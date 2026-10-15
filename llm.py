# type: ignore
"""
All LLM calls funnel through this module.

Keeping prompt construction and response parsing in one place makes the
rest of the codebase (preprocessing.py, graph.py) read as plain business
logic, and makes it trivial to swap models or add retries/observability
in a single spot later.
"""
from __future__ import annotations

import json
import logging
from typing import Any

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
) -> str:
    """Single non-streaming completion call. Returns the concatenated text blocks."""
    client = _get_client()
    response = client.chat.completions.create(
        model=settings.LLM_MODEL,
        max_tokens=max_tokens or settings.LLM_MAX_TOKENS,
        messages=[
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ]
    )

    return response.choices[0].message.content

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

def generate_plan(
    question: str,
    data_dictionary: list[dict[str, Any]],
    business_rules: list[str],
    chat_history: list[dict[str, str]],
    executive_summary: str = "",
) -> str:
    system = (
        "You are the planning module of an autonomous data-analysis agent. Produce "
        "a short, numbered, step-by-step plan describing what pandas/plotly "
        "operations are needed to answer the user's question. Do not write code."
    )
    history_txt = "\n".join(f"{m['role']}: {m['content']}" for m in chat_history[-10:])
    user = (
        f"Data dictionary:\n{json.dumps(data_dictionary, indent=2)}\n\n"
        f"Dashboard Executive Summary (For context on overall trends/forecasts):\n{executive_summary or '(None generated)'}\n\n"]
        f"Persistent business rules this analysis MUST respect:\n"
        f"{json.dumps(business_rules, indent=2) if business_rules else '(none defined)'}\n\n"
        f"Recent conversation:\n{history_txt or '(no prior turns)'}\n\n"
        f"User question: {question}\n\n"
        f"Executive summary: {executive_summary}\n\n"
        "Produce the step-by-step plan."
    )
    return _call(system, user)


def generate_code(
    plan: str,
    data_dictionary: list[dict[str, Any]],
    file_path: str,
    prior_code: str | None = None,
    prior_error: str | None = None,
) -> str:
    system = (
        "You are the coding module of an autonomous data-analysis agent. Translate "
        "the given plan into a single, self-contained Python script using pandas "
        "(and plotly.express / plotly.graph_objects if a chart is required). "
        "The dataframe must be loaded with `df = pd.read_csv(file_path)`. "
        "If producing a chart, assign the Plotly figure to a variable named `fig` "
        "and end the script with `result = fig.to_json()`. Otherwise assign the "
        "final answer to a variable named `result` (a string, number, or "
        "JSON-serializable dict). Return ONLY the raw Python code, no markdown "
        "fences, no commentary."
    )
    correction_note = ""
    if prior_code and prior_error:
        correction_note = (
            f"\n\nThe previous attempt raised an error. Fix it.\n"
            f"--- previous code ---\n{prior_code}\n"
            f"--- error ---\n{prior_error}\n"
        )
    user = (
        f"file_path variable will be set to: {file_path!r}\n\n"
        f"Data dictionary:\n{json.dumps(data_dictionary, indent=2)}\n\n"
        f"Plan:\n{plan}"
        f"{correction_note}"
    )
    code = _call(system, user, max_tokens=2048)
    return code.strip().removeprefix("```python").removeprefix("```").removesuffix("```").strip()


def generate_prescriptive_summary(
    question: str,
    execution_output: dict[str, Any],
    business_rules: list[str],
) -> str:
    system = (
        "You are a senior analytics consultant. Given the raw result of an "
        "executed analysis, write a short, prescriptive, data-backed recommendation "
        "for what business action to take. Cite the specific numbers produced. "
        "Respect any business rules given."
    )
    user = (
        f"User question: {question}\n\n"
        f"Execution output:\n{json.dumps(execution_output, default=str, indent=2)}\n\n"
        f"Business rules to respect:\n"
        f"{json.dumps(business_rules, indent=2) if business_rules else '(none defined)'}\n\n"
        "Write the prescriptive summary (2-4 sentences)."
    )
    return _call(system, user)
