# backend/app/routers/embeddings.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
import json

from ..db import get_db
from ..models import Embedding
from ..schemas import EmbeddingOut

router = APIRouter(prefix="/api/embeddings", tags=["embeddings"])


def _parse_vec(v) -> List[float]:
    # r.vec is Text (JSON). Be robust if it's already a list.
    if isinstance(v, (list, tuple)):
        try:
            return [float(x) for x in v]
        except Exception:
            raise HTTPException(500, "Bad embedding format in DB (list)")
    try:
        parsed = json.loads(v)
        return [float(x) for x in parsed]
    except Exception:
        raise HTTPException(500, "Bad embedding format in DB (json)")


@router.get("/", response_model=List[EmbeddingOut])
def list_embeddings(db: Session = Depends(get_db)):
    rows = db.query(Embedding).all()
    return [EmbeddingOut(user_id=r.user_id, vec=_parse_vec(r.vec)) for r in rows]


@router.get("/{user_id}", response_model=List[EmbeddingOut])
def list_user_embeddings(user_id: str, db: Session = Depends(get_db)):
    rows = db.query(Embedding).filter(Embedding.user_id == user_id).all()
    return [EmbeddingOut(user_id=r.user_id, vec=_parse_vec(r.vec)) for r in rows]
