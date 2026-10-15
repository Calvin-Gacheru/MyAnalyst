"""
Pydantic schemas shared by the FastAPI routes.

Keeping these separate from the LangGraph state (see graph.py) is
intentional: the API contract and the agent's internal working memory
evolve independently.
"""
from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


# --------------------------------------------------------------------------
# Ingestion & preprocessing
# --------------------------------------------------------------------------

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
    business_meaning: str
    data_type: str
    notes: str = ""


class CleaningLogEntry(BaseModel):
    column: str
    action: str
    detail: str


class UploadResponse(BaseModel):
    dataset_id: str
    row_count: int
    column_count: int
    data_dictionary: list[DataDictionaryEntry]
    cleaning_log: list[CleaningLogEntry]
    charts: list[dict[str, Any]]
    executive_summary: str


# --------------------------------------------------------------------------
# Business rules
# --------------------------------------------------------------------------

class BusinessRuleCreate(BaseModel):
    rule_text: str = Field(..., min_length=1, max_length=2000)


class BusinessRule(BaseModel):
    id: int
    dataset_id: str
    rule_text: str
    created_at: datetime


# --------------------------------------------------------------------------
# Q&A loop
# --------------------------------------------------------------------------

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
    generated_code: str
    execution_output: dict[str, Any]
    attempts: int
    errors: list[str] = Field(default_factory=list)
