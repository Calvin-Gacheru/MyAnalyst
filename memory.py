# type: ignore
from __future__ import annotations
from datetime import datetime, timezone
from sqlalchemy import create_engine, text, Column, String, Integer, Text, DateTime, ForeignKey
from sqlalchemy.orm import declarative_base, sessionmaker, relationship
from pgvector.sqlalchemy import Vector

from config import settings

engine = create_engine(settings.DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

class Workspace(Base):
    __tablename__ = "workspaces"
    workspace_id = Column(String, primary_key=True)
    name = Column(String, nullable=False, default="Untitled Workspace")
    # Account that created the workspace (auth.Account.id). Every route checks it.
    owner_id = Column(Integer, index=True)
    executive_summary = Column(Text, default="")
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

class WorkspaceFile(Base):
    __tablename__ = "workspace_files"
    file_id = Column(String, primary_key=True)
    workspace_id = Column(String, ForeignKey("workspaces.workspace_id", ondelete="CASCADE"))
    filename = Column(String, nullable=False)
    file_path = Column(String, nullable=False)
    file_type = Column(String, nullable=False)  # 'tabular' or 'document'
    # JSON-encoded. Tabular files: {details, data_dictionary, cleaning_log, charts,
    # executive_summary, flagged_ids}. Documents: {details}.
    parsed_metadata = Column(Text, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

class DocumentChunk(Base):
    __tablename__ = "documents"
    chunk_id = Column(String, primary_key=True)
    workspace_id = Column(String, ForeignKey("workspaces.workspace_id", ondelete="CASCADE"))
    filename = Column(String, nullable=False)
    page_number = Column(Integer, default=0)
    content = Column(Text, nullable=False)
    # The all-MiniLM-L6-v2 model outputs 384-dimensional embeddings
    embedding = Column(Vector(384))  

class BusinessRule(Base):
    __tablename__ = "business_rules"
    id = Column(Integer, primary_key=True, autoincrement=True)
    workspace_id = Column(String, ForeignKey("workspaces.workspace_id", ondelete="CASCADE"))
    rule_text = Column(Text, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

class ChatMessage(Base):
    __tablename__ = "chat_messages"
    id = Column(Integer, primary_key=True, autoincrement=True)
    session_id = Column(String, index=True, nullable=False)
    workspace_id = Column(String, ForeignKey("workspaces.workspace_id", ondelete="CASCADE"))
    role = Column(String, nullable=False)
    content = Column(Text, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

def init_db() -> None:
    """Creates the pgvector extension and initializes all relational tables."""
    with engine.connect() as conn:
        conn.execute(text("CREATE EXTENSION IF NOT EXISTS vector;"))
        conn.commit()
    Base.metadata.create_all(bind=engine)
    # create_all doesn't add columns to existing tables: migrate databases
    # created before workspaces had owners.
    with engine.connect() as conn:
        conn.execute(text("ALTER TABLE workspaces ADD COLUMN IF NOT EXISTS owner_id INTEGER"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_workspaces_owner_id ON workspaces (owner_id)"))
        conn.commit()