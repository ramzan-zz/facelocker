import os
from fastapi import APIRouter, UploadFile, File, HTTPException
from typing import List, Dict
import numpy as np
import cv2

from ..face.engine import _FaceEngine, cosine_sim
from ..face.db import all_embeddings


router = APIRouter(prefix="/api", tags=["recognition"])

THRESHOLD = float(os.getenv("FACE_COS_THRESHOLD", 0.75))  # cosine similarity
TOPK = 5


@router.post("/recognize")
async def recognize(image: UploadFile = File(...)):
    raw = await image.read()
    npimg = np.frombuffer(raw, np.uint8)
    bgr = cv2.imdecode(npimg, cv2.IMREAD_COLOR)
    if bgr is None:
        raise HTTPException(400, "Invalid image")

    eng = _FaceEngine.get()
    dets = eng.embed(bgr)
    if not dets:
        return {"faces": []}

    # Load gallery
    gallery = all_embeddings()  # list of (face_id, user_id, emb)
    if not gallery:
        return {"faces": [], "error": "gallery_empty"}

    results = []
    for bbox, qemb in dets:
        # compare to gallery
        sims = []
        for fid, uid, gemb in gallery:
            sims.append((fid, uid, cosine_sim(qemb, gemb)))
        sims.sort(key=lambda x: x[2], reverse=True)
        top = sims[:TOPK]
        best = top[0]
        match = None
        if best[2] >= THRESHOLD:
            match = {
                "user_id": best[1],
                "face_id": best[0],
                "similarity": round(float(best[2]), 4),
            }
        results.append(
            {
                "bbox": [float(v) for v in bbox],
                "top": [
                    {"face_id": fid, "user_id": uid, "similarity": round(float(s), 4)}
                    for fid, uid, s in top
                ],
                "best": match,
            }
        )
    return {"faces": results}
