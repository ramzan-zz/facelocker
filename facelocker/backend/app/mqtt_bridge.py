import json
import threading
import paho.mqtt.client as mqtt
from .config import settings
from .db import SessionLocal
from .models import Event


TOPIC_TELE = f"sites/{settings.site_id}/locker/tele"
TOPIC_DOOR = f"sites/{settings.site_id}/locker/door"


_client = None


def on_connect(client, userdata, flags, reason_code, properties=None):
print("MQTT connected", reason_code)
client.subscribe([(TOPIC_TELE, 0), (TOPIC_DOOR, 0)])


def on_message(client, userdata, msg):
payload = json.loads(msg.payload.decode("utf-8"))
with SessionLocal() as db:
e = Event(
user_id=payload.get("user_id"),
locker_id=payload.get("locker_id"),
action=payload.get("status", "unknown"),
result=payload.get("door_state"),
confidence=payload.get("confidence"),
liveness=payload.get("liveness"),
source=payload.get("source"),
request_id=payload.get("request_id"),
)
db.add(e)
db.commit()


def start_mqtt():
global _client
_client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
_client.on_connect = on_connect
_client.on_message = on_message
_client.connect(settings.mqtt_host, settings.mqtt_port, 60)
thread = threading.Thread(target=_client.loop_forever, daemon=True)
thread.start()