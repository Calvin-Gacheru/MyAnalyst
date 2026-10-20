# type: ignore
"""
All LLM calls funnel through this module.

Keeping prompt construction and response parsing in one place makes the
rest of the codebase (preprocessing.py, graph.py) read as plain business
logic, and makes it trivial to swap models or add retries/observability
in a single spot later.
"""
from __future__ import annotations

import base64
import json
import logging
import math
import re
from collections import Counter
from typing import Any

import numpy as np
import openai

from config import settings

logger = logging.getLogger(__name__)

_client: openai.OpenAI | None = None

def _get_client() -> openai.OpenAI:
    global _client

    if _client is None:
        if not settings.DEEPSEEK_API_KEY:
            raise RuntimeError(
                "DEEPSEEK_API_KEY is not set. Please set it in your environment."
            )
        _client = openai.OpenAI(
            api_key=settings.DEEPSEEK_API_KEY,
            base_url = "https://api.deepseek.com",
        )
    return _client

def _call(
    system: str,
    user: str,
    *,
    max_tokens: int | None = None,
    thinking: bool = False,
) -> str:
    """Single non-streaming completion call. Returns the concatenated text blocks.

    `thinking` turns on DeepSeek's reasoning. It helps planning and code
    generation; for prose (summaries, dictionaries, answers) it only adds
    latency and can use up the whole token budget, so it is off by default.
    """
    client = _get_client()
    if _PLACEHOLDER.search(user):
        system += _PLACEHOLDER_NOTE
    response = client.chat.completions.create(
        model=settings.LLM_MODEL,
        # DeepSeek's current models reason before answering, and the reasoning
        # counts against max_tokens. A small cap (e.g. 2048) can be used up by
        # thinking alone, returning an empty script or a cut-off summary, so
        # never go below the configured floor.
        # With thinking on, reasoning alone can exceed 8k tokens on a real
        # dataset prompt (seen in testing), so those calls get double.
        max_tokens=max(max_tokens or 0, settings.LLM_MAX_TOKENS * (2 if thinking else 1)),
        messages=[
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        extra_body=None if thinking else {"thinking": {"type": "disabled"}},
    )

    choice = response.choices[0]
    if choice.finish_reason == "length":
        logger.warning("LLM reply hit the token limit (%s tokens used); output may be truncated.",
                       getattr(response.usage, "completion_tokens", "?"))
    # content can be None (e.g. a filtered response); callers .strip() it.
    return choice.message.content or ""


# privacy.py replaces names with [P1]-style placeholders before any LLM call.
_PLACEHOLDER = re.compile(r"\[P\d+\]")
_PLACEHOLDER_NOTE = (
    "\n\nSome names in the input were replaced with placeholders like [P1] for privacy. "
    "Treat each placeholder as the real name of that person or business and write it exactly as "
    "given (it is swapped back before the user reads your answer). Do not call them codes or "
    "anonymised, and never guess the hidden names."
)

def _call_json(system: str, user: str, *, max_tokens: int | None = None) -> Any:
    """
    Calls the model with an instruction to return raw JSON only, then parses it.
    Strips markdown code fences defensively in case the model wraps its output.
    """
    json_system = (
        f"{system}\n\n"
        "Respond with ONLY valid JSON. No prose, no markdown code fences, "
        "no explanation before or after the JSON."
    )
    raw = _call(json_system, user, max_tokens=max_tokens)
    cleaned = raw.strip().removeprefix("```json").removeprefix("```").removesuffix("```").strip()
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        logger.warning("LLM returned non-JSON payload, returning empty structure. Raw: %s", raw[:500])
        return None


# --------------------------------------------------------------------------
# Step 1: Data dictionary generation
# --------------------------------------------------------------------------

def generate_data_dictionary(metadata: dict[str, Any]) -> list[dict[str, str]]:
    system = (
        "You are a senior data analyst producing a data dictionary for a business "
        "audience. For each column, infer its likely business meaning from its name, "
        "dtype, and sample values."
    )
    user = (
        "Dataset metadata (JSON):\n"
        f"{json.dumps(metadata, default=str, indent=2)}\n\n"
        "Return a JSON array where each element has exactly these keys: "
        '"column", "business_meaning", "data_type", "notes".'
    )
    result = _call_json(system, user)
    if not isinstance(result, list):
        # Deterministic fallback so the pipeline never hard-fails on an LLM hiccup.
        return [
            {
                "column": col["name"],
                "business_meaning": "Unable to infer automatically.",
                "data_type": col["dtype"],
                "notes": "LLM data-dictionary generation failed; populate manually.",
            }
            for col in metadata.get("columns", [])
        ]
    return result


# --------------------------------------------------------------------------
# Step 2: Choosing the exploratory charts
# --------------------------------------------------------------------------

def select_eda_charts(
    column_profile: dict[str, list[dict[str, Any]]],
    data_dictionary: list[dict[str, Any]],
    chart_menu: dict[str, dict[str, Any]],
    max_charts: int = 4,
) -> list[dict[str, Any]] | None:
    """Returns the model's chart picks, or None if it didn't return a JSON array.
    The caller validates every pick against the menu and the column roles."""
    system = (
        "You are a senior data analyst choosing the first charts a business stakeholder "
        "sees for a newly uploaded dataset. Pick the charts most likely to reveal something "
        "actionable: lead with the key business metric (revenue, sales, spend, volume, users...) "
        "- how it splits across the most meaningful segments, how it moves over time, and how "
        "it is distributed. Prefer aggregated views (bar_agg, time_series) over raw ones. "
        "Never chart near-constant columns or pair columns with no business logic, and do not "
        "repeat the same view of the same columns."
    )
    user = (
        f"Columns by role (only these columns may be used):\n{json.dumps(column_profile, default=str, indent=2)}\n\n"
        f"Data dictionary (business meaning of each column):\n{json.dumps(data_dictionary, default=str)[:6000]}\n\n"
        f"Chart menu (type -> required column role per axis):\n{json.dumps(chart_menu, indent=2)}\n\n"
        f"Return a JSON array of {max_charts - 1}-{max_charts} charts, most important first. Each element "
        'has keys: "type" (from the menu), "x", "y" (column names fitting the roles; omit "y" when '
        'the type has none), "agg" ("sum" or "mean", only for types that take it; sum for totals like '
        'revenue or units, mean for rates, ratings, prices or ages), "color" (optional, time_series only), '
        '"title" (short, business-friendly), and "why" (one sentence on the business question it answers).'
    )
    result = _call_json(system, user, max_tokens=2048)
    return result if isinstance(result, list) else None


# --------------------------------------------------------------------------
# Step 3: Executive summary
# --------------------------------------------------------------------------

def generate_executive_summary(
    metadata: dict[str, Any],
    cleaning_log: list[dict[str, Any]],
    chart_descriptions: list[str],
    data_insights: list[str] | None = None,
) -> str:
    insights_text = "\n".join(data_insights) if data_insights else "(No specific data insights provided)"
    
    system = (
        "You are a senior data analyst writing a plain-text executive summary for "
        "a non-technical business stakeholder. Be concise, avoid jargon, and focus "
        "on explaining what the data actually reveals about the business."
    )
    
    user = (
        f"Dataset metadata:\n{json.dumps(metadata, default=str, indent=2)}\n\n"
        f"Cleaning log:\n{json.dumps(cleaning_log, indent=2)}\n\n"
        f"Charts generated:\n{json.dumps(chart_descriptions, indent=2)}\n\n"
        f"Key Data Insights (Extracted from charts):\n{insights_text}\n\n"
        "Write a 3-5 paragraph executive summary covering:\n"
        "1. What the dataset represents.\n"
        "2. The data quality issues found and how they were automatically remediated.\n"
        "3. A simple, business-friendly explanation of the visualizations based on the Key Data Insights. "
        "Do not just list the charts; explain what the numbers, distributions, and trends actually mean for the business."
    )
    
    return _call(system, user)


# --------------------------------------------------------------------------
# Step 4: Q&A loop - planning, coding, prescriptive summarization
# --------------------------------------------------------------------------

def _format_excerpts(chunks: list[dict[str, Any]]) -> str:
    parts = []
    for i, c in enumerate(chunks):
        page = f", Page {c['page_number']}" if c.get("page_number") else ""
        parts.append(f"--- Excerpt {i+1} (Source: {c['filename']}{page}) ---\n{c['content']}")
    return "\n\n".join(parts)


def generate_plan(
    question: str,
    data_dictionary: list[dict[str, Any]],
    business_rules: list[str],
    chat_history: list[dict[str, str]],
    executive_summary: str = "",
    document_excerpts: list[dict[str, Any]] | None = None,
) -> str:
    """`data_dictionary` is one entry per dataset: {"filename", "columns": [...]}."""
    system = (
        "You are the planning module of an autonomous data-analysis agent. Produce "
        "a short, numbered, step-by-step plan describing what pandas/plotly "
        "operations are needed to answer the user's question. Several datasets may "
        "be available; name the exact file(s) each step reads, and how they are "
        "joined if more than one is needed. Do not write code."
    )
    history_txt = "\n".join(f"{m['role']}: {m['content']}" for m in chat_history[-10:])
    docs_txt = ""
    if document_excerpts:
        docs_txt = (
            "Relevant document excerpts (use these for targets, thresholds, definitions "
            f"or policies the numbers must be compared against):\n{_format_excerpts(document_excerpts)}\n\n"
        )
    user = (
        f"Datasets and their data dictionaries:\n{json.dumps(data_dictionary, default=str, indent=2)}\n\n"
        f"Dashboard Executive Summary (For context on overall trends/forecasts):\n{executive_summary or '(None generated)'}\n\n"
        f"{docs_txt}"
        f"Persistent business rules this analysis MUST respect:\n"
        f"{json.dumps(business_rules, indent=2) if business_rules else '(none defined)'}\n\n"
        f"Recent conversation:\n{history_txt or '(no prior turns)'}\n\n"
        f"User question: {question}\n\n"
        "Produce the step-by-step plan."
    )
    return _call(system, user, thinking=True)


def generate_code(
    plan: str,
    data_dictionary: list[dict[str, Any]],
    filenames: list[str],
    prior_code: str | None = None,
    prior_error: str | None = None,
) -> str:
    system = (
        "You are the coding module of an autonomous data-analysis agent. Translate "
        "the given plan into a single, self-contained Python script using pandas "
        "(and plotly.express / plotly.graph_objects if a chart is required). "
        "A pre-defined dict named `files` maps each dataset's filename to a CSV path; "
        "load datasets ONLY via `pd.read_csv(files[\"<filename>\"])` using the exact "
        "filenames given. Never hard-code paths and never redefine `files`. Datetime "
        "columns are stored as text, so parse them with `pd.to_datetime` before use. "
        "If producing a chart, assign the Plotly figure to a variable named `fig` "
        "(it is captured automatically; never call `fig.to_json()`). Always assign "
        "the key numbers behind the answer to a variable named `result` (a string, "
        "number, or small JSON-serializable dict, e.g. the aggregated values the "
        "chart plots). Return ONLY the raw Python code, no markdown fences, no "
        "commentary."
    )
    correction_note = ""
    if prior_code and prior_error:
        correction_note = (
            f"\n\nThe previous attempt raised an error. Fix it.\n"
            f"--- previous code ---\n{prior_code}\n"
            f"--- error ---\n{prior_error}\n"
        )
    user = (
        f"Available keys in `files`: {json.dumps(filenames)}\n\n"
        f"Datasets and their data dictionaries:\n{json.dumps(data_dictionary, default=str, indent=2)}\n\n"
        f"Plan:\n{plan}"
        f"{correction_note}"
    )
    code = _call(system, user, max_tokens=2048, thinking=True)
    return code.strip().removeprefix("```python").removeprefix("```").removesuffix("```").strip()


def generate_prescriptive_summary(
    question: str,
    execution_output: dict[str, Any],
    business_rules: list[str],
    document_excerpts: list[dict[str, Any]] | None = None,
) -> str:
    system = (
        "You are a senior analytics consultant. Given the raw result of an "
        "executed analysis, write a short, prescriptive, data-backed recommendation "
        "for what business action to take. Cite the specific numbers produced. "
        "Respect any business rules given. If document excerpts are provided, compare "
        "the numbers against them and cite the document filename and page inline."
    )
    # The serialized chart can be huge and is useless to the summarizer.
    output_for_llm = {k: v for k, v in execution_output.items() if k != "plotly_json"}
    output_for_llm["chart_produced"] = bool(execution_output.get("plotly_json"))
    docs_txt = f"Document excerpts:\n{_format_excerpts(document_excerpts)}\n\n" if document_excerpts else ""
    user = (
        f"User question: {question}\n\n"
        f"Execution output:\n{json.dumps(output_for_llm, default=str, indent=2)[:12000]}\n\n"
        f"{docs_txt}"
        f"Business rules to respect:\n"
        f"{json.dumps(business_rules, indent=2) if business_rules else '(none defined)'}\n\n"
        "Write the prescriptive summary (2-4 sentences)."
    )
    return _call(system, user)

### --------------------------------------------------------------------------
### Step 5: Predictive Modeling Summary
### --------------------------------------------------------------------------
def generate_predictive_summary(
    target_column: str, 
    problem_type: str, 
    metrics: dict[str, str], 
    top_drivers: dict[str, float]
) -> str:
    system = (
        "You are a senior data analytics consultant. Given the mathematical outputs of an "
        "automated machine learning model, write a prescriptive, plain-English summary "
        "for a non-technical business executive."
    )
    user = (
        f"Target Outcome: {target_column}\n"
        f"Model Type: {problem_type}\n"
        f"Accuracy Metrics: {json.dumps(metrics, indent=2)}\n"
        f"Top Driving Factors (Feature Importance): {json.dumps(top_drivers, indent=2)}\n\n"
        "Write a 2-paragraph prescriptive summary covering:\n"
        "1. How accurately we can predict this outcome based on the metrics.\n"
        "2. What the specific driving factors are, and what concrete business actions "
        "leadership should take to influence them. Avoid technical ML jargon like 'R-squared' or 'F1-score'."
    )
    return _call(system, user)

### --------------------------------------------------------------------------
### Document RAG & Intent Routing
### --------------------------------------------------------------------------
INTENTS = ("quant", "doc", "hybrid")

def generate_document_digest(filename: str, preview_text: str) -> dict[str, Any]:
    """A short summary plus starter questions that kick off the RAG loop in the UI."""
    system = (
        "You are a senior analyst skimming a document a colleague just shared. "
        "Return a JSON object with exactly two keys: "
        "'summary' (2-3 plain-English sentences on what the document is and what it covers) and "
        "'starter_questions' (a list of 4 short, specific questions a business user would ask about "
        "THIS document, each answerable from its contents, e.g. 'What are the termination clauses?')."
    )
    user = f"Document: {filename}\n\nRepresentative excerpts:\n{preview_text}"
    result = _call_json(system, user, max_tokens=600)
    if not isinstance(result, dict):
        return {}
    questions = result.get("starter_questions")
    return {
        "summary": str(result.get("summary") or "").strip(),
        "starter_questions": [str(q).strip() for q in questions if str(q).strip()][:4]
        if isinstance(questions, list) else [],
    }

def classify_intent(question: str, tabular_files: list[str], document_files: list[str]) -> str:
    system = (
        "You are an intent router for an autonomous data analysis agent. "
        "Classify the user's question into exactly one category: 'quant', 'doc' or 'hybrid'.\n\n"
        "- 'quant': answerable from the structured tabular datasets alone (math, aggregation, "
        "charts, counts, averages, trends, forecasting).\n"
        "- 'doc': answerable from the unstructured documents alone (policies, contracts, "
        "reports, feedback, definitions, qualitative information).\n"
        "- 'hybrid': needs numbers computed from the datasets AND context from the documents "
        "(e.g., comparing actual revenue to a target stated in a strategy PDF).\n\n"
        "Return ONLY the category name. No punctuation or explanation."
    )
    user = (
        f"Tabular datasets: {json.dumps(tabular_files)}\n"
        f"Documents: {json.dumps(document_files)}\n\n"
        f"Question: {question}"
    )
    raw = (_call(system, user) or "").lower()
    match = re.search(r"\b(hybrid|quant|doc)\b", raw)
    # When unsure, hybrid is the safe default: it grounds in documents and still runs the numbers.
    return match.group(1) if match else "hybrid"

def generate_rag_synthesis(
    question: str,
    chunks: list[dict[str, Any]],
    chat_history: list[dict[str, str]] | None = None,
) -> str:
    system = (
        "You are an intelligent document assistant. Answer the user's question based STRICTLY on the provided document excerpts. "
        "If the answer cannot be found in the excerpts, state explicitly that you do not have sufficient information. "
        "Whenever you use information from an excerpt, cite the document filename and page number inline "
        "(e.g., [policy.pdf, p. 3]; omit the page when none is given)."
    )
    if not chunks:
        return "I couldn't find any indexed document content in this workspace to answer that question."
    history_txt = "\n".join(f"{m['role']}: {m['content']}" for m in (chat_history or [])[-6:])
    user = (
        f"Recent conversation:\n{history_txt or '(no prior turns)'}\n\n"
        f"Question: {question}\n\n"
        f"Document excerpts:\n{_format_excerpts(chunks)}"
    )
    return _call(system, user)

### --------------------------------------------------------------------------
### Chart Q&A
### --------------------------------------------------------------------------
_CHART_POINT_LIMIT = 60      # plot every point up to this many, else sample + stats
_CHART_DIGEST_CHARS = 14000  # hard cap on the figure digest sent to the model


def _decode_array(value: Any) -> Any:
    """Plotly 6+ serializes numpy arrays as {"dtype", "bdata" (base64), "shape"}."""
    if isinstance(value, dict) and "bdata" in value and "dtype" in value:
        arr = np.frombuffer(base64.b64decode(value["bdata"]), dtype=np.dtype(value["dtype"]))
        shape = value.get("shape")
        if shape:
            dims = shape if isinstance(shape, list) else [int(s) for s in str(shape).split(",")]
            arr = arr.reshape(dims)
        return arr.tolist()
    return value


def _round(v: Any) -> Any:
    return round(v, 4) if isinstance(v, float) else v


def _is_number(v: Any) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def _numeric(values: list[Any]) -> np.ndarray | None:
    """The values as floats when (almost) all of them are numeric, else None."""
    nums = [v for v in values if _is_number(v)]
    return np.array(nums, dtype=float) if nums and len(nums) >= 0.9 * len(values) else None


def _value_stats(values: list[Any]) -> dict[str, Any]:
    nums = _numeric(values)
    if nums is None:
        return {"n": len(values), "most_common": Counter(map(str, values)).most_common(10)}
    return {
        "n": len(values),
        **{k: _round(float(f(nums))) for k, f in (("min", np.min), ("max", np.max), ("mean", np.mean), ("median", np.median), ("std", np.std))},
        "p25": _round(float(np.percentile(nums, 25))),
        "p75": _round(float(np.percentile(nums, 75))),
    }


def _describe_trace(trace: dict[str, Any]) -> dict[str, Any]:
    kind = trace.get("type", "scatter")
    out: dict[str, Any] = {"type": kind}
    for key in ("name", "mode", "orientation"):
        if trace.get(key):
            out[key] = trace[key]
    x, y = _decode_array(trace.get("x")), _decode_array(trace.get("y"))

    if kind == "histogram":
        # A histogram trace carries the raw observations; the browser does the binning.
        raw = x if x is not None else y
        nums = _numeric(raw or [])
        out["observations"] = _value_stats(raw or [])
        if nums is not None and len(nums):
            counts, edges = np.histogram(nums, bins=min(15, max(1, len(set(nums.tolist())))))
            out["bins"] = [[_round(float(edges[i])), _round(float(edges[i + 1])), int(c)] for i, c in enumerate(counts)]
        return out

    if kind == "box" and y is not None:
        groups: dict[str, list[Any]] = {}
        for g, v in zip(x if x is not None else ["all"] * len(y), y):
            groups.setdefault(str(g), []).append(v)
        out["groups"] = {g: _value_stats(vs) for g, vs in list(groups.items())[:25]}
        return out

    if kind == "heatmap":
        out.update({k: _decode_array(trace.get(k)) for k in ("x", "y", "z") if trace.get(k) is not None})
        return out

    if kind == "pie":
        out["slices"] = list(zip(_decode_array(trace.get("labels")) or [], _decode_array(trace.get("values")) or []))
        return out

    if x is not None and y is not None:
        points = list(zip(x, y))
        if len(points) <= _CHART_POINT_LIMIT:
            out["points"] = [[_round(a), _round(b)] for a, b in points]
        else:
            idx = np.linspace(0, len(points) - 1, 40).astype(int)
            out["sampled_points"] = [[_round(points[i][0]), _round(points[i][1])] for i in idx]
            out["x_stats"], out["y_stats"] = _value_stats(x), _value_stats(y)
            xs, ys = _numeric(x), _numeric(y)
            if xs is not None and ys is not None and len(xs) == len(ys) > 2:
                out["pearson_r"] = _round(float(np.corrcoef(xs, ys)[0, 1]))
        return out

    for key in ("x", "y", "z", "values", "labels"):
        values = _decode_array(trace.get(key))
        if isinstance(values, list):
            out[key] = values if len(values) <= _CHART_POINT_LIMIT else _value_stats(values)
    return out


def _axis_title(axis: Any) -> str:
    title = (axis or {}).get("title") if isinstance(axis, dict) else None
    return (title.get("text") if isinstance(title, dict) else title) or ""


def describe_figure(figure: dict[str, Any], fallback_title: str = "") -> dict[str, Any]:
    """Turns a serialized Plotly figure into a compact, model-readable digest of what it plots."""
    layout = figure.get("layout") or {}
    title = layout.get("title")
    return {
        "title": re.sub(r"<[^>]+>", " ", (title.get("text") if isinstance(title, dict) else title) or fallback_title).strip(),
        "x_axis": _axis_title(layout.get("xaxis")),
        "y_axis": _axis_title(layout.get("yaxis")),
        "traces": [_describe_trace(t) for t in (figure.get("data") or [])[:12] if isinstance(t, dict)],
    }


def generate_chart_answer(
    question: str,
    figure_digest: dict[str, Any],
    data_dictionary: list[dict[str, Any]],
    business_rules: list[str],
    chat_history: list[dict[str, str]],
) -> str:
    system = (
        "You are a senior data analyst sitting next to a business user who has one chart "
        "expanded on screen and is asking about it. Answer from the chart's plotted values "
        "given below: cite the specific numbers, categories or dates you rely on, and point "
        "out patterns, outliers and caveats (e.g. sampled points, imputed data). Keep it "
        "short and plain-English; use a few bullets when listing findings. If the question "
        "needs data the chart does not show, say so and suggest the question to ask in the "
        "main MyAnalyst chat, which can run new analyses. Respect any business rules given."
    )
    history_txt = "\n".join(f"{m['role']}: {m['content']}" for m in chat_history[-8:])
    user = (
        f"Chart (digest of the plotted data):\n{json.dumps(figure_digest, default=str)[:_CHART_DIGEST_CHARS]}\n\n"
        f"Data dictionary of the underlying dataset(s):\n{json.dumps(data_dictionary, default=str)[:4000]}\n\n"
        f"Business rules to respect:\n{json.dumps(business_rules, indent=2) if business_rules else '(none defined)'}\n\n"
        f"Earlier questions about this chart:\n{history_txt or '(none)'}\n\n"
        f"Question: {question}"
    )
    return _call(system, user, max_tokens=900)
