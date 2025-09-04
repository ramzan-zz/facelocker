from sqlalchemy import Column, Integer, String, Float, Boolean, ForeignKey, DateTime, JSON
from sqlalchemy.orm import relationship
from datetime import datetime
from .db import Base


class User(Base):
__tablename__ = "users"
id = Column(String, primary_key=True)
name = Column(String, nullable=False)
status = Column(String, default="active")
updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
embeddings = relationship("Embedding", back_populates="user")


class Locker(Base):
__tablename__ = "lockers"
id = Column(Integer, primary_key=True, autoincrement=False)
site_id = Column(String, index=True)
channel = Column(Integer, nullable=False)
notes = Column(String)


class Assignment(Base):
__tablename__ = "assignments"
id = Column(Integer, primary_key=True, autoincrement=True)
user_id = Column(String, ForeignKey("users.id"))
locker_id = Column(Integer, ForeignKey("lockers.id"))


class Embedding(Base):
__tablename__ = "embeddings"
id = Column(Integer, primary_key=True, autoincrement=True)
user_id = Column(String, ForeignKey("users.id"))
# store vector as JSON array for simplicity in SQLite
vec = Column(JSON)
updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
user = relationship("User", back_populates="embeddings")


class Event(Base):
__tablename__ = "events"
id = Column(Integer, primary_key=True, autoincrement=True)
ts = Column(DateTime, default=datetime.utcnow)
user_id = Column(String)
locker_id = Column(Integer)
action = Column(String)
result = Column(String)
confidence = Column(Float)
liveness = Column(Float)
source = Column(String)
request_id = Column(String)