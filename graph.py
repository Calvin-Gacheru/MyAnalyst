# type: ignore
"""
LangGraph orchestration for MyAnalyst.

Two graphs live here:

  * EDA graph  - runs once, automatically, right after ingestion/remediation.
                 Planner -> ChartBuilder -> [Forecaster] -> Summarizer -> END
  * Q&A graph  - runs once per user question. A router picks one of three
                 tracks from the workspace's files and the question:
                   quant  : Planner -> Coder -> Executor -> (Coder | Summarizer | GiveUp)
                   doc    : Retrieve -> Synthesize
                   hybrid : Retrieve -> Planner -> ... (quant track, with doc context)
                 The quant track is cyclic: a failed Executor run routes back to the
                 Coder node (bounded by MAX_CODER_RETRIES) instead of failing the request.
"""
from __future__ import annotations

import json
import logging
import operator
import re
from typing import Annotated, Any, TypedDict

import numpy as np
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from langgraph.graph import END, START, StateGraph
import forecasting

import llm
import memory
import rag
from config import settings
from sandbox import ExecutionResult, execute_code_in_docker

logger = logging.getLogger(__name__)



# ==========================================================================
# Workflow step 3: Proactive EDA & Forecasting
# ==========================================================================


class EDAState(TypedDict, total=False):
    df: pd.DataFrame
    metadata: dict[str, Any]
    cleaning_log: list[dict[str, Any]]
    flagged_ids: set[str]
    data_dictionary: list[dict[str, Any]]
    chart_specs: list[dict[str, Any]]
    charts: list[dict[str, Any]]
    datetime_column: str | None
    numeric_columns: list[str]  # most informative first (see _rank_numeric)
    categorical_columns: list[str]
    executive_summary: str


# The charts the builder knows how to draw, and which column role each axis needs.
# The LLM picks from this menu; anything outside it is discarded by _validate_spec.
EDA_CHART_MENU: dict[str, dict[str, Any]] = {
    "bar_agg": {"x": "categorical", "y": "numeric", "agg": True,
                "description": "a numeric column aggregated per category (agg: sum or mean), top 20 categories"},
    "time_series": {"x": "datetime", "y": "numeric", "agg": True, "color": True,
                    "description": "a numeric column aggregated per day/week/month (agg: sum or mean); "
                                   "optional 'color' splits the line by a categorical column with at most 8 values"},
    "histogram": {"x": "numeric", "description": "distribution of one numeric column"},
    "box": {"x": "categorical", "y": "numeric", "description": "spread of a numeric column within each category"},
    "scatter": {"x": "numeric", "y": "numeric", "description": "relationship between two numeric columns"},
    "bar_counts": {"x": "categorical", "description": "number of rows per category"},
}
EDA_MAX_CHARTS = 4
EDA_MIN_CHARTS = 3

# Column names that usually hold the money / volume a business tracks.
_METRIC_NAME = re.compile(
    r"amount|revenue|sales|price|cost|spend|profit|money|income|value|total|fee|margin|"
    r"quantity|qty|volume|units|users|orders|visits|clicks",
    re.IGNORECASE,
)
# Levels are snapshots (users active today, a price, a rating): they add up across segments
# on the same date, but across time they average rather than sum.
_LEVEL_NAME = re.compile(
    r"users|active|subscribers|members|headcount|balance|inventory|stock|price|rate|ratio|percent|pct|score|rating",
    re.IGNORECASE,
)
_CHARTABLE_CATEGORIES = (2, 30)  # fewer is constant, more is unreadable as bars
_COLOR_MAX_CATEGORIES = 8


