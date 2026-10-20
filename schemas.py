"""
Pydantic schemas shared by the FastAPI routes.
Keeping these separate from the LangGraph state (see graph.py) is intentional:
the API contract and the agent's internal working memory evolve independently.
"""
from __future__ import annotations
from datetime import datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field

### --------------------------------------------------------------------------
### Ingestion & preprocessing
### --------------------------------------------------------------------------
class ColumnMetadata(BaseModel):
    name: str
    dtype: str
    n_missing: int
    n_unique: int
    is_flagged_id: bool = False
    sample_values: list[Any] = Field(default_factory=list)

class DatasetMetadata(BaseModel):
    n_rows: int
    n_columns: int
    columns: list[ColumnMetadata]
    sample_rows: list[dict[str, Any]]

class DataDictionaryEntry(BaseModel):
    column: str
    business_meaning: str = ""
    data_type: str = ""
    notes: str = ""
    source_file: str = ""  # which workspace file the column belongs to

class CleaningLogEntry(BaseModel):
    column: str
    action: str
    detail: str
    source_file: str = ""

# Tracks the status of each individual file uploaded to the workspace
class FileIngestionMetadata(BaseModel):
    filename: str
    file_type: str  # 'tabular' or 'document'
    details: dict[str, Any]  # e.g., {"rows": 100, "columns": 5} or {"pages": 12, "chunks": 45}

# LLM-written overview of one uploaded document, with questions to start the RAG loop
class DocumentDigest(BaseModel):
    filename: str
    summary: str = ""
    starter_questions: list[str] = Field(default_factory=list)

# Full state of a workspace (all files, not just the latest upload batch)
class WorkspaceResponse(BaseModel):
    workspace_id: str
    files: list[FileIngestionMetadata]
    # Document outputs (only populated if a PDF/DOCX/TXT was included)
    document_digests: list[DocumentDigest] = Field(default_factory=list)
    # Tabular outputs (Optional, only populated if a CSV/XLSX was included)
    data_dictionary: list[DataDictionaryEntry] = Field(default_factory=list)
    cleaning_log: list[CleaningLogEntry] = Field(default_factory=list)
    charts: list[dict[str, Any]] = Field(default_factory=list)
    executive_summary: str = ""
    # Per-file ingestion failures from this request; other files in the batch still succeed.
    errors: list[str] = Field(default_factory=list)

### --------------------------------------------------------------------------
### Business rules
### --------------------------------------------------------------------------
class BusinessRuleCreate(BaseModel):
    rule_text: str = Field(..., min_length=1, max_length=2000)

class BusinessRule(BaseModel):
    id: int
    workspace_id: str
    rule_text: str
    created_at: datetime

### --------------------------------------------------------------------------
### Q&A loop
### --------------------------------------------------------------------------
class QARequest(BaseModel):
    question: str = Field(..., min_length=1)
    session_id: str | None = Field(
        default=None,
        description="Chat/session identifier used to load prior turns for context. "
                    "A new session is created when omitted.",
    )

class MessageRole(str, Enum):
    USER = "user"
    ASSISTANT = "assistant"

class ChatMessage(BaseModel):
    role: MessageRole
    content: str
    created_at: datetime

class QAResponse(BaseModel):
    session_id: str
    answer: str
    intent: str = ""  # which LangGraph track answered: 'quant' | 'doc' | 'hybrid' | 'none'
    
    # Made optional: Document RAG queries bypass the Docker sandbox and do not generate code.
    generated_code: str | None = None
    execution_output: dict[str, Any] | None = None
    
    attempts: int = 0
    errors: list[str] = Field(default_factory=list)
    
    # Filename and page number citations for doc / hybrid queries.
    sources: list[dict[str, Any]] = Field(default_factory=list)

### --------------------------------------------------------------------------
### Chart Q&A (questions scoped to one expanded chart)
### --------------------------------------------------------------------------
class ChartQATurn(BaseModel):
    role: MessageRole
    content: str

class ChartQARequest(BaseModel):
    question: str = Field(..., min_length=1)
    plotly_json: str = Field(..., min_length=2, description="The serialized Plotly figure being asked about.")
    chart_title: str = ""
    source_file: str | None = Field(
        default=None,
        description="Workspace dataset the chart was drawn from, when known; scopes the data dictionary.",
    )
    # Chart threads live in the browser, so prior turns travel with each request.
    history: list[ChartQATurn] = Field(default_factory=list)

class ChartQAResponse(BaseModel):
    answer: str

### --------------------------------------------------------------------------
### Predictive Modeling (AutoML)
### --------------------------------------------------------------------------
class PredictiveRequest(BaseModel):
    target_column: str = Field(..., min_length=1, description="The column to predict")
    filename: str | None = Field(
        default=None,
        description="Workspace file containing the target column. Inferred when omitted.",
    )

class PredictiveResponse(BaseModel):
    problem_type: str
    metrics: dict[str, str]
    top_drivers: dict[str, float]
    performance_plot: str
    importance_plot: str
    predictive_summary: str