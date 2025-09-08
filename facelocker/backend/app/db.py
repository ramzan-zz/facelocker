# backend/app/db.py
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker, declarative_base
from .config import settings

IS_SQLITE = settings.db_url.startswith("sqlite")

engine = create_engine(
    settings.db_url,
    connect_args={"check_same_thread": False} if IS_SQLITE else {},
    pool_pre_ping=False if IS_SQLITE else True,  # useful for PG/MySQL
    future=True,  # SQLAlchemy 1.4/2.x style
)

# Enable SQLite pragmas so ForeignKey(ondelete="CASCADE") works and concurrency is nicer
if IS_SQLITE:

    @event.listens_for(engine, "connect")
    def _set_sqlite_pragmas(dbapi_connection, _):
        cursor = dbapi_connection.cursor()
        # Enforce FK constraints (needed for CASCADE deletes)
        cursor.execute("PRAGMA foreign_keys = ON;")
        # Better concurrency; safe for dev and most single-host setups
        cursor.execute("PRAGMA journal_mode = WAL;")
        cursor.close()


SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
    expire_on_commit=False,  # avoids stale attributes after commit
    future=True,
)

Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