def _profile_columns(df: pd.DataFrame, flagged: set[str]) -> dict[str, list[dict[str, Any]]]:
    """Per-role column facts used both to rank columns and to brief the LLM."""
    numeric, categorical, datetime = [], [], []
    for col in df.columns:
        if col in flagged:
            continue
        series = df[col].dropna()
        n_unique = int(series.nunique())
        if pd.api.types.is_datetime64_any_dtype(df[col]):
            if n_unique >= 3:
                datetime.append({"name": col, "n_unique": n_unique,
                                 "start": str(series.min()), "end": str(series.max())})
        elif pd.api.types.is_numeric_dtype(df[col]) and not pd.api.types.is_bool_dtype(df[col]):
            if n_unique < 2:
                continue
            mean = float(series.mean())
            numeric.append({
                "name": col,
                "n_unique": n_unique,
                "mean": round(mean, 3),
                "coef_of_variation": round(float(series.std()) / abs(mean), 3) if mean else None,
                "looks_like_metric": bool(_METRIC_NAME.search(str(col))),
            })
        else:
            lo, hi = _CHARTABLE_CATEGORIES
            if lo <= n_unique <= hi:
                top_share = float(series.value_counts(normalize=True).iloc[0])
                categorical.append({"name": col, "n_unique": n_unique, "top_value_share": round(top_share, 3)})
    return {"numeric": numeric, "categorical": categorical, "datetime": datetime}


def _rank_numeric(profiles: list[dict[str, Any]]) -> list[str]:
    """Business metrics first, then columns with enough distinct values and spread to be interesting."""
    def score(p: dict[str, Any]) -> float:
        cv = p["coef_of_variation"] or 0.0
        return 3 * p["looks_like_metric"] + (p["n_unique"] >= 10) + min(abs(cv), 1.5)
    return [p["name"] for p in sorted(profiles, key=score, reverse=True)]


def _rank_categorical(profiles: list[dict[str, Any]]) -> list[str]:
    """A handful of segments reads best; a single dominant value says little."""
    def score(p: dict[str, Any]) -> float:
        size = 2 if 3 <= p["n_unique"] <= 15 else 1
        return size - p["top_value_share"]
    return [p["name"] for p in sorted(profiles, key=score, reverse=True)]


def _default_agg(column: str) -> str:
    # Totals are what matter for money and volume; averages for levels and everything else.
    if _LEVEL_NAME.search(str(column)):
        return "mean"
    return "sum" if _METRIC_NAME.search(str(column)) else "mean"


def _time_aggs(column: str, agg: str) -> tuple[str, str]:
    """(how rows sharing a timestamp combine, how timestamps within a period combine).
    E.g. daily active users: sum the platforms on each day, then average the days of a week."""
    stamp_agg = "sum" if _METRIC_NAME.search(str(column)) or agg == "sum" else "mean"
    period_agg = "mean" if _LEVEL_NAME.search(str(column)) else agg
    return stamp_agg, period_agg


def _spec_title(spec: dict[str, Any]) -> str:
    x, y, agg = spec.get("x"), spec.get("y"), spec.get("agg")
    return {
        "bar_agg": f"{'Total' if agg == 'sum' else 'Average'} {y} by {x}",
        "time_series": f"{'Total' if agg == 'sum' else 'Average'} {y} over time" + (f" by {spec['color']}" if spec.get("color") else ""),
        "histogram": f"Distribution of {x}",
        "box": f"{y} by {x}",
        "scatter": f"{y} vs. {x}",
        "bar_counts": f"Rows by {x}",
    }[spec["type"]]


