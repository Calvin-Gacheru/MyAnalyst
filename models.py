# type: ignore
from sqlalchemy import Column, Integer, String, Text, DateTime, ForeignKey, Date
from sqlalchemy.orm import declarative_base, relationship
from pgvector.sqlalchemy import Vector
from datetime import datetime

Base = declarative_base()

class User(Base):
    __tablename__ = 'users'
    
    user_id = Column(Integer, primary_key=True)
    staff_name = Column(String(255), nullable=False)
    role = Column(String(100))
    department = Column(String(100))
    
    queries = relationship("Query", back_populates="user")

class Document(Base):
    __tablename__ = 'documents'
    
    doc_id = Column(Integer, primary_key=True)
    category = Column(String(100))
    version_date = Column(Date)
    content = Column(Text, nullable=False)
    embedding = Column(Vector(384))

class Query(Base):
    __tablename__ = 'queries'
    
    query_id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey('users.user_id'), nullable=False)
    user_prompt = Column(Text, nullable=False)
    ai_answer = Column(Text)
    timestamp = Column(DateTime, default=datetime.utcnow)
    
    user = relationship("User", back_populates="queries")
    feedback = relationship("Feedback", back_populates="query", uselist=False)

class Feedback(Base):
    __tablename__ = 'feedback'
    
    feedback_id = Column(Integer, primary_key=True)
    query_id = Column(Integer, ForeignKey('queries.query_id'), unique=True, nullable=False)
    rating = Column(Integer)
    engineers_comment = Column(Text)
    
    query = relationship("Query", back_populates="feedback")