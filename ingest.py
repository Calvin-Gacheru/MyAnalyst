# type: ignore
import os
from langchain_community.document_loaders import PyPDFLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_huggingface import HuggingFaceEmbeddings 
from database import SessionLocal
from models import Document
from datetime import date

def ingest_pdf(file_path: str, category: str):
    print(f"Loading document: {file_path}")
    loader = PyPDFLoader(file_path)
    docs = loader.load()
    
    print("Chunking document...")
    text_splitter = RecursiveCharacterTextSplitter(
        chunk_size=1000,
        chunk_overlap=100
    )
    chunks = text_splitter.split_documents(docs)
    
    print("Generating embeddings...")
    # Initialize the embedding model
    embeddings_model = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")
    texts = [chunk.page_content for chunk in chunks]
    embeddings = embeddings_model.embed_documents(texts)
    
    print("Saving to PostgreSQL...")
    db = SessionLocal()
    try:
        for i, chunk in enumerate(chunks):
            doc = Document(
                category=category,
                version_date=date.today(),
                content=chunk.page_content,
                embedding=embeddings[i]
            )
            db.add(doc)
        db.commit()
        print(f"Successfully ingested {len(chunks)} chunks from {file_path}.")
    except Exception as e:
        db.rollback()
        print(f"Database Error: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    pdf_filename = "troubleshooting_guide.pdf" 

    if not os.path.exists(pdf_filename):
        print(f"ERROR: File '{pdf_filename}' not found.")
    else:
        ingest_pdf(pdf_filename, "Technical Documentation")