def _heuristic_chart_specs(numeric: list[str], categorical: list[str], datetime_cols: list[str]) -> list[dict[str, Any]]:
    """Rule-based fallback when the LLM's pick is missing or unusable: lead with the top metric."""
    metric = numeric[0] if numeric else None
    candidates: list[dict[str, Any]] = []
    if metric and datetime_cols:
        candidates.append({"type": "time_series", "x": datetime_cols[0], "y": metric, "agg": _default_agg(metric),
                           "rationale": f"How {metric} has moved over time."})
    if metric and categorical:
        candidates.append({"type": "bar_agg", "x": categorical[0], "y": metric, "agg": _default_agg(metric),
                           "rationale": f"Which {categorical[0]} contributes most to {metric}."})
    if metric:
        candidates.append({"type": "histogram", "x": metric,
                           "rationale": f"The typical range of {metric} and how skewed it is."})
    if metric and len(categorical) > 1:
        candidates.append({"type": "bar_agg", "x": categorical[1], "y": metric, "agg": _default_agg(metric),
                           "rationale": f"How {metric} splits across {categorical[1]}."})
    if len(numeric) > 1:
        candidates.append({"type": "scatter", "x": numeric[1], "y": metric,
                           "rationale": f"Whether {numeric[1]} moves together with {metric}."})
    if categorical and not metric:
        candidates.append({"type": "bar_counts", "x": categorical[0],
                           "rationale": f"How rows are spread across {categorical[0]}."})
    for spec in candidates:
        spec["title"] = _spec_title(spec)
    return candidates


def _validate_spec(raw: Any, roles: dict[str, set[str]], color_ok: set[str]) -> dict[str, Any] | None:
    """Keeps an LLM-proposed chart only if it is on the menu and every column fits its role."""
    if not isinstance(raw, dict) or raw.get("type") not in EDA_CHART_MENU:
        return None
    menu = EDA_CHART_MENU[raw["type"]]
    spec: dict[str, Any] = {"type": raw["type"]}
    for axis in ("x", "y"):
        role = menu.get(axis)
        if role:
            if raw.get(axis) not in roles[role]:
                return None
            spec[axis] = raw[axis]
    if spec.get("x") is not None and spec.get("x") == spec.get("y"):
        return None
    if menu.get("agg"):
        spec["agg"] = raw.get("agg") if raw.get("agg") in ("sum", "mean") else _default_agg(spec["y"])
    if menu.get("color") and raw.get("color") in color_ok:
        spec["color"] = raw["color"]
    title = raw.get("title")
    spec["title"] = title.strip()[:90] if isinstance(title, str) and title.strip() else _spec_title(spec)
    why = raw.get("why")
    spec["rationale"] = why.strip()[:240] if isinstance(why, str) else ""
    return spec


def _spec_key(spec: dict[str, Any]) -> tuple:
    return (spec["type"], spec.get("x"), spec.get("y"), spec.get("color"))


def _eda_planner_node(state: EDAState) -> dict[str, Any]:
    """Picks 3-4 charts: the LLM chooses from EDA_CHART_MENU using the column profile and
    data dictionary; invalid or missing picks are filled from the rule-based ranking."""
    df = state["df"]
    profile = _profile_columns(df, state.get("flagged_ids", set()))
    numeric_cols = _rank_numeric(profile["numeric"])
    categorical_cols = _rank_categorical(profile["categorical"])
    datetime_cols = [p["name"] for p in profile["datetime"]]
    roles = {"numeric": set(numeric_cols), "categorical": set(categorical_cols), "datetime": set(datetime_cols)}
    color_ok = {p["name"] for p in profile["categorical"] if p["n_unique"] <= _COLOR_MAX_CATEGORIES}

    try:
        proposed = llm.select_eda_charts(
            column_profile=profile,
            data_dictionary=state.get("data_dictionary", []),
            chart_menu=EDA_CHART_MENU,
            max_charts=EDA_MAX_CHARTS,
        ) or []
    except Exception:
        logger.exception("LLM chart selection failed; using rule-based charts")
        proposed = []

    specs: list[dict[str, Any]] = []
    seen: set[tuple] = set()

    def add(spec: dict[str, Any] | None) -> None:
        if spec and _spec_key(spec) not in seen and len(specs) < EDA_MAX_CHARTS:
            specs.append(spec)
            seen.add(_spec_key(spec))

    for raw in proposed:
        add(_validate_spec(raw, roles, color_ok))
    if len(specs) < EDA_MIN_CHARTS:
        for spec in _heuristic_chart_specs(numeric_cols, categorical_cols, datetime_cols):
            add(spec)

    return {
        "chart_specs": specs,
        "datetime_column": datetime_cols[0] if datetime_cols else None,
        "numeric_columns": numeric_cols,
        "categorical_columns": categorical_cols,
    }


