# app/main.py
import os
from pathlib import Path
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .config import settings
from .db import Base, engine
from .mqtt_bridge import start_mqtt

# Routers
from .routers import users, lockers, assignments, embeddings, events
from .routers.faces import router as faces_router
from .routers.recognize import router as recognize_router
from .routers import assignments_resolver

app = FastAPI(title="FaceLocker Backend")  # ← create app first

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins if settings.cors_origins != ["*"] else ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Ensure faces dir exists BEFORE mounting static
faces_dir = Path(os.getenv("FACES_DIR", "/app/data/faces")).resolve()
faces_dir.mkdir(parents=True, exist_ok=True)
app.mount("/static/faces", StaticFiles(directory=str(faces_dir)), name="faces")

# Create DB tables
Base.metadata.create_all(bind=engine)

# Include routers AFTER app is created
app.include_router(users.router)
app.include_router(lockers.router)
app.include_router(assignments.router)
app.include_router(embeddings.router)
app.include_router(events.router)
app.include_router(faces_router)
app.include_router(recognize_router)
app.include_router(assignments_resolver.router)


@app.on_event("startup")
def on_startup():
    start_mqtt()


@app.get("/healthz")
def healthz():
    return {"ok": True}
