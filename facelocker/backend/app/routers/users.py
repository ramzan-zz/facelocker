# backend/app/routers/users.py
from fastapi import APIRouter, Depends, HTTPException, Path as FPath, Response

from sqlalchemy.orm import Session
from typing import List, Optional

from ..db import get_db
from ..models import User
from ..schemas import UserOut, UserCreate, UserUpdate  # <- ensure these exist
from ..face.db import delete_faces_by_user


router = APIRouter(prefix="/api/users", tags=["users"])


@router.get("/", response_model=List[UserOut])
def list_users(db: Session = Depends(get_db)):
    """List all users (active + disabled)."""
    return db.query(User).order_by(User.user_id.asc()).all()


@router.get("/{user_id}", response_model=UserOut)
def get_user(user_id: str = FPath(...), db: Session = Depends(get_db)):
    """Fetch a single user by public user_id."""
    row = db.query(User).filter(User.user_id == user_id).first()
    if not row:
        raise HTTPException(status_code=404, detail="user_not_found")
    return row


@router.post("/", response_model=UserOut, status_code=201)
def create_user(payload: UserCreate, db: Session = Depends(get_db)):
    """Create a user. 409 if user_id already exists."""
    existing = db.query(User).filter(User.user_id == payload.user_id).first()
    if existing:
        raise HTTPException(status_code=409, detail="user_id_exists")

    fields = {"user_id": payload.user_id}
    if payload.name is not None:
        fields["name"] = payload.name
    if payload.status is not None:
        # Expect "active" or "disabled"
        if payload.status not in ("active", "disabled"):
            raise HTTPException(status_code=400, detail="invalid_status")
        fields["status"] = payload.status

    row = User(**fields)
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


@router.patch("/{user_id}", response_model=UserOut)
def update_user(
    user_id: str = FPath(...), payload: UserUpdate = None, db: Session = Depends(get_db)
):
    """Partial update: name and/or status (active/disabled)."""
    row = db.query(User).filter(User.user_id == user_id).first()
    if not row:
        raise HTTPException(status_code=404, detail="user_not_found")

    changed = False
    if payload is not None:
        if payload.name is not None:
            row.name = payload.name
            changed = True
        if payload.status is not None:
            if payload.status not in ("active", "disabled"):
                raise HTTPException(status_code=400, detail="invalid_status")
            row.status = payload.status
            changed = True

    if changed:
        db.add(row)
        db.commit()
        db.refresh(row)
    return row


@router.post("/{user_id}/disable", response_model=UserOut)
def disable_user(user_id: str, db: Session = Depends(get_db)):
    row = db.query(User).filter(User.user_id == user_id).first()
    if not row:
        raise HTTPException(status_code=404, detail="user_not_found")
    if hasattr(User, "status"):
        row.status = "disabled"
        db.commit()
        db.refresh(row)
    return row


@router.post("/{user_id}/enable", response_model=UserOut)
def enable_user(user_id: str, db: Session = Depends(get_db)):
    row = db.query(User).filter(User.user_id == user_id).first()
    if not row:
        raise HTTPException(status_code=404, detail="user_not_found")
    if hasattr(User, "status"):
        row.status = "active"
        db.commit()
        db.refresh(row)
    return row


@router.delete("/{user_id}", status_code=204)
def delete_user(user_id: str = FPath(...), db: Session = Depends(get_db)):
    row = db.query(User).filter(User.user_id == user_id).first()
    if not row:
        raise HTTPException(status_code=404, detail="user_not_found")

    db.delete(row)
    db.commit()

    # also remove all face rows + image files for this user
    try:
        delete_faces_by_user(user_id)
    except Exception:
        # don’t fail delete if file cleanup hiccups
        pass

    return Response(status_code=204)
