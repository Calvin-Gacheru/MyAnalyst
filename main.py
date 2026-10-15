# type: ignore
"""
FastAPI entrypoint for MyAnalyst.

Route responsibilities are intentionally thin: parse/validate the HTTP
layer, delegate to preprocessing.py / graph.py / memory.py, and shape the
result into the Pydantic response models. No business logic lives here.
"""
from __future__ import annotations

import io
import json
import logging
import uuid
from pathlib import Path

import pandas as pd
from fastapi import FastAPI, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

import graph
import memory
from config import settings
from preprocessing import apply_ingestion_heuristics, extract_metadata, remediate_data
from schemas import (
    BusinessRule,
    BusinessRuleCreate,
    ChatMessage,
    DataDictionaryEntry,
    QARequest,
    QAResponse,
    UploadResponse,
)
import llm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("myanalyst")

app = FastAPI(
    title="MyAnalyst",
    description="Autonomous data analysis platform: deterministic pandas preprocessing "
    "feeding a LangGraph agent for EDA, forecasting, and a self-correcting Q&A loop.",
    version="0.1.0",
)

# The frontend is served from the same origin (see the mount at the bottom
# of this file), so this CORS config only matters if you ever open
# frontend/index.html directly as a file or serve it from elsewhere.
# Tighten allow_origins to that origin before shipping this beyond your
# own machine.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def on_startup() -> None:
    settings.ensure_dirs()
    memory.init_db()
    if not settings.DEEPSEEK_API_KEY:
        logger.warning(
            "DEEPSEEK_API_KEY is not set; LLM-backed nodes will fail at call time."
        )


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


# --------------------------------------------------------------------------
# Workflow steps 1 + 2 + 3: upload -> deterministic clean -> EDA/forecast
# --------------------------------------------------------------------------

@app.post("/datasets/upload", response_model=UploadResponse)
async def upload_dataset(file: UploadFile) -> UploadResponse:
    if not file.filename or not file.filename.lower().endswith(".csv"):
        raise HTTPException(status_code=400, detail="Only .csv uploads are supported.")

    raw_bytes = await file.read()
    try:
        raw_df = pd.read_csv(io.BytesIO(raw_bytes))
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Could not parse CSV: {exc}") from exc

    if raw_df.empty:
        raise HTTPException(status_code=400, detail="Uploaded CSV contains no rows.")

    # --- Step 1: deterministic ingestion heuristics ---
    clean_df, ingestion_log, flagged_ids = apply_ingestion_heuristics(raw_df)
    metadata = extract_metadata(clean_df, flagged_ids)

    # --- Step 2: automated remediation ---
    remediated_df, remediation_log = remediate_data(clean_df, flagged_ids)
    full_cleaning_log = ingestion_log + remediation_log

    # --- Data dictionary (LLM, but grounded in the deterministic metadata) ---
    data_dictionary = llm.generate_data_dictionary(metadata)

    # --- Step 3: proactive EDA + forecasting (LangGraph) ---
    eda_result = graph.run_eda_workflow(
        df=remediated_df,
        metadata=metadata,
        cleaning_log=full_cleaning_log,
        flagged_ids=flagged_ids,
    )

    exec_summary = eda_result.get("executive_summary", "")

    # --- Persist the cleaned CSV + dataset record ---
    dataset_id = str(uuid.uuid4())
    settings.ensure_dirs()
    file_path = settings.UPLOAD_DIR / f"{dataset_id}.csv"
    remediated_df.to_csv(file_path, index=False)

    memory.save_dataset(
        file_path=str(file_path),
        data_dictionary=data_dictionary,
        cleaning_log=full_cleaning_log,
        dataset_id=dataset_id,
    )

    return UploadResponse(
        dataset_id=dataset_id,
        row_count=metadata["n_rows"],
        column_count=metadata["n_columns"],
        data_dictionary=[DataDictionaryEntry(**entry) for entry in data_dictionary],
        cleaning_log=full_cleaning_log,
        charts=eda_result.get("charts", []),
        executive_summary=exec_summary,
    )


# --------------------------------------------------------------------------
# Business rules (persisted, and consumed by the Q&A Planner node)
# --------------------------------------------------------------------------

@app.post("/datasets/{dataset_id}/business-rules", response_model=BusinessRule)
def create_business_rule(dataset_id: str, payload: BusinessRuleCreate) -> BusinessRule:
    if memory.get_dataset(dataset_id) is None:
        raise HTTPException(status_code=404, detail="Unknown dataset_id.")
    rule_id = memory.add_business_rule(dataset_id, payload.rule_text)
    rows = memory.get_business_rules(dataset_id)
    saved = next(r for r in rows if r["id"] == rule_id)
    return BusinessRule(**saved)


@app.get("/datasets/{dataset_id}/business-rules", response_model=list[BusinessRule])
def list_business_rules(dataset_id: str) -> list[BusinessRule]:
    if memory.get_dataset(dataset_id) is None:
        raise HTTPException(status_code=404, detail="Unknown dataset_id.")
    return [BusinessRule(**row) for row in memory.get_business_rules(dataset_id)]


# --------------------------------------------------------------------------
# Workflow step 4: the Q&A loop
# --------------------------------------------------------------------------

@app.post("/datasets/{dataset_id}/qa", response_model=QAResponse)
def ask_question(dataset_id: str, payload: QARequest) -> QAResponse:
    if memory.get_dataset(dataset_id) is None:
        raise HTTPException(status_code=404, detail="Unknown dataset_id.")

    session_id = payload.session_id or str(uuid.uuid4())

    try:
        final_state = graph.run_qa_workflow(
            dataset_id=dataset_id,
            session_id=session_id,
            question=payload.question,
        )
    except Exception as exc:
        logger.exception("Q&A workflow crashed for dataset_id=%s", dataset_id)
        raise HTTPException(status_code=500, detail=f"Q&A workflow failed: {exc}") from exc

    return QAResponse(
        session_id=session_id,
        answer=final_state.get("final_answer", ""),
        generated_code=final_state.get("current_code", ""),
        execution_output=final_state.get("execution_output", {}),
        attempts=final_state.get("attempts", 0),
        errors=final_state.get("errors", []),
    )


@app.get("/datasets/{dataset_id}/chat-history", response_model=list[ChatMessage])
def get_chat_history(dataset_id: str, session_id: str) -> list[ChatMessage]:
    if memory.get_dataset(dataset_id) is None:
        raise HTTPException(status_code=404, detail="Unknown dataset_id.")
    rows = memory.get_chat_history(session_id)
    return [ChatMessage(role=r["role"], content=r["content"], created_at=r["created_at"]) for r in rows]


@app.exception_handler(ValueError)
def value_error_handler(request, exc: ValueError) -> JSONResponse:  # noqa: ANN001 - FastAPI signature
    return JSONResponse(status_code=400, content={"detail": str(exc)})


# --------------------------------------------------------------------------
# Frontend
# --------------------------------------------------------------------------
# Mounted last and at "/" so it only catches requests that didn't match any
# API route above (route order is registration order, so this never shadows
# /health, /datasets/..., etc.). `html=True` makes StaticFiles serve
# frontend/index.html for "/" and for any unmatched sub-path, so a single
# `uvicorn main:app` both runs the API and serves the UI at
# http://localhost:8000/.
_FRONTEND_DIR = Path(__file__).resolve().parent / "frontend"
if _FRONTEND_DIR.is_dir():
    app.mount("/", StaticFiles(directory=str(_FRONTEND_DIR), html=True), name="frontend")
else:
    logger.warning("frontend/ directory not found next to main.py; UI will not be served.")
