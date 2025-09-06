import os
import threading
from pathlib import Path
import numpy as np


class _FaceEngine:
    _instance = None
    _lock = threading.Lock()

    def __init__(self):
        from insightface.app import FaceAnalysis

        models_dir = os.getenv("FACE_MODELS_DIR")  # may be None/empty
        provider = os.getenv("FACE_PROVIDER", "CPU").upper()
        pack = os.getenv("FACE_PACK", "buffalo_sc")

        if provider == "GPU":
            providers = ["CUDAExecutionProvider", "CPUExecutionProvider"]
        else:
            providers = ["CPUExecutionProvider"]

        # Only pass `root` when it’s a valid path
        if models_dir and models_dir.strip():
            Path(models_dir).mkdir(parents=True, exist_ok=True)
            self.app = FaceAnalysis(name=pack, root=models_dir, providers=providers)
        else:
            self.app = FaceAnalysis(name=pack, providers=providers)

        self.app.prepare(ctx_id=0, det_size=(640, 640))
        self.dim = 512

    @classmethod
    def get(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = _FaceEngine()
        return cls._instance

    def embed(self, image_bgr: np.ndarray):
        faces = self.app.get(image_bgr)
        if not faces:
            return []
        out = []
        for f in faces:
            emb = f.normed_embedding
            out.append((f.bbox.astype(float).tolist(), emb.astype(np.float32)))
        return out


def cosine_sim(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.dot(a, b))
