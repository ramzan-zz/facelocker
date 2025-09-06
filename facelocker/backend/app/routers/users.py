from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List, Optional
from pydantic import BaseModel

from ..db import get_db
from ..models import User
from ..schemas import UserOut

router = APIRouter(prefix="/api/users", tags=["users"])


class UserCreate(BaseModel):
    user_id: str
    name: Optional[str] = None
    status: Optional[str] = None  # only used if your model has this column


@router.get("/", response_model=List[UserOut])
def list_users(db: Session = Depends(get_db)):
    return db.query(User).all()


@router.post("/", response_model=UserOut, status_code=201)
def create_user(payload: UserCreate, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.user_id == payload.user_id).first()
    if existing:
        raise HTTPException(status_code=409, detail="user_id_exists")

    fields = {"user_id": payload.user_id}
    if payload.name is not None:
        fields["name"] = payload.name
    if hasattr(User, "status") and payload.status is not None:
        fields["status"] = payload.status

    row = User(**fields)
    db.add(row)
    db.commit()
    db.refresh(row)
    return row
