from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from ..db import get_db
from ..models import Embedding
from ..schemas import EmbeddingOut

router = APIRouter(prefix="/api/embeddings", tags=["embeddings"])


@router.get("/", response_model=list[EmbeddingOut])
def list_embeddings(db: Session = Depends(get_db)):
    rows = db.query(Embedding).all()
    return [EmbeddingOut(user_id=r.user_id, vec=r.vec) for r in rows]


