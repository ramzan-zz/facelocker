# backend/app/schemas.py
from typing import Optional, List, Literal
from datetime import datetime

try:
    # Pydantic v2
    from pydantic import BaseModel, ConfigDict

    class ORMModel(BaseModel):
        model_config = ConfigDict(from_attributes=True)

except Exception:
    # Pydantic v1 fallback
    from pydantic import BaseModel

    class ORMModel(BaseModel):
        class Config:
            orm_mode = True


# ====== Read models (responses) ======


class UserOut(ORMModel):
    id: int
    user_id: str
    name: Optional[str] = None
    status: Optional[str] = "active"


# ✅ Add this:
class UserUpdate(ORMModel):
    name: Optional[str] = None
    status: Optional[str] = None  # e.g. "active" | "disabled"


class LockerOut(ORMModel):
    id: int
    locker_id: int
    site_id: Optional[str] = None
    channel: int
    notes: Optional[str] = None


class AssignmentOut(ORMModel):
    user_id: str
    locker_id: int


class EmbeddingOut(ORMModel):
    user_id: str
    vec: List[float]  # router must json-decode DB text to list[float]


class EventOut(ORMModel):
    id: int
    type: str
    user_id: Optional[str] = None
    locker_id: Optional[int] = None
    created_at: datetime


class SyncPayload(BaseModel):
    users: List[UserOut]
    lockers: List[LockerOut]
    assignments: List[AssignmentOut]
    embeddings: List[EmbeddingOut]


# ====== Write models (requests) ======


# Create a locker
class LockerCreate(BaseModel):
    locker_id: int
    site_id: Optional[str] = None
    channel: int
    notes: Optional[str] = None
    # NOTE: Your Locker model has no "active" column.
    # If you later add it, you can reintroduce a field here.


# Seed lockers (1..N, 16 per controller by default)
class LockerSeedRequest(BaseModel):
    total: int = 48
    per_controller: int = 16
    site_id: str = "site-001"
    controller_prefix: str = "esp"


# Create a user
class UserCreate(BaseModel):
    user_id: str
    name: Optional[str] = None
    status: Optional[Literal["active", "disabled"]] = "active"


# ✅ NEW: Update a user (partial PATCH)
class UserUpdate(BaseModel):
    name: Optional[str] = None
    status: Optional[Literal["active", "disabled"]] = None


# Create (or reassign) an assignment
class AssignmentCreate(BaseModel):
    user_id: str
    locker_id: int
    # If your Assignment table later adds 'active'/'ended_at', you can extend here.
