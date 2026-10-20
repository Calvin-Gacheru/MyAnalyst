# type: ignore
"""
FastAPI entrypoint for MyAnalyst.
Route responsibilities are intentionally thin: parse/validate the HTTP layer, delegate
to preprocessing.py / rag.py / graph.py, and shape the result into Pydantic models.
"""
from __future__ import annotations
import io
import json
import logging
import re
import uuid
from pathlib import Path
from typing import Any

import pandas as pd
from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

import graph
import memory
import schemas
import llm
import rag
import modeling
from config import settings
from preprocessing import apply_ingestion_heuristics, extract_metadata, remediate_data
from sandbox import container_path_for

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("myanalyst")

app = FastAPI(
    title="MyAnalyst",
    description="Autonomous multi-modal data analyst. Handles tabular CSVs via Pandas/Plotly and unstructured documents via pgvector RAG.",
    version="0.2.0",
)

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
        logger.warning("DEEPSEEK_API_KEY is not set; LLM-backed nodes will fail at call time.")

@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}

### --------------------------------------------------------------------------
### Workspace helpers
### --------------------------------------------------------------------------
TABULAR_EXTENSIONS = (".csv", ".xlsx")
SUPPORTED_EXTENSIONS = TABULAR_EXTENSIONS + rag.DOCUMENT_EXTENSIONS


def _safe_filename(name: str) -> str:
    """Strips any client-supplied directories (path traversal) and characters
    that would break a Docker bind-mount spec (e.g. ':')."""
    return re.sub(r"[^\w.\- ]", "_", Path(name).name).strip() or "upload"


def _get_workspace_or_404(db, workspace_id: str) -> memory.Workspace:
    ws = db.query(memory.Workspace).filter_by(workspace_id=workspace_id).first()
    if not ws:
        raise HTTPException(status_code=404, detail=f"Workspace '{workspace_id}' not found.")
    return ws


def _workspace_files(db, workspace_id: str) -> list[memory.WorkspaceFile]:
    return (
        db.query(memory.WorkspaceFile)
        .filter_by(workspace_id=workspace_id)
        .order_by(memory.WorkspaceFile.created_at)
        .all()
    )


def _combined_executive_summary(files: list[memory.WorkspaceFile]) -> str:
    summaries = []
    for wf in files:
        summary = json.loads(wf.parsed_metadata).get("executive_summary")
        if summary:
            summaries.append((wf.filename, summary))
    if len(summaries) == 1:
        return summaries[0][1]
    return "\n\n".join(f"{name}\n{summary}" for name, summary in summaries)


def _workspace_response(db, workspace_id: str, errors: list[str] | None = None) -> schemas.WorkspaceResponse:
    """Builds the full workspace state from PostgreSQL, so the UI always renders
    every file in the workspace rather than just the latest upload batch."""
    ws = _get_workspace_or_404(db, workspace_id)
    files, digests, dictionary, cleaning_log, charts = [], [], [], [], []
    for wf in _workspace_files(db, workspace_id):
        meta = json.loads(wf.parsed_metadata)
        files.append(schemas.FileIngestionMetadata(filename=wf.filename, file_type=wf.file_type, details=meta.get("details", {})))
        if wf.file_type == "document":
            digests.append(schemas.DocumentDigest(filename=wf.filename, **meta.get("digest", {})))
        dictionary += [schemas.DataDictionaryEntry(**e, source_file=wf.filename) for e in meta.get("data_dictionary", [])]
        cleaning_log += [schemas.CleaningLogEntry(**e, source_file=wf.filename) for e in meta.get("cleaning_log", [])]
        charts += [{**c, "source_file": wf.filename} for c in meta.get("charts", [])]
    return schemas.WorkspaceResponse(
        workspace_id=workspace_id,
        files=files,
        document_digests=digests,
        data_dictionary=dictionary,
        cleaning_log=cleaning_log,
        charts=charts,
        executive_summary=ws.executive_summary or "",
        errors=errors or [],
    )


def _normalize_dictionary(entries: Any, metadata: dict[str, Any]) -> list[dict[str, str]]:
    """Coerces the LLM's data dictionary into the DataDictionaryEntry shape."""
    if not isinstance(entries, list):
        entries = []
    normalized = []
    for e in entries:
        if isinstance(e, dict) and e.get("column"):
            normalized.append({
                "column": str(e["column"]),
                "business_meaning": str(e.get("business_meaning", "")),
                "data_type": str(e.get("data_type", "")),
                "notes": str(e.get("notes", "")),
            })
    if not normalized:
        normalized = [
            {"column": c["name"], "business_meaning": "", "data_type": c["dtype"], "notes": ""}
            for c in metadata.get("columns", [])
        ]
    return normalized


