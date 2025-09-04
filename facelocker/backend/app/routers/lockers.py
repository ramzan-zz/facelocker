from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from ..db import get_db
from ..models import Locker
from ..schemas import LockerOut


router = APIRouter(prefix="/api/lockers", tags=["lockers"])


@router.get("/", response_model=list[LockerOut])
def list_lockers(db: Session = Depends(get_db)):
return db.query(Locker).all()