def _time_bucket(dates: pd.Series) -> str:
    # Aim for a readable line: roughly 30-150 points across the dataset's span.
    span_days = (dates.max() - dates.min()).days
    return "MS" if span_days > 730 else "W" if span_days > 120 else "D"


def _build_figure(df: pd.DataFrame, spec: dict[str, Any]) -> go.Figure:
    chart_type, x, y, title = spec["type"], spec.get("x"), spec.get("y"), spec["title"]
    if chart_type == "histogram":
        return px.histogram(df, x=x, title=title)
    if chart_type == "scatter":
        return px.scatter(df, x=x, y=y, title=title, opacity=0.6)
    if chart_type == "bar_counts":
        counts = df[x].astype(str).value_counts().head(20).reset_index()
        counts.columns = [x, "rows"]
        return px.bar(counts, x=x, y="rows", title=title)
    if chart_type == "bar_agg":
        agg = df.groupby(df[x].astype(str))[y].agg(spec["agg"]).sort_values(ascending=False).head(20).reset_index()
        return px.bar(agg, x=x, y=y, title=title, labels={y: f"{spec['agg']} of {y}"})
    if chart_type == "time_series":
        # Many rows can share a timestamp (transactions, regions), so combine them, then bucket.
        stamp_agg, period_agg = _time_aggs(y, spec["agg"])
        split = [spec["color"]] if spec.get("color") else []
        rows = df.dropna(subset=[x, y])
        per_stamp = rows.groupby([x, *split], observed=True)[y].agg(stamp_agg).reset_index()
        bucket = pd.Grouper(key=x, freq=_time_bucket(per_stamp[x]))
        ts = per_stamp.groupby([bucket, *split], observed=True)[y].agg(period_agg).dropna().reset_index()
        return px.line(ts, x=x, y=y, color=spec.get("color"), title=title, markers=len(ts) <= 60,
                       labels={y: f"{period_agg} of {y}"})
    if chart_type == "box":
        return px.box(df, x=x, y=y, title=title)
    raise ValueError(f"Unknown chart spec type: {chart_type}")


def _chart_builder_node(state: EDAState) -> dict[str, Any]:
    df = state["df"]
    charts: list[dict[str, Any]] = []
    for spec in state.get("chart_specs", []):
        try:
            fig = _build_figure(df, spec)
            charts.append({"title": spec["title"], "type": spec["type"], "rationale": spec.get("rationale", ""),
                           "plotly_json": fig.to_json()})
        except Exception as exc:  # a single bad chart should never sink the whole EDA run
            charts.append({"title": spec["title"], "type": spec["type"], "error": str(exc)})
    return {"charts": charts}

def _forecast_node(state: EDAState) -> dict[str, Any]:
    df = state["df"]
    datetime_col = state.get("datetime_column")
    numeric_cols = state.get("numeric_columns", [])
    charts = list(state.get("charts", []))

    if datetime_col and numeric_cols:
        metric = numeric_cols[0]  # the planner ranks the key business metric first
        try:
            # Delegate to the autonomous mathematical routing module
            stamp_agg, period_agg = _time_aggs(metric, _default_agg(metric))
            result = forecasting.generate_autonomous_forecast(df, datetime_col, metric, stamp_agg=stamp_agg, period_agg=period_agg)
            if result:
                fig, rationale = result
                charts.append({
                    "title": f"{metric} forecast",
                    "type": "forecast",
                    "rationale": rationale,
                    "plotly_json": fig.to_json(),
                })
        except Exception as exc:
            logger.exception("Forecast failed for %s", metric)
            charts.append({"title": "Forecast", "type": "forecast", "error": str(exc)})

    return {"charts": charts}


