# backend/app/mqtt_bridge.py
import json
import threading
import traceback
import paho.mqtt.client as mqtt

from .config import settings
from .db import SessionLocal
from .models import Event

TOPIC_TELE = f"sites/{settings.site_id}/locker/tele"
TOPIC_DOOR = f"sites/{settings.site_id}/locker/door"

_client = None
_client_thread = None


def _persist_event(payload: dict, topic: str) -> None:
    """Persist an Event row from a received MQTT payload."""
    try:
        with SessionLocal() as db:
            e = Event(
                # Required by models.py
                type="door" if topic == TOPIC_DOOR else "tele",
                user_id=payload.get("user_id"),
                locker_id=payload.get("locker_id"),
                # Optional diagnostics
                action=payload.get("status") or payload.get("action"),
                result=payload.get("door_state") or payload.get("result"),
                confidence=payload.get("confidence"),
                liveness=payload.get("liveness"),
                source=payload.get("source") or "mqtt",
                request_id=payload.get("request_id"),
            )
            db.add(e)
            db.commit()
    except Exception:
        print("MQTT persist error:\n", traceback.format_exc())


# Paho v2 callback signatures
def on_connect(client, userdata, flags, reason_code, properties=None):
    print(f"MQTT connected: {reason_code}")
    # (Re)subscribe on connect
    client.subscribe([(TOPIC_TELE, 0), (TOPIC_DOOR, 0)])


def on_message(client, userdata, msg):
    try:
        payload = json.loads(msg.payload.decode("utf-8"))
    except Exception:
        print(f"MQTT invalid JSON on {msg.topic}: {msg.payload!r}")
        return
    _persist_event(payload, msg.topic)


def start_mqtt():
    """Start a background MQTT client thread (idempotent)."""
    global _client, _client_thread
    if _client is not None:
        return

    _client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    _client.on_connect = on_connect
    _client.on_message = on_message

    # Optional TLS (dev defaults to False)
    if getattr(settings, "mqtt_use_tls", False):
        _client.tls_set()  # uses system CAs

    # Optional username/password (only if you later add them to Settings)
    if hasattr(settings, "mqtt_username") and getattr(settings, "mqtt_username"):
        _client.username_pw_set(
            getattr(settings, "mqtt_username"),
            getattr(settings, "mqtt_password", None),
        )

    _client.connect(settings.mqtt_host, settings.mqtt_port, keepalive=60)
    _client_thread = threading.Thread(target=_client.loop_forever, daemon=True)
    _client_thread.start()
