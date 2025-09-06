# backend/app/routers/assignments.py (add to existing router)
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import Optional
from pydantic import BaseModel
from ..db import get_db
from ..models import Assignment, User, Locker
from ..schemas import AssignmentOut

router = APIRouter(prefix="/api/assignments", tags=["assignments"])


class AssignmentCreate(BaseModel):
    user_id: str
    locker_id: int
    active: Optional[bool] = True  # honored only if column exists


@router.post("/", response_model=AssignmentOut, status_code=201)
def create_assignment(payload: AssignmentCreate, db: Session = Depends(get_db)):
    if not db.query(User).filter(User.user_id == payload.user_id).first():
        raise HTTPException(status_code=404, detail="user_not_found")
    if not db.query(Locker).filter(Locker.locker_id == payload.locker_id).first():
        raise HTTPException(status_code=404, detail="locker_not_found")

    if hasattr(Assignment, "active"):
        db.query(Assignment).filter(
            Assignment.user_id == payload.user_id, Assignment.active == True
        ).update({"active": False})
        db.commit()
        row = Assignment(
            user_id=payload.user_id,
            locker_id=payload.locker_id,
            active=bool(payload.active),
        )
    else:
        row = Assignment(user_id=payload.user_id, locker_id=payload.locker_id)

    db.add(row)
    db.commit()
    db.refresh(row)
    return row