def _route_after_charts(state: EDAState) -> str:
    return "forecast" if state.get("datetime_column") else "summarize"


def _eda_summarizer_node(state: EDAState) -> dict[str, Any]:
    df = state["df"]
    chart_descriptions = [f"{c['title']}: {c['rationale']}" if c.get("rationale") else c["title"] for c in state.get("charts", [])]
    
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
    data_dictionary: list[dict[str, Any]] | None = None,
) -> EDAState:
    initial_state: EDAState = {
        "df": df,
        "metadata": metadata,
        "cleaning_log": cleaning_log,
        "flagged_ids": flagged_ids,
        "data_dictionary": data_dictionary or [],
    }
    return _eda_graph.invoke(initial_state)


### ==========================================================================
### Workflow step 4: The Q&A Loop (Dual-Track Agent State Machine)
### ==========================================================================
class QAState(TypedDict, total=False):
    workspace_id: str
    session_id: str
    question: str
    intent: str  # 'quant' | 'doc' | 'hybrid' | 'none'

    # Workspace context, loaded once by the router
    tabular_files: dict[str, str]  # original filename -> cleaned CSV path on host
    document_files: list[str]
    data_dictionary: list[dict[str, Any]]  # one entry per tabular file
    business_rules: list[str]
    chat_history: list[dict[str, str]]  # prior turns only, excludes this question
    executive_summary: str

    # Quant Path (Tabular)
    plan: str
    current_code: str
    execution_output: dict[str, Any]
    errors: Annotated[list[str], operator.add]
    attempts: int

    # Doc Path (Unstructured RAG); also feeds the hybrid path
    retrieved_chunks: list[dict[str, Any]]
    sources: list[dict[str, Any]]

    # Shared Output
    final_answer: str
    succeeded: bool


def _log_assistant_message(state: QAState, content: str) -> None:
    with memory.SessionLocal() as db:
        db.add(memory.ChatMessage(
            session_id=state["session_id"],
            workspace_id=state["workspace_id"],
            role="assistant",
            content=content,
        ))
        db.commit()


