# type: ignore
"""
LangGraph orchestration for MyAnalyst.

Two graphs live here:

  * EDA graph  - runs once, automatically, right after ingestion/remediation.
                 Planner -> ChartBuilder -> [Forecaster] -> Summarizer -> END
  * Q&A graph  - runs once per user question. Cyclic: a failed Executor run
                 routes back to the Coder node (bounded by MAX_CODER_RETRIES)
                 instead of failing the whole request.
                 Planner -> Coder -> Executor -> (Coder | Summarizer | GiveUp)
"""
from __future__ import annotations

import operator
from typing import Annotated, Any, TypedDict

import numpy as np
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from langgraph.graph import END, START, StateGraph
import forecasting

import llm
import memory
from config import settings
from sandbox import ExecutionResult, execute_code_in_docker



# ==========================================================================
# Workflow step 3: Proactive EDA & Forecasting
# ==========================================================================


class EDAState(TypedDict, total=False):
    df: pd.DataFrame
    metadata: dict[str, Any]
    cleaning_log: list[dict[str, Any]]
    flagged_ids: set[str]
    chart_specs: list[dict[str, Any]]
    charts: list[dict[str, Any]]
    datetime_column: str | None
    numeric_columns: list[str]
    categorical_columns: list[str]
    executive_summary: str


def _eda_planner_node(state: EDAState) -> dict[str, Any]:
    """Selects 3-4 chart specs to build, purely from column dtypes."""
    df = state["df"]
    flagged = state.get("flagged_ids", set())
    analysis_cols = [c for c in df.columns if c not in flagged]

    numeric_cols = [c for c in analysis_cols if pd.api.types.is_numeric_dtype(df[c])]
    categorical_cols = [
        c for c in analysis_cols
        if not pd.api.types.is_numeric_dtype(df[c]) and not pd.api.types.is_datetime64_any_dtype(df[c])
    ]
    datetime_cols = [c for c in analysis_cols if pd.api.types.is_datetime64_any_dtype(df[c])]
    datetime_col = datetime_cols[0] if datetime_cols else None

    specs: list[dict[str, Any]] = []

    if numeric_cols:
        specs.append({"type": "histogram", "x": numeric_cols[0],
                       "title": f"Distribution of {numeric_cols[0]}"})

    if len(numeric_cols) >= 2:
        specs.append({"type": "scatter", "x": numeric_cols[0], "y": numeric_cols[1],
                       "title": f"{numeric_cols[1]} vs. {numeric_cols[0]}"})

    if categorical_cols:
        specs.append({"type": "bar_counts", "x": categorical_cols[0],
                       "title": f"Counts by {categorical_cols[0]}"})

    if datetime_col and numeric_cols:
        specs.append({"type": "time_series", "x": datetime_col, "y": numeric_cols[0],
                       "title": f"{numeric_cols[0]} over time"})
    elif categorical_cols and numeric_cols:
        specs.append({"type": "box", "x": categorical_cols[0], "y": numeric_cols[0],
                       "title": f"{numeric_cols[0]} by {categorical_cols[0]}"})

    specs = specs[:4]  # cap at 4 per the workflow spec (min 3 when data allows it)

    return {
        "chart_specs": specs,
        "datetime_column": datetime_col,
        "numeric_columns": numeric_cols,
        "categorical_columns": categorical_cols,
    }


def _build_figure(df: pd.DataFrame, spec: dict[str, Any]) -> go.Figure:
    chart_type = spec["type"]
    if chart_type == "histogram":
        return px.histogram(df, x=spec["x"], title=spec["title"])
    if chart_type == "scatter":
        return px.scatter(df, x=spec["x"], y=spec["y"], title=spec["title"])
    if chart_type == "bar_counts":
        counts = df[spec["x"]].value_counts().head(20).reset_index()
        counts.columns = [spec["x"], "count"]
        return px.bar(counts, x=spec["x"], y="count", title=spec["title"])
    if chart_type == "time_series":
        ts = df[[spec["x"], spec["y"]]].dropna().sort_values(spec["x"])
        return px.line(ts, x=spec["x"], y=spec["y"], title=spec["title"])
    if chart_type == "box":
        return px.box(df, x=spec["x"], y=spec["y"], title=spec["title"])
    raise ValueError(f"Unknown chart spec type: {chart_type}")


def _chart_builder_node(state: EDAState) -> dict[str, Any]:
    df = state["df"]
    charts: list[dict[str, Any]] = []
    for spec in state.get("chart_specs", []):
        try:
            fig = _build_figure(df, spec)
            charts.append({"title": spec["title"], "type": spec["type"], "plotly_json": fig.to_json()})
        except Exception as exc:  # a single bad chart should never sink the whole EDA run
            charts.append({"title": spec["title"], "type": spec["type"], "error": str(exc)})
    return {"charts": charts}

