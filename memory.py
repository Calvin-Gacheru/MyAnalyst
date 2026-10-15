"""
SQLite-backed persistence for MyAnalyst.

Stores three things:
  * datasets           - one row per uploaded CSV (file path + data dictionary JSON)
  * business_rules     - user-defined, persistent rules the Planner node must honor
  * chat_messages      - Q&A turn history, keyed by session_id

Every public function opens and closes its own connection so this module
is safe to call from FastAPI's threadpool-executed sync endpoints and from
LangGraph nodes alike. No connection state is held on the module.
"""
from __future__ import annotations

import json
import sqlite3
import uuid
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Iterator

from config import settings

_SCHEMA = """
CREATE TABLE IF NOT EXISTS datasets (
    dataset_id      TEXT PRIMARY KEY,
    file_path       TEXT NOT NULL,
    data_dictionary TEXT NOT NULL,   -- JSON-encoded list[DataDictionaryEntry]
    cleaning_log    TEXT NOT NULL,   -- JSON-encoded list[CleaningLogEntry]
    executive_summary TEXT,                 -- optional executive summary text
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS business_rules (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    dataset_id  TEXT NOT NULL REFERENCES datasets(dataset_id),
    rule_text   TEXT NOT NULL,
    created_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS chat_messages (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id  TEXT NOT NULL,
    dataset_id  TEXT NOT NULL REFERENCES datasets(dataset_id),
    role        TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content     TEXT NOT NULL,
    created_at  TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_business_rules_dataset ON business_rules(dataset_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_session ON chat_messages(session_id);
"""


@contextmanager
def _connect() -> Iterator[sqlite3.Connection]:
    settings.ensure_dirs()
    conn = sqlite3.connect(settings.SQLITE_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db() -> None:
    """Create tables if they do not already exist. Call once at startup."""
    with _connect() as conn:
        conn.executescript(_SCHEMA)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


# --------------------------------------------------------------------------
# Datasets
# --------------------------------------------------------------------------

@dataclass(frozen=True)
class DatasetRecord:
    dataset_id: str
    file_path: str
    data_dictionary: list[dict[str, Any]]
    cleaning_log: list[dict[str, Any]]
    created_at: str
    executive_summary: str = ""


def save_dataset(
    *,
    file_path: str,
    data_dictionary: list[dict[str, Any]],
    cleaning_log: list[dict[str, Any]],
    executive_summary: str = "",
    dataset_id: str | None = None,
) -> str:
    dataset_id = dataset_id or str(uuid.uuid4())
    with _connect() as conn:
        conn.execute(
            """
            INSERT INTO datasets (dataset_id, file_path, data_dictionary, cleaning_log, executive_summary, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (dataset_id, file_path, json.dumps(data_dictionary), json.dumps(cleaning_log), executive_summary, _now()),
        )
    return dataset_id


def get_dataset(dataset_id: str) -> DatasetRecord | None:
    with _connect() as conn:
        row = conn.execute(
            "SELECT * FROM datasets WHERE dataset_id = ?", (dataset_id,)
        ).fetchone()
    if row is None:
        return None
    return DatasetRecord(
        dataset_id=row["dataset_id"],
        file_path=row["file_path"],
        data_dictionary=json.loads(row["data_dictionary"]),
        cleaning_log=json.loads(row["cleaning_log"]),
        executive_summary=row["executive_summary"] or "",
        created_at=row["created_at"]
    )


# --------------------------------------------------------------------------
# Business rules
# --------------------------------------------------------------------------

def add_business_rule(dataset_id: str, rule_text: str) -> int:
    with _connect() as conn:
        cur = conn.execute(
            "INSERT INTO business_rules (dataset_id, rule_text, created_at) VALUES (?, ?, ?)",
            (dataset_id, rule_text, _now()),
        )
        return int(cur.lastrowid)


def get_business_rules(dataset_id: str) -> list[dict[str, Any]]:
    with _connect() as conn:
        rows = conn.execute(
            "SELECT * FROM business_rules WHERE dataset_id = ? ORDER BY created_at ASC",
            (dataset_id,),
        ).fetchall()
    return [dict(row) for row in rows]


# --------------------------------------------------------------------------
# Chat history
# --------------------------------------------------------------------------

def add_chat_message(session_id: str, dataset_id: str, role: str, content: str) -> None:
    with _connect() as conn:
        conn.execute(
            """
            INSERT INTO chat_messages (session_id, dataset_id, role, content, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (session_id, dataset_id, role, content, _now()),
        )


def get_chat_history(session_id: str, limit: int = 50) -> list[dict[str, Any]]:
    with _connect() as conn:
        rows = conn.execute(
            """
            SELECT * FROM chat_messages
            WHERE session_id = ?
            ORDER BY created_at ASC
            LIMIT ?
            """,
            (session_id, limit),
        ).fetchall()
    return [dict(row) for row in rows]
