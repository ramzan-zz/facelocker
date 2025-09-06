from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from fastapi import Depends
from fastapi.responses import JSONResponse
from typing import List
from pathlib import Path
import uuid
import numpy as np
import cv2
import os

from ..face.engine import _FaceEngine
from ..face.db import add_face, delete_face, list_faces, init_db, FACES_DIR

router = APIRouter(prefix="/api", tags=["faces"])


@router.on_event("startup")
async def _startup():
    init_db()
    # warm engine once
    _ = _FaceEngine.get()


@router.post("/faces")
async def enroll_face(
    user_id: str = Form(...),
    image: UploadFile = File(...),
):
    if not user_id:
        raise HTTPException(status_code=400, detail="user_id required")

    raw = await image.read()
    npimg = np.frombuffer(raw, np.uint8)
    bgr = cv2.imdecode(npimg, cv2.IMREAD_COLOR)
    if bgr is None:
        raise HTTPException(400, "Invalid image")

    eng = _FaceEngine.get()
    faces = eng.embed(bgr)
    if not faces:
        raise HTTPException(422, "No face detected")

    # choose largest box
    faces.sort(key=lambda t: (t[0][2] - t[0][0]) * (t[0][3] - t[0][1]), reverse=True)
    bbox, emb = faces[0]
    # simple quality metric: box area / image area
    h, w = bgr.shape[:2]
    area = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
    quality = float(max(0.0, min(1.0, area / float(w * h))))

    face_id = f"F_{uuid.uuid4().hex[:8]}"
    user_dir = FACES_DIR / user_id
    user_dir.mkdir(parents=True, exist_ok=True)
    img_path = user_dir / f"{face_id}.jpg"
    cv2.imwrite(str(img_path), bgr)

    add_face(face_id, user_id, emb, str(img_path), quality)
    return {
        "ok": True,
        "face_id": face_id,
        "quality": quality,
        "image_url": f"/static/faces/{user_id}/{face_id}.jpg",
    }


@router.get("/faces")
async def list_all_faces(user_id: str | None = None):
    return list_faces(user_id)


@router.delete("/faces/{face_id}")
async def delete_face_route(face_id: str):
    n = delete_face(face_id)
    if n == 0:
        raise HTTPException(404, "Not found")
    return {"ok": True, "deleted": face_id}