def _forecast_node(state: EDAState) -> dict[str, Any]:
    df = state["df"]
    datetime_col = state.get("datetime_column")
    numeric_cols = state.get("numeric_columns", [])
    charts = list(state.get("charts", []))

    if datetime_col and numeric_cols:
        try:
            # Delegate to the autonomous mathematical routing module
            fig = forecasting.generate_autonomous_forecast(df, datetime_col, numeric_cols[0])
            charts.append({
                "title": f"{numeric_cols[0]} forecast",
                "type": "forecast",
                "plotly_json": fig.to_json(),
            })
        except Exception as exc:
            charts.append({"title": "Forecast", "type": "forecast", "error": str(exc)})

    return {"charts": charts}


def _route_after_charts(state: EDAState) -> str:
    return "forecast" if state.get("datetime_column") else "summarize"


def _eda_summarizer_node(state: EDAState) -> dict[str, Any]:
    df = state["df"]
    chart_descriptions = [c["title"] for c in state.get("charts", [])]
    
    # Extract concrete data insights so the LLM can actually explain the charts
    data_insights = []
    
    # Numeric Distribution Insights
    for col in state.get("numeric_columns", [])[:2]:
        desc = df[col].describe()
        data_insights.append(
            f"- {col} Distribution: averages {desc['mean']:.2f}, "
            f"ranging from {desc['min']:.2f} to {desc['max']:.2f}."
        )
        
    # Categorical Count Insights
    for col in state.get("categorical_columns", [])[:2]:
        counts = df[col].value_counts().head(3)
        top_vals = ", ".join([f"{k} ({v} occurrences)" for k, v in counts.items()])
        data_insights.append(f"- {col} Top Categories: {top_vals}.")
        
    # Time-Series & Forecast Insights
    dt_col = state.get("datetime_column")
    if dt_col and state.get("numeric_columns"):
        num_col = state.get("numeric_columns")[0]
        ts = df[[dt_col, num_col]].dropna().sort_values(dt_col)
        if not ts.empty:
            start_date, end_date = ts.iloc[0][dt_col], ts.iloc[-1][dt_col]
            start_val, end_val = ts.iloc[0][num_col], ts.iloc[-1][num_col]
            trend_dir = "an upward" if end_val > start_val else "a downward"
            data_insights.append(
                f"- {num_col} Time Series: Spans from {start_date} to {end_date}. "
                f"Exhibits {trend_dir} historical trend (moving from {start_val:.2f} to {end_val:.2f})."
            )

    summary = llm.generate_executive_summary(
        metadata=state["metadata"],
        cleaning_log=state.get("cleaning_log", []),
        chart_descriptions=chart_descriptions,
        data_insights=data_insights,  # Pass the newly extracted insights
    )
    return {"executive_summary": summary}


def build_eda_graph():
    graph = StateGraph(EDAState)
    graph.add_node("plan", _eda_planner_node)
    graph.add_node("build_charts", _chart_builder_node)
    graph.add_node("forecast", _forecast_node)
    graph.add_node("summarize", _eda_summarizer_node)

    graph.add_edge(START, "plan")
    graph.add_edge("plan", "build_charts")
    graph.add_conditional_edges("build_charts", _route_after_charts, {
        "forecast": "forecast",
        "summarize": "summarize",
    })
    graph.add_edge("forecast", "summarize")
    graph.add_edge("summarize", END)
    return graph.compile()


_eda_graph = build_eda_graph()


def run_eda_workflow(
    df: pd.DataFrame,
    metadata: dict[str, Any],
    cleaning_log: list[dict[str, Any]],
    flagged_ids: set[str],
) -> EDAState:
    initial_state: EDAState = {
        "df": df,
        "metadata": metadata,
        "cleaning_log": cleaning_log,
        "flagged_ids": flagged_ids,
    }
    return _eda_graph.invoke(initial_state)


# ==========================================================================
# Workflow step 4: The Q&A Loop (cyclic agent state machine)
# ==========================================================================


class QAState(TypedDict, total=False):
    # Conversation
    messages: Annotated[list[dict[str, str]], operator.add]
    question: str
    session_id: str

    # Context pulled from persistence (SQLite)
    dataset_id: str
    file_path: str
    data_dictionary: list[dict[str, Any]]
    business_rules: list[str]

    # Working memory
    plan: str
    current_code: str
    execution_output: dict[str, Any]
    errors: Annotated[list[str], operator.add]
    attempts: int

    # Output
    final_answer: str
    succeeded: bool