def _document_digest(filename: str, preview: str) -> dict[str, Any]:
    """The digest is a nice-to-have: an LLM failure here must not fail an otherwise indexed document."""
    try:
        return llm.generate_document_digest(filename, preview)
    except Exception:
        logger.exception("Document digest failed for %s", filename)
        return {}


def _ingest_tabular(raw_bytes: bytes, filename: str, workspace_dir: Path) -> tuple[str, dict[str, Any]]:
    """Clean -> profile -> EDA graph. Returns (clean CSV path, parsed_metadata)."""
    if filename.lower().endswith(".xlsx"):
        raw_df = pd.read_excel(io.BytesIO(raw_bytes))
    else:
        raw_df = pd.read_csv(io.BytesIO(raw_bytes))
    if raw_df.empty:
        raise ValueError("the file contains no rows")

    clean_df, i_log, flagged_ids = apply_ingestion_heuristics(raw_df)
    metadata = extract_metadata(clean_df, flagged_ids)
    remediated_df, r_log = remediate_data(clean_df, flagged_ids)
    full_log = i_log + r_log

    data_dictionary = _normalize_dictionary(llm.generate_data_dictionary(metadata), metadata)

    # Always persist as CSV (XLSX included) so the sandbox reads one format.
    clean_file_path = workspace_dir / f"clean_{Path(filename).stem}.csv"
    remediated_df.to_csv(clean_file_path, index=False)

    eda_result = graph.run_eda_workflow(
        df=remediated_df,
        metadata=metadata,
        cleaning_log=full_log,
        flagged_ids=flagged_ids,
        data_dictionary=data_dictionary,
    )

    return str(clean_file_path), {
        "details": {"rows": metadata["n_rows"], "columns": metadata["n_columns"]},
        "data_dictionary": data_dictionary,
        "cleaning_log": full_log,
        "charts": eda_result.get("charts", []),
        "executive_summary": eda_result.get("executive_summary", ""),
        "flagged_ids": sorted(flagged_ids),
    }

### --------------------------------------------------------------------------
### Multi-File Ingestion Dispatcher
### --------------------------------------------------------------------------
# Sync (not async) so FastAPI runs the heavy cleaning / LLM / embedding work in its
# threadpool instead of blocking the event loop.
@app.post("/workspaces/{workspace_id}/files", response_model=schemas.WorkspaceResponse)
def upload_workspace_files(
    workspace_id: str,
    files: list[UploadFile] = File(...),
) -> schemas.WorkspaceResponse:
    uploads = [(f, _safe_filename(f.filename)) for f in files if f.filename]
    if not uploads:
        raise HTTPException(status_code=400, detail="No files were uploaded.")
    unsupported = [name for _, name in uploads if not name.lower().endswith(SUPPORTED_EXTENSIONS)]
    if unsupported:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file format: {', '.join(unsupported)}. Supported: {', '.join(SUPPORTED_EXTENSIONS)}",
        )

    is_new = workspace_id.lower() == "new"
    if is_new:
        workspace_id = str(uuid.uuid4())

    settings.ensure_dirs()
    workspace_dir = settings.UPLOAD_DIR / workspace_id
    workspace_dir.mkdir(parents=True, exist_ok=True)
    errors: list[str] = []

    with memory.SessionLocal() as db:
        ws = db.query(memory.Workspace).filter_by(workspace_id=workspace_id).first()
        if not ws:
            if not is_new:
                raise HTTPException(status_code=404, detail=f"Workspace '{workspace_id}' not found.")
            ws = memory.Workspace(workspace_id=workspace_id, name="Analysis Workspace")
            db.add(ws)
            db.commit()

        for upload, filename in uploads:
            # Each tabular file gets its own mount inside the sandbox; refuse names that collide.
            if filename.lower().endswith(TABULAR_EXTENSIONS):
                target = container_path_for(filename)
                clash = next(
                    (f.filename for f in _workspace_files(db, workspace_id)
                     if f.file_type == "tabular" and f.filename != filename and container_path_for(f.filename) == target),
                    None,
                )
                if clash:
                    errors.append(f"{filename}: name clashes with existing dataset {clash}; rename one of them.")
                    continue

            # Re-uploading a file replaces it instead of duplicating rows / chunks.
            existing = db.query(memory.WorkspaceFile).filter_by(workspace_id=workspace_id, filename=filename).first()
            if existing:
                if existing.file_type == "document":
                    rag.delete_document_chunks(workspace_id, filename)
                db.delete(existing)
                db.commit()

            raw_bytes = upload.file.read()
            file_path = workspace_dir / filename
            file_path.write_bytes(raw_bytes)

            try:
                # ROUTE 1: Tabular Data Pipeline
                if filename.lower().endswith(TABULAR_EXTENSIONS):
                    stored_path, parsed = _ingest_tabular(raw_bytes, filename, workspace_dir)
                    file_type = "tabular"
                # ROUTE 2: Unstructured Document Pipeline (RAG)
                else:
                    stored_path = str(file_path)
                    n_chunks, preview = rag.ingest_document(file_path, workspace_id)
                    parsed = {"details": {"chunks": n_chunks}, "digest": _document_digest(filename, preview)}
                    file_type = "document"
            except Exception as exc:
                logger.exception("Failed to ingest %s", filename)
                errors.append(f"{filename}: {exc}")
                continue

            db.add(memory.WorkspaceFile(
                file_id=str(uuid.uuid4()),
                workspace_id=workspace_id,
                filename=filename,
                file_path=stored_path,
                file_type=file_type,
                parsed_metadata=json.dumps(parsed, default=str),
            ))
            db.commit()

        all_files = _workspace_files(db, workspace_id)
        if not all_files and is_new:
            db.delete(ws)
            db.commit()
            raise HTTPException(status_code=400, detail="None of the files could be ingested. " + " | ".join(errors))

        ws.executive_summary = _combined_executive_summary(all_files)
        db.commit()
        return _workspace_response(db, workspace_id, errors)


