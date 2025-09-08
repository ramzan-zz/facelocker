# backend/app/routers/assignments.py
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import Optional, List
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
    # Validate FK presence
    if not db.query(User).filter(User.user_id == payload.user_id).first():
        raise HTTPException(status_code=404, detail="user_not_found")
    if not db.query(Locker).filter(Locker.locker_id == payload.locker_id).first():
        raise HTTPException(status_code=404, detail="locker_not_found")

    # Two branches depending on whether your Assignment model has "active"
    if hasattr(Assignment, "active"):
        # Deactivate current assignment for this user
        db.query(Assignment).filter(
            Assignment.user_id == payload.user_id,
            Assignment.active == True,  # noqa: E712
        ).update({"active": False})

        # Also free the locker: deactivate whomever currently has that locker
        db.query(Assignment).filter(
            Assignment.locker_id == payload.locker_id,
            Assignment.active == True,  # noqa: E712
        ).update({"active": False})

        db.commit()

        row = Assignment(
            user_id=payload.user_id,
            locker_id=payload.locker_id,
            active=bool(payload.active),
        )
    else:
        # No "active"/"ended_at" columns → enforce uniqueness by deleting old rows.
        # This keeps the DB representing only the current state.
        db.query(Assignment).filter(Assignment.user_id == payload.user_id).delete()
        db.query(Assignment).filter(Assignment.locker_id == payload.locker_id).delete()
        db.commit()

        row = Assignment(user_id=payload.user_id, locker_id=payload.locker_id)

    db.add(row)
    db.commit()
    db.refresh(row)
    return row


@router.get("/", response_model=List[AssignmentOut])
def list_assignments(
    user_id: Optional[str] = Query(None),
    only_open: bool = Query(False),  # kept for compatibility
    db: Session = Depends(get_db),
):
    q = db.query(Assignment)
    if user_id:
        q = q.filter(Assignment.user_id == user_id)

    # If you add "active"/"ended_at" later, this keeps working.
    if only_open:
        if hasattr(Assignment, "ended_at"):
            q = q.filter(Assignment.ended_at == None)  # noqa: E711
        elif hasattr(Assignment, "active"):
            q = q.filter(Assignment.active == True)  # noqa: E712

    # No created_at in your model; fall back to id DESC as "most recent"
    order_col = getattr(Assignment, "created_at", getattr(Assignment, "id"))
    return q.order_by(order_col.desc()).all()


@router.get("/current", response_model=AssignmentOut)
def get_current_assignment(
    user_id: str = Query(...),
    db: Session = Depends(get_db),
):
    q = db.query(Assignment).filter(Assignment.user_id == user_id)
    if hasattr(Assignment, "ended_at"):
        q = q.filter(Assignment.ended_at == None)  # noqa: E711
    elif hasattr(Assignment, "active"):
        q = q.filter(Assignment.active == True)  # noqa: E712

    order_col = getattr(Assignment, "created_at", getattr(Assignment, "id"))
    row = q.order_by(order_col.desc()).first()
    if not row:
        raise HTTPException(404, "assignment_not_found")
    return row