def _qa_planner_node(state: QAState) -> dict[str, Any]:
    dataset = memory.get_dataset(state["dataset_id"])
    if dataset is None:
        raise ValueError(f"Unknown dataset_id: {state['dataset_id']}")
    rule_rows = memory.get_business_rules(state["dataset_id"])
    business_rules = [r["rule_text"] for r in rule_rows]
    history = memory.get_chat_history(state["session_id"])

    plan = llm.generate_plan(
        question=state["question"],
        data_dictionary=dataset.data_dictionary,
        business_rules=business_rules,
        chat_history=[{"role": h["role"], "content": h["content"]} for h in history],
        executive_summary=dataset.executive_summary, # extract and pass the memory
    )

    memory.add_chat_message(state["session_id"], state["dataset_id"], "user", state["question"])

    return {
        "file_path": dataset.file_path,
        "data_dictionary": dataset.data_dictionary,
        "business_rules": business_rules,
        "plan": plan,
        "attempts": 0,
        "messages": [{"role": "user", "content": state["question"]}],
    }


def _qa_coder_node(state: QAState) -> dict[str, Any]:
    prior_error = state["errors"][-1] if state.get("errors") else None
    code = llm.generate_code(
        plan=state["plan"],
        data_dictionary=state["data_dictionary"],
        file_path=state["file_path"],
        prior_code=state.get("current_code"),
        prior_error=prior_error,
    )
    return {"current_code": code, "attempts": state.get("attempts", 0) + 1}



def _qa_executor_node(state: QAState) -> dict[str, Any]:
    result: ExecutionResult = execute_code_in_docker(state["current_code"], state["file_path"])
    
    if result.success:
        return {
            "execution_output": {
                "result": result.result,
                "stdout": result.stdout,
                "plotly_json": result.plotly_json,
            },
            "succeeded": True,
        }
        
    # Combine the top-level error with the detailed traceback/logs 
    # so the LLM isn't flying blind during its retry attempts.
    error_msg = result.error or "Unknown execution error"
    if result.traceback:
        error_msg += f"\nDetailed Logs/Traceback:\n{result.traceback}"
        
    return {
        "errors": [error_msg],
        "succeeded": False,
    }


def _route_after_execution(state: QAState) -> str:
    if state.get("succeeded"):
        return "summarize"
    if state.get("attempts", 0) < settings.MAX_CODER_RETRIES:
        return "retry"
    return "give_up"


def _qa_prescriptive_summarizer_node(state: QAState) -> dict[str, Any]:
    summary = llm.generate_prescriptive_summary(
        question=state["question"],
        execution_output=state.get("execution_output", {}),
        business_rules=state.get("business_rules", []),
    )
    memory.add_chat_message(state["session_id"], state["dataset_id"], "assistant", summary)
    return {"final_answer": summary, "messages": [{"role": "assistant", "content": summary}]}


def _qa_give_up_node(state: QAState) -> dict[str, Any]:
    last_error = state["errors"][-1] if state.get("errors") else "unknown error"
    message = (
        "I wasn't able to produce a working analysis after "
        f"{state.get('attempts', 0)} attempts. The last error was: {last_error}. "
        "Try rephrasing the question or simplifying what's being asked."
    )
    memory.add_chat_message(state["session_id"], state["dataset_id"], "assistant", message)
    return {"final_answer": message, "messages": [{"role": "assistant", "content": message}]}


def build_qa_graph():
    graph = StateGraph(QAState)
    graph.add_node("plan", _qa_planner_node)
    graph.add_node("code", _qa_coder_node)
    graph.add_node("execute", _qa_executor_node)
    graph.add_node("summarize", _qa_prescriptive_summarizer_node)
    graph.add_node("give_up", _qa_give_up_node)

    graph.add_edge(START, "plan")
    graph.add_edge("plan", "code")
    graph.add_edge("code", "execute")
    graph.add_conditional_edges("execute", _route_after_execution, {
        "retry": "code",       # <-- the cyclic error-correction edge
        "summarize": "summarize",
        "give_up": "give_up",
    })
    graph.add_edge("summarize", END)
    graph.add_edge("give_up", END)
    return graph.compile()


_qa_graph = build_qa_graph()


def run_qa_workflow(dataset_id: str, session_id: str, question: str) -> QAState:
    initial_state: QAState = {
        "dataset_id": dataset_id,
        "session_id": session_id,
        "question": question,
        "messages": [],
        "errors": [],
    }
    return _qa_graph.invoke(initial_state)