@app.get("/workspaces/{workspace_id}", response_model=schemas.WorkspaceResponse)
def get_workspace(workspace_id: str) -> schemas.WorkspaceResponse:
    with memory.SessionLocal() as db:
        return _workspace_response(db, workspace_id)

### --------------------------------------------------------------------------
### Predictive Modeling (AutoML)
### --------------------------------------------------------------------------
@app.post("/workspaces/{workspace_id}/predict", response_model=schemas.PredictiveResponse)
def run_predictive_analysis(workspace_id: str, payload: schemas.PredictiveRequest):
    with memory.SessionLocal() as db:
        _get_workspace_or_404(db, workspace_id)
        tabular_files = [f for f in _workspace_files(db, workspace_id) if f.file_type == "tabular"]
        if not tabular_files:
            raise HTTPException(status_code=400, detail="No tabular data found in this workspace to model.")

        # Use the requested file, else the first dataset that actually contains the target.
        def has_target(wf: memory.WorkspaceFile) -> bool:
            entries = json.loads(wf.parsed_metadata).get("data_dictionary", [])
            return any(e.get("column") == payload.target_column for e in entries)

        candidates = [f for f in tabular_files if f.filename == payload.filename] if payload.filename else tabular_files
        tabular_file = next((f for f in candidates if has_target(f)), None)
        if not tabular_file:
            raise HTTPException(status_code=400, detail=f"Column '{payload.target_column}' was not found in any dataset.")
        file_path = tabular_file.file_path
        flagged_ids = set(json.loads(tabular_file.parsed_metadata).get("flagged_ids", []))

    try:
        df = pd.read_csv(file_path)
        results = modeling.run_predictive_model(df, target_column=payload.target_column, flagged_ids=flagged_ids)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        logger.exception("Modeling engine failed")
        raise HTTPException(status_code=500, detail=f"Predictive modeling failed: {exc}")

    summary = llm.generate_predictive_summary(
        target_column=payload.target_column,
        problem_type=results["problem_type"],
        metrics=results["metrics"],
        top_drivers=results["top_drivers"],
    )

    return schemas.PredictiveResponse(
        problem_type=results["problem_type"],
        metrics=results["metrics"],
        top_drivers=results["top_drivers"],
        performance_plot=results["performance_plot"],
        importance_plot=results["importance_plot"],
        predictive_summary=summary,
    )

