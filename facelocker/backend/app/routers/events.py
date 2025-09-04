from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from ..db import get_db
from ..models import Event


router = APIRouter(prefix="/api/events", tags=["events"])


@router.get("/")
def list_events(db: Session = Depends(get_db)):
return db.query(Event).order_by(Event.id.desc()).limit(200).all()