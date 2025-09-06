# backend/app/models.py
from datetime import datetime
from sqlalchemy import Column, Integer, String, DateTime, Text, Float, ForeignKey
from sqlalchemy.orm import relationship
from .db import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    # Public user identifier used by the app
    user_id = Column(String, unique=True, index=True, nullable=False)
    name = Column(String, nullable=True)
    status = Column(String, default="active")
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # One-to-many: User -> Embeddings
    embeddings = relationship(
        "Embedding",
        back_populates="user",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )


class Locker(Base):
    __tablename__ = "lockers"

    id = Column(Integer, primary_key=True, index=True)
    # Public locker number used by the app/ESP
    locker_id = Column(Integer, unique=True, index=True, nullable=False)
    site_id = Column(String, index=True, nullable=True)
    channel = Column(Integer, nullable=False)
    notes = Column(String, nullable=True)


class Assignment(Base):
    __tablename__ = "assignments"

    id = Column(Integer, primary_key=True, index=True)
    # Link a user to a locker by public IDs
    user_id = Column(
        String,
        ForeignKey("users.user_id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    locker_id = Column(
        Integer,
        ForeignKey("lockers.locker_id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )


class Embedding(Base):
    __tablename__ = "embeddings"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        String,
        ForeignKey("users.user_id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    # Store vector as JSON-encoded string for SQLite compatibility
    vec = Column(Text, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    user = relationship("User", back_populates="embeddings")


class Event(Base):
    __tablename__ = "events"

    id = Column(Integer, primary_key=True, index=True)
    # core fields the app cares about
    type = Column(String, nullable=False)  # e.g. "unlock"
    user_id = Column(String, nullable=True)
    locker_id = Column(Integer, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    # optional diagnostics/telemetry (safe to ignore in responses)
    action = Column(String, nullable=True)
    result = Column(String, nullable=True)
    confidence = Column(Float, nullable=True)
    liveness = Column(Float, nullable=True)
    source = Column(String, nullable=True)
    request_id = Column(String, nullable=True)