### --------------------------------------------------------------------------
### Business Rules & Chat History
### --------------------------------------------------------------------------
@app.post("/workspaces/{workspace_id}/business-rules", response_model=schemas.BusinessRule)
def create_business_rule(workspace_id: str, payload: schemas.BusinessRuleCreate):
    with memory.SessionLocal() as db:
        _get_workspace_or_404(db, workspace_id)
        rule = memory.BusinessRule(workspace_id=workspace_id, rule_text=payload.rule_text)
        db.add(rule)
        db.commit()
        db.refresh(rule)
        return schemas.BusinessRule(
            id=rule.id,
            workspace_id=rule.workspace_id,
            rule_text=rule.rule_text,
            created_at=rule.created_at
        )

@app.get("/workspaces/{workspace_id}/business-rules", response_model=list[schemas.BusinessRule])
def list_business_rules(workspace_id: str):
    with memory.SessionLocal() as db:
        return db.query(memory.BusinessRule).filter_by(workspace_id=workspace_id).order_by(memory.BusinessRule.id).all()

@app.get("/workspaces/{workspace_id}/chat-history", response_model=list[schemas.ChatMessage])
def get_chat_history(workspace_id: str, session_id: str):
    with memory.SessionLocal() as db:
        return (
            db.query(memory.ChatMessage)
            .filter_by(workspace_id=workspace_id, session_id=session_id)
            .order_by(memory.ChatMessage.id)
            .all()
        )

### --------------------------------------------------------------------------
### The Q&A Loop
### --------------------------------------------------------------------------
@app.post("/workspaces/{workspace_id}/qa", response_model=schemas.QAResponse)
def ask_question(workspace_id: str, payload: schemas.QARequest):
    with memory.SessionLocal() as db:
        _get_workspace_or_404(db, workspace_id)
    session_id = payload.session_id or str(uuid.uuid4())

    # Executes the routed (quant / doc / hybrid) LangGraph workflow
    state = graph.run_qa_workflow(workspace_id=workspace_id, session_id=session_id, question=payload.question)

    return schemas.QAResponse(
        session_id=session_id,
        answer=state.get("final_answer", ""),
        intent=state.get("intent", ""),
        generated_code=state.get("current_code"),
        execution_output=state.get("execution_output"),
        attempts=state.get("attempts", 0),
        errors=state.get("errors", []),
        sources=state.get("sources", [])
    )

### --------------------------------------------------------------------------
### Chart Q&A: questions about one expanded chart, answered from its plotted data
### --------------------------------------------------------------------------
@app.post("/workspaces/{workspace_id}/chart-qa", response_model=schemas.ChartQAResponse)
def ask_about_chart(workspace_id: str, payload: schemas.ChartQARequest):
    try:
        figure = json.loads(payload.plotly_json)
    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="plotly_json is not a valid serialized figure.")

    with memory.SessionLocal() as db:
        _get_workspace_or_404(db, workspace_id)
        tabular = [f for f in _workspace_files(db, workspace_id) if f.file_type == "tabular"]
        # Chat-generated charts can span datasets, so only narrow when the source is known.
        scoped = [f for f in tabular if f.filename == payload.source_file] or tabular
        dictionary = [
            {"filename": f.filename, "columns": json.loads(f.parsed_metadata).get("data_dictionary", [])}
            for f in scoped
        ]
        rules = [r.rule_text for r in db.query(memory.BusinessRule).filter_by(workspace_id=workspace_id).order_by(memory.BusinessRule.id)]

    answer = llm.generate_chart_answer(
        question=payload.question,
        figure_digest=llm.describe_figure(figure, payload.chart_title),
        data_dictionary=dictionary,
        business_rules=rules,
        chat_history=[{"role": t.role.value, "content": t.content} for t in payload.history],
    )
    return schemas.ChartQAResponse(answer=answer)

@app.exception_handler(ValueError)
def value_error_handler(request, exc: ValueError) -> JSONResponse:
    return JSONResponse(status_code=400, content={"detail": str(exc)})

### --------------------------------------------------------------------------
### Frontend Static Mount
### --------------------------------------------------------------------------
_FRONTEND_DIR = Path(__file__).resolve().parent / "frontend"
if _FRONTEND_DIR.is_dir():
    app.mount("/", StaticFiles(directory=str(_FRONTEND_DIR), html=True), name="frontend")
else:
    logger.warning("frontend/ directory not found next to main.py; UI will not be served.")