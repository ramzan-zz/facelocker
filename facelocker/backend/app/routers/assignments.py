from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from ..db import get_db
from ..models import Assignment
from ..schemas import AssignmentOut


router = APIRouter(prefix="/api/assignments", tags=["assignments"])


@router.get("/", response_model=list[AssignmentOut])
def list_assignments(db: Session = Depends(get_db)):
rows = db.query(Assignment).all()
return [AssignmentOut(user_id=r.user_id, locker_id=r.locker_id) for r in rows]