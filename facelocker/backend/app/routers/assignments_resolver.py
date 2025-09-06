# app/routers/assignments_resolver.py
from fastapi import APIRouter, HTTPException, Query, Depends
from sqlalchemy.orm import Session
from ..db import get_db
from ..models import Assignment

router = APIRouter(prefix="/api", tags=["assignments"])


@router.get("/resolve-locker")
def resolve_locker(
    user_id: str = Query(...),
    active: bool = Query(True),
    db: Session = Depends(get_db),
):
    q = db.query(Assignment).filter(Assignment.user_id == user_id)
    if active:
        q = q.filter(Assignment.active == True)
    row = q.order_by(Assignment.created_at.desc()).first()
    if not row:
        raise HTTPException(404, "assignment_not_found")
    return {"user_id": row.user_id, "locker_id": row.locker_id}
