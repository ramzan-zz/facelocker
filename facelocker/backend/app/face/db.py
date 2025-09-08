from pathlib import Path as PathlibPath
import os
import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import List, Tuple, Optional, Dict, Any
import numpy as np
import io


DB_PATH = os.getenv("DB_PATH", "/app/data/facelocker.db")
FACES_DIR = PathlibPath(os.getenv("FACES_DIR", "/app/data/faces")).resolve()
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


def _safe_unlink(p: PathlibPath) -> None:  # type annotation
    try:
        p.unlink(missing_ok=True)
    except Exception:
        pass


def _image_url(user_id: str, face_id: str) -> str:
    """
    Our API serves static files under /static.
    We save images at: FACES_DIR / user_id / {face_id}.jpg
    So the public URL is typically: /static/faces/{user_id}/{face_id}.jpg
    """
    return f"/static/faces/{user_id}/{face_id}.jpg"


# --- CRUD ---


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
    """
    Delete a single face by ID; remove DB row and the image file if present.
    Returns the number of rows deleted (0 or 1).
    """
    with get_conn() as c:
        # fetch image path first
        cur = c.execute("SELECT image_path FROM faces WHERE face_id=?", (face_id,))
        row = cur.fetchone()
        if row:
            img_path = Path(row[0])
            _safe_unlink(img_path)
        cur = c.execute("DELETE FROM faces WHERE face_id=?", (face_id,))
        return cur.rowcount


def delete_faces_by_user(user_id: str) -> tuple[int, list[str]]:
    """
    Delete all faces for a given user; remove DB rows and the image files.
    Returns (count_deleted, deleted_face_ids)
    """
    deleted_ids: list[str] = []
    with get_conn() as c:
        cur = c.execute(
            "SELECT face_id, image_path FROM faces WHERE user_id=?", (user_id,)
        )
        rows = cur.fetchall()
        for fid, img in rows:
            deleted_ids.append(fid)
            _safe_unlink(PathlibPath(img))

        c.execute("DELETE FROM faces WHERE user_id=?", (user_id,))
    return (len(deleted_ids), deleted_ids)


def list_faces(user_id: str | None = None) -> list[dict[str, Any]]:
    with get_conn() as c:
        if user_id:
            cur = c.execute(
                "SELECT face_id,user_id,image_path,quality,created_at "
                "FROM faces WHERE user_id=? ORDER BY created_at DESC",
                (user_id,),
            )
        else:
            cur = c.execute(
                "SELECT face_id,user_id,image_path,quality,created_at "
                "FROM faces ORDER BY created_at DESC"
            )
        rows = cur.fetchall()
        out: list[dict[str, Any]] = []
        for r in rows:
            face_id, uid, img_path, quality, created_at = r
            out.append(
                {
                    "face_id": face_id,
                    "user_id": uid,
                    "image_path": img_path,
                    "image_url": _image_url(uid, face_id),  # <— added
                    "quality": quality,
                    "created_at": created_at,
                }
            )
        return out


def all_embeddings() -> list[tuple[str, str, np.ndarray]]:
    with get_conn() as c:
        cur = c.execute("SELECT face_id,user_id,embedding FROM faces")
        rows = cur.fetchall()
        return [(r[0], r[1], _bytes_to_np(r[2])) for r in rows]
