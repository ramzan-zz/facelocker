# backend/app/schemas.py
from typing import Optional, List
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


class UserOut(ORMModel):
    id: int
    user_id: str
    name: Optional[str] = None
    status: Optional[str] = "active"


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
    vec: List[float]  # JSON list parsed to Python list in the router


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


# ----- Create payloads (request bodies) -----


# Create a locker
class LockerCreate(BaseModel):
    locker_id: int
    site_id: Optional[str] = None
    channel: int
    notes: Optional[str] = None
    active: Optional[bool] = True  # if your Locker model has this column


# Seed lockers (1..N, 16 per controller by default)
class LockerSeedRequest(BaseModel):
    total: int = 48  # total lockers to create
    per_controller: int = 16  # lockers per ESP/controller
    site_id: str = "site-001"
    controller_prefix: str = "esp"  # used only to annotate notes


# (optional) Create a user
class UserCreate(BaseModel):
    user_id: str
    name: Optional[str] = None
    status: Optional[str] = "active"


# (optional) Create an assignment
class AssignmentCreate(BaseModel):
    user_id: str
    locker_id: int
    active: Optional[bool] = True
