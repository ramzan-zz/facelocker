from pydantic import BaseModel, Field
from typing import List, Optional


class UserOut(BaseModel):
id: str
name: str
status: str


class LockerOut(BaseModel):
id: int
site_id: str
channel: int
notes: Optional[str] = None


class AssignmentOut(BaseModel):
user_id: str
locker_id: int


class EmbeddingOut(BaseModel):
user_id: str
vec: List[float]


class SyncPayload(BaseModel):
users: List[UserOut]
lockers: List[LockerOut]
assignments: List[AssignmentOut]
embeddings: List[EmbeddingOut]