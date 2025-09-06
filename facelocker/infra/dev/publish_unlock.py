import argparse, json, time
from paho.mqtt import client as mqtt


parser = argparse.ArgumentParser()
parser.add_argument("--host", default="127.0.0.1")
parser.add_argument("--port", type=int, default=1883)
parser.add_argument("--site", default="site-001")
parser.add_argument("--locker", type=int, default=12)
parser.add_argument("--ms", type=int, default=1200)
args = parser.parse_args()


topic = f"sites/{args.site}/locker/cmd"
client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
client.connect(args.host, args.port, 60)
client.loop_start()


payload = {
    "request_id": f"{int(time.time())}-manual",
    "user_id": "U_0001",
    "locker_id": args.locker,
    "action": "unlock",
    "duration_ms": args.ms,
    "confidence": 0.99,
    "liveness": 0.99,
    "source": "manual-test",
}
client.publish(topic, json.dumps(payload), qos=1)
print("Published to", topic, payload)
client.loop_stop()
client.disconnect()
