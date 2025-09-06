import os
from pydantic import BaseModel


class Settings(BaseModel):
    site_id: str = os.getenv("SITE_ID", "site-001")
    db_url: str = os.getenv("BACKEND_DB_URL", "sqlite:///./facelocker.db")
    secret_key: str = os.getenv("BACKEND_SECRET", "changeme")
    cors_origins: list[str] = os.getenv("CORS_ORIGINS", "*").split(",")
    mqtt_host: str = os.getenv("MQTT_HOST", "localhost")
    mqtt_port: int = int(os.getenv("MQTT_PORT", "1883"))
    mqtt_use_tls: bool = os.getenv("MQTT_USE_TLS", "false").lower() == "true"


settings = Settings()


