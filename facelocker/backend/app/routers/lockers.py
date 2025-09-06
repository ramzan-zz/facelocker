from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List
from pydantic import BaseModel

from ..db import get_db
from ..models import Locker, Assignment
from ..schemas import LockerOut, LockerCreate  # keep your existing schema

router = APIRouter(prefix="/api/lockers", tags=["lockers"])


# ---------- List all lockers ----------
@router.get("/", response_model=List[LockerOut])
def list_lockers(db: Session = Depends(get_db)):
    return db.query(Locker).order_by(Locker.locker_id.asc()).all()


# ---------- Create a locker (NO 'active' passed to model) ----------
@router.post("/", response_model=LockerOut, status_code=201)
def create_locker(payload: LockerCreate, db: Session = Depends(get_db)):
    exists = db.query(Locker).filter(Locker.locker_id == payload.locker_id).first()
    if exists:
        raise HTTPException(status_code=409, detail="locker_id_exists")

    row = Locker(
        locker_id=payload.locker_id,
        site_id=payload.site_id,
        channel=payload.channel,
        notes=payload.notes,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


# ---------- List free lockers (don’t assume Locker.active/Assignment.active exists) ----------
@router.get("/free", response_model=List[LockerOut])
def list_free_lockers(db: Session = Depends(get_db)):
    # If Assignment has an 'active' flag, use it; otherwise treat any assignment as taking the locker
    try:
        subq = (
            db.query(Assignment.locker_id).filter(Assignment.active == True).subquery()
        )
    except Exception:
        subq = db.query(Assignment.locker_id).subquery()

    rows = (
        db.query(Locker)
        .filter(~Locker.locker_id.in_(subq))
        .order_by(Locker.locker_id.asc())
        .all()
    )
    return rows


# ---------- Seed lockers 1..N ----------
class SeedRequest(BaseModel):
    total: int = 48
    per_controller: int = 16
    site_id: str = "site-001"
    controller_prefix: str = "esp"


def _do_seed(
    total: int, per_controller: int, site_id: str, controller_prefix: str, db: Session
):
    created_or_existing = []
    for i in range(1, total + 1):
        controller_idx = (i - 1) // per_controller + 1
        channel = (i - 1) % per_controller + 1
        notes = f"controller={controller_prefix}{controller_idx};channel={channel}"

        row = db.query(Locker).filter(Locker.locker_id == i).first()
        if row is None:
            row = Locker(
                locker_id=i,
                site_id=site_id,
                channel=channel,
                notes=notes,
            )
            db.add(row)
            db.commit()
            db.refresh(row)
        created_or_existing.append(row)

    created_or_existing.sort(key=lambda x: x.locker_id)
    return created_or_existing


@router.post("/seed", response_model=List[LockerOut])
def seed_lockers_json(payload: SeedRequest, db: Session = Depends(get_db)):
    return _do_seed(
        payload.total,
        payload.per_controller,
        payload.site_id,
        payload.controller_prefix,
        db,
    )


# Handy GET variant so you can seed without JSON quoting issues in PowerShell
@router.get("/seed", response_model=List[LockerOut])
def seed_lockers_query(
    total: int = Query(48, ge=1),
    per_controller: int = Query(16, ge=1),
    site_id: str = Query("site-001"),
    controller_prefix: str = Query("esp"),
    db: Session = Depends(get_db),
):
    return _do_seed(total, per_controller, site_id, controller_prefix, db)
