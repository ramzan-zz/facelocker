from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .config import settings
from .db import Base, engine
from .routers import users, lockers, assignments, embeddings, events
from .mqtt_bridge import start_mqtt


app = FastAPI(title="FaceLocker Backend")
app.add_middleware(
CORSMiddleware,
allow_origins=settings.cors_origins if settings.cors_origins != ["*"] else ["*"],
allow_credentials=True,
allow_methods=["*"],
allow_headers=["*"],
)


Base.metadata.create_all(bind=engine)


app.include_router(users.router)
app.include_router(lockers.router)
app.include_router(assignments.router)
app.include_router(embeddings.router)
app.include_router(events.router)


@app.on_event("startup")
def on_startup():
start_mqtt()


if __name__ == "__main__":
import uvicorn
uvicorn.run(app, host="0.0.0.0", port=8000)