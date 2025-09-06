# backend/app/seed_dev.py
import json
from .db import SessionLocal, Base, engine
from .models import User, Locker, Assignment, Embedding


def seed():
    # Ensure tables exist
    Base.metadata.create_all(bind=engine)

    db = SessionLocal()
    try:
        # Demo user
        user = db.query(User).filter_by(user_id="U_0001").first()
        if not user:
            user = User(user_id="U_0001", name="Demo User", status="active")
            db.add(user)

        # Demo locker
        locker = db.query(Locker).filter_by(locker_id=12).first()
        if not locker:
            locker = Locker(
                locker_id=12, site_id="site-001", channel=12, notes="Demo locker"
            )
            db.add(locker)

        # Assignment
        assign = db.query(Assignment).filter_by(user_id="U_0001", locker_id=12).first()
        if not assign:
            db.add(Assignment(user_id="U_0001", locker_id=12))

        # Optional: a tiny example embedding vector
        emb = db.query(Embedding).filter_by(user_id="U_0001").first()
        if not emb:
            vec = json.dumps([0.05, 0.1, 0.2, 0.15, 0.0, 0.3])  # JSON string
            db.add(Embedding(user_id="U_0001", vec=vec))

        db.commit()
        print("Seeded: U_0001 -> Locker 12")
    finally:
        db.close()


if __name__ == "__main__":
    seed()
