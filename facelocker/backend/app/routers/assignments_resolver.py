# app/routers/assignments_resolver.py
from fastapi import APIRouter, HTTPException, Query, Depends
from sqlalchemy.orm import Session
from ..db import get_db
from ..models import Assignment

router = APIRouter(prefix="/api", tags=["assignments"])


@router.get("/resolve-locker")
def resolve_locker(
    user_id: str = Query(...),
    only_open: bool = Query(True),
    db: Session = Depends(get_db),
):
    q = db.query(Assignment).filter(Assignment.user_id == user_id)

    # Prefer ended_at==NULL if present; otherwise fall back to active==True if present.
    if only_open:
        if hasattr(Assignment, "ended_at"):
            q = q.filter(Assignment.ended_at == None)  # noqa: E711
        elif hasattr(Assignment, "active"):
            q = q.filter(Assignment.active == True)  # noqa: E712

    # Order by created_at desc if you have it, otherwise by id desc
    order_col = getattr(Assignment, "created_at", getattr(Assignment, "id"))
    row = q.order_by(order_col.desc()).first()
    if not row:
        raise HTTPException(404, "assignment_not_found")

    return {"user_id": row.user_id, "locker_id": row.locker_id}
