import os
import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import List, Tuple, Optional
import numpy as np
import io
import json

DB_PATH = os.getenv("DB_PATH", "/app/data/facelocker.db")
FACES_DIR = Path(os.getenv("FACES_DIR", "/app/data/faces")).resolve()
FACES_DIR.mkdir(parents=True, exist_ok=True)


@contextmanager
def get_conn():
    Path(DB_PATH).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA journal_mode=WAL;")
    try:
        yield conn
    finally:
        conn.commit()
        conn.close()


SCHEMA = """
CREATE TABLE IF NOT EXISTS faces (
  face_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  embedding BLOB NOT NULL,
  image_path TEXT NOT NULL,
  quality REAL,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_faces_user ON faces(user_id);
"""


def init_db():
    with get_conn() as c:
        for stmt in SCHEMA.strip().split(";"):
            s = stmt.strip()
            if s:
                c.execute(s)


# --- helpers ---


def _np_to_bytes(arr: np.ndarray) -> bytes:
    buf = io.BytesIO()
    np.save(buf, arr.astype("float32"))
    return buf.getvalue()


def _bytes_to_np(b: bytes) -> np.ndarray:
    buf = io.BytesIO(b)
    return np.load(buf)


def add_face(
    face_id: str,
    user_id: str,
    embedding: np.ndarray,
    image_path: str,
    quality: float | None,
):
    with get_conn() as c:
        c.execute(
            "INSERT INTO faces(face_id,user_id,embedding,image_path,quality) VALUES(?,?,?,?,?)",
            (face_id, user_id, _np_to_bytes(embedding), image_path, quality),
        )


def delete_face(face_id: str) -> int:
    with get_conn() as c:
        cur = c.execute("DELETE FROM faces WHERE face_id=?", (face_id,))
        return cur.rowcount


def list_faces(user_id: str | None = None):
    with get_conn() as c:
        if user_id:
            cur = c.execute(
                "SELECT face_id,user_id,image_path,quality,created_at FROM faces WHERE user_id=? ORDER BY created_at DESC",
                (user_id,),
            )
        else:
            cur = c.execute(
                "SELECT face_id,user_id,image_path,quality,created_at FROM faces ORDER BY created_at DESC"
            )
        rows = cur.fetchall()
        return [
            {
                "face_id": r[0],
                "user_id": r[1],
                "image_path": r[2],
                "quality": r[3],
                "created_at": r[4],
            }
            for r in rows
        ]


def all_embeddings():
    with get_conn() as c:
        cur = c.execute("SELECT face_id,user_id,embedding FROM faces")
        rows = cur.fetchall()
        return [(r[0], r[1], _bytes_to_np(r[2])) for r in rows]