def _sources_from_chunks(chunks: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """One citation per (file, page). Chunks arrive ranked, so the excerpt kept for
    each is the most relevant passage on that page (shown in the UI's hover preview)."""
    seen, sources = set(), []
    for c in chunks:
        key = (c["filename"], c["page_number"])
        if key not in seen:
            seen.add(key)
            sources.append({"filename": c["filename"], "page": c["page_number"] or None, "excerpt": c["content"]})
    return sources


def _load_data_dictionary(wf: memory.WorkspaceFile) -> dict[str, Any]:
    """The LLM-written dictionary persisted at upload; dtypes from the file as a fallback."""
    meta = json.loads(wf.parsed_metadata or "{}")
    columns = meta.get("data_dictionary")
    if not columns:
        df_sample = pd.read_csv(wf.file_path, nrows=5)
        columns = [{"column": col, "data_type": str(dtype)} for col, dtype in df_sample.dtypes.items()]
    return {"filename": wf.filename, "columns": columns}


def _qa_router_node(state: QAState) -> dict[str, Any]:
    workspace_id = state["workspace_id"]

    with memory.SessionLocal() as db:
        ws = db.query(memory.Workspace).filter_by(workspace_id=workspace_id).first()
        if not ws:
            raise ValueError(f"Workspace '{workspace_id}' does not exist. Upload files first.")

        files = db.query(memory.WorkspaceFile).filter_by(workspace_id=workspace_id).order_by(memory.WorkspaceFile.created_at).all()
        tabular = [f for f in files if f.file_type == "tabular"]
        documents = [f.filename for f in files if f.file_type == "document"]

        rules = db.query(memory.BusinessRule).filter_by(workspace_id=workspace_id).all()

        # Read history BEFORE logging this question so it isn't duplicated in prompts.
        history = (
            db.query(memory.ChatMessage)
            .filter_by(workspace_id=workspace_id, session_id=state["session_id"])
            .order_by(memory.ChatMessage.id)
            .all()
        )
        context = {
            "tabular_files": {f.filename: f.file_path for f in tabular},
            "document_files": documents,
            "data_dictionary": [_load_data_dictionary(f) for f in tabular],
            "business_rules": [r.rule_text for r in rules],
            "chat_history": [{"role": h.role, "content": h.content} for h in history],
            "executive_summary": ws.executive_summary or "",
        }

        db.add(memory.ChatMessage(
            session_id=state["session_id"],
            workspace_id=workspace_id,
            role="user",
            content=state["question"],
        ))
        db.commit()

    # Only ask the LLM to choose when both kinds of data actually exist.
    if tabular and documents:
        intent = llm.classify_intent(state["question"], list(context["tabular_files"]), documents)
        if intent not in llm.INTENTS:
            intent = "hybrid"
    elif tabular:
        intent = "quant"
    elif documents:
        intent = "doc"
    else:
        intent = "none"

    return {**context, "intent": intent}


def _route_after_intent(state: QAState) -> str:
    # Hybrid retrieves document context first, then hands it to the quant planner.
    return {"quant": "plan", "doc": "rag_retrieve", "hybrid": "rag_retrieve"}.get(state["intent"], "no_data")


def _qa_no_data_node(state: QAState) -> dict[str, Any]:
    message = "This workspace has no files yet. Upload a CSV/XLSX dataset or a PDF/DOCX/TXT document first."
    _log_assistant_message(state, message)
    return {"final_answer": message}

### --- QUANTITATIVE TRACK (PANDAS/DOCKER) ---
def _qa_planner_node(state: QAState) -> dict[str, Any]:
    plan = llm.generate_plan(
        question=state["question"],
        data_dictionary=state["data_dictionary"],
        business_rules=state.get("business_rules", []),
        chat_history=state.get("chat_history", []),
        executive_summary=state.get("executive_summary", ""),
        document_excerpts=state.get("retrieved_chunks"),
    )
    return {"plan": plan, "attempts": 0}

def _qa_coder_node(state: QAState) -> dict[str, Any]:
    prior_error = state["errors"][-1] if state.get("errors") else None
    code = llm.generate_code(
        plan=state["plan"],
        data_dictionary=state["data_dictionary"],
        filenames=list(state["tabular_files"]),
        prior_code=state.get("current_code"),
        prior_error=prior_error,
    )
    return {"current_code": code, "attempts": state.get("attempts", 0) + 1}

def _qa_executor_node(state: QAState) -> dict[str, Any]:
    result: ExecutionResult = execute_code_in_docker(state["current_code"], state["tabular_files"])
    if result.success:
        return {
            "execution_output": {
                "result": result.result,
                "stdout": result.stdout,
                "plotly_json": result.plotly_json,
            },
            "succeeded": True,
        }

    error_msg = result.error or "Unknown execution error"
    if result.traceback:
        error_msg += f"\nDetailed Logs/Traceback:\n{result.traceback}"

    return {"errors": [error_msg], "succeeded": False}

def _route_after_execution(state: QAState) -> str:
    if state.get("succeeded"):
        return "summarize"
    if state.get("attempts", 0) < settings.MAX_CODER_RETRIES:
        return "retry"
    return "give_up"

def _qa_prescriptive_summarizer_node(state: QAState) -> dict[str, Any]:
    chunks = state.get("retrieved_chunks", [])
    summary = llm.generate_prescriptive_summary(
        question=state["question"],
        execution_output=state.get("execution_output", {}),
        business_rules=state.get("business_rules", []),
        document_excerpts=chunks,
    )
    _log_assistant_message(state, summary)
    return {"final_answer": summary, "sources": _sources_from_chunks(chunks)}

def _qa_give_up_node(state: QAState) -> dict[str, Any]:
    last_error = state["errors"][-1] if state.get("errors") else "unknown error"
    # Only the first line of the error; the full traceback is still returned in `errors`.
    message = (
        f"I wasn't able to produce a working analysis after {state.get('attempts', 0)} attempts. "
        f"The last error was: {last_error.splitlines()[0]}. Try rephrasing the question or simplifying what's being asked."
    )
    _log_assistant_message(state, message)
    return {"final_answer": message, "sources": _sources_from_chunks(state.get("retrieved_chunks", []))}

### --- QUALITATIVE TRACK (DOCUMENT RAG) ---
def _qa_rag_retrieve_node(state: QAState) -> dict[str, Any]:
    chunks = rag.search_documents(state["workspace_id"], state["question"])
    return {"retrieved_chunks": chunks}

def _route_after_retrieval(state: QAState) -> str:
    return "plan" if state["intent"] == "hybrid" else "rag_synthesize"

def _qa_rag_synthesizer_node(state: QAState) -> dict[str, Any]:
    chunks = state.get("retrieved_chunks", [])
    answer = llm.generate_rag_synthesis(state["question"], chunks, state.get("chat_history"))
    _log_assistant_message(state, answer)
    return {"final_answer": answer, "sources": _sources_from_chunks(chunks)}

### --- GRAPH COMPILATION ---
#
#   START -> route_intent -+-> plan -> code -> execute -+-> summarize -> END      (quant)
#                          |             ^              +-> code (retry)
#                          |             |              +-> give_up -> END
#                          +-> rag_retrieve -+-> rag_synthesize -> END           (doc)
#                          |                 +-> plan ...                        (hybrid)
#                          +-> no_data -> END                                    (empty workspace)
def build_qa_graph():
    graph = StateGraph(QAState)

    # Entry Point Router
    graph.add_node("route_intent", _qa_router_node)
    graph.add_node("no_data", _qa_no_data_node)

    # Quant Nodes
    graph.add_node("plan", _qa_planner_node)
    graph.add_node("code", _qa_coder_node)
    graph.add_node("execute", _qa_executor_node)
    graph.add_node("summarize", _qa_prescriptive_summarizer_node)
    graph.add_node("give_up", _qa_give_up_node)

    # RAG Nodes
    graph.add_node("rag_retrieve", _qa_rag_retrieve_node)
    graph.add_node("rag_synthesize", _qa_rag_synthesizer_node)

    # Routing Logic
    graph.add_edge(START, "route_intent")
    graph.add_conditional_edges("route_intent", _route_after_intent, {
        "plan": "plan",
        "rag_retrieve": "rag_retrieve",
        "no_data": "no_data",
    })
    graph.add_edge("no_data", END)

    # Quant Edges
    graph.add_edge("plan", "code")
    graph.add_edge("code", "execute")
    graph.add_conditional_edges("execute", _route_after_execution, {
        "retry": "code",
        "summarize": "summarize",
        "give_up": "give_up",
    })
    graph.add_edge("summarize", END)
    graph.add_edge("give_up", END)

    # RAG Edges (hybrid continues into the quant planner with the retrieved context)
    graph.add_conditional_edges("rag_retrieve", _route_after_retrieval, {
        "plan": "plan",
        "rag_synthesize": "rag_synthesize",
    })
    graph.add_edge("rag_synthesize", END)

    return graph.compile()

_qa_graph = build_qa_graph()

def run_qa_workflow(workspace_id: str, session_id: str, question: str) -> dict[str, Any]:
    initial_state: QAState = {
        "workspace_id": workspace_id,
        "session_id": session_id,
        "question": question,
        "errors": [],
    }
    return _qa_graph.invoke(initial_state)
