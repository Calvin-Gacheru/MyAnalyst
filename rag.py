# type: ignore
"""
Document RAG Module.
Parses PDFs/Word/text docs, chunks them, computes local embeddings, and saves to PostgreSQL.
"""
import uuid
from pathlib import Path
from typing import Any
from langchain_community.document_loaders import PyPDFLoader, Docx2txtLoader, TextLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from sentence_transformers import SentenceTransformer

from memory import SessionLocal, DocumentChunk

DOCUMENT_EXTENSIONS = (".pdf", ".docx", ".txt")

# Load locally (downloads weights on the first run only)
_embedder = SentenceTransformer("all-MiniLM-L6-v2")
_splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=100)

def _preview_text(texts: list[str], max_chunks: int = 8, max_chars: int = 8000) -> str:
    """Evenly spaced chunks across the whole document, so a digest of a long file
    reflects more than its first few pages."""
    step = max(1, len(texts) // max_chunks)
    return "\n\n".join(texts[::step][:max_chunks])[:max_chars]

def ingest_document(file_path: Path, workspace_id: str) -> tuple[int, str]:
    """Parses a document, generates embeddings, and inserts into PostgreSQL via SQLAlchemy.
    Returns (chunk count, a representative text preview for the document digest)."""
    suffix = file_path.suffix.lower()
    if suffix == ".pdf":
        loader = PyPDFLoader(str(file_path))
    elif suffix == ".docx":
        loader = Docx2txtLoader(str(file_path))
    elif suffix == ".txt":
        loader = TextLoader(str(file_path), autodetect_encoding=True)
    else:
        raise ValueError(f"Unsupported format: {file_path.suffix}")

    raw_docs = loader.load()
    split_docs = [d for d in _splitter.split_documents(raw_docs) if d.page_content.strip()]
    if not split_docs:
        raise ValueError(f"No extractable text found in {file_path.name} (scanned PDF?).")

    # Process embeddings in a batch array for maximum speed
    texts = [chunk.page_content for chunk in split_docs]
    embeddings = _embedder.encode(texts).tolist()

    with SessionLocal() as db:
        for i, chunk in enumerate(split_docs):
            # PyPDFLoader pages are 0-indexed; store 1-indexed so citations match the
            # document. Loaders without pages (docx/txt) are stored as 0 = "n/a".
            page = chunk.metadata.get("page")
            doc_chunk = DocumentChunk(
                chunk_id=str(uuid.uuid4()),
                workspace_id=workspace_id,
                filename=file_path.name,
                page_number=page + 1 if isinstance(page, int) else 0,
                content=chunk.page_content,
                embedding=embeddings[i]
            )
            db.add(doc_chunk)
        db.commit()

    return len(split_docs), _preview_text(texts)

def delete_document_chunks(workspace_id: str, filename: str) -> None:
    """Removes previously indexed chunks so a re-uploaded file isn't retrieved twice."""
    with SessionLocal() as db:
        db.query(DocumentChunk).filter_by(workspace_id=workspace_id, filename=filename).delete()
        db.commit()

def search_documents(workspace_id: str, query: str, top_k: int = 4) -> list[dict[str, Any]]:
    """Embeds the query and searches pgvector for the closest chunks."""
    query_vector = _embedder.encode([query])[0].tolist()

    with SessionLocal() as db:
        # pgvector cosine distance operator is <=>; MiniLM embeddings are tuned for cosine
        chunks = (
            db.query(DocumentChunk)
            .filter(DocumentChunk.workspace_id == workspace_id)
            .order_by(DocumentChunk.embedding.cosine_distance(query_vector))
            .limit(top_k)
            .all()
        )

        return [
            {
                "filename": c.filename,
                "page_number": c.page_number,
                "content": c.content
            }
            for c in chunks
        ]
