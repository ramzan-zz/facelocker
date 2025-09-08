#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

// ======== RELAY LOGIC LEVEL ========
// Define via platformio.ini: -D RELAY_ACTIVE_LOW=1 or 0
#ifndef RELAY_ACTIVE_LOW
#define RELAY_ACTIVE_LOW 1
#endif
inline int RELAY_ON() { return RELAY_ACTIVE_LOW ? LOW : HIGH; }
inline int RELAY_OFF() { return RELAY_ACTIVE_LOW ? HIGH : LOW; }

// ======== CONFIG ========
#define WIFI_SSID "Zayan"
#define WIFI_PASS "Zayan123"

#define MQTT_HOST "192.168.70.14" // broker IP (your PC's IP)
#define MQTT_PORT 1883

#define SITE_ID "site-001"
#define DEVICE_ID "esp32-01"

#ifndef LOCKER_OFFSET
#define LOCKER_OFFSET 0 // 0 for lockers 1-16, 16 for 17-32, etc.
#endif

const int NUM_CHANNELS = 16;
const int MAX_LOCKER_ID = 48;
// Map local channel (1..NUM_CHANNELS) -> ESP32 GPIO pins (edit to match your wiring)
const int RELAY_PINS[NUM_CHANNELS + 1] = {
    /*0*/ -1,
    /*1*/ 14, /*2*/ 27, /*3*/ 26, /*4*/ 25,
    /*5*/ 33, /*6*/ 32, /*7*/ 15, /*8*/ 4,
    /*9*/ 16, /*10*/ 17, /*11*/ 5, /*12*/ 18,
    /*13*/ 19, /*14*/ 21, /*15*/ 22, /*16*/ 23};

// ======== LOG MACRO ========
#define LOGF(...)                   \
    do                              \
    {                               \
        Serial.printf(__VA_ARGS__); \
    } while (0)

// ======== GLOBALS ========
WiFiClient wifi;
PubSubClient client(wifi);

String topicCmd() { return String("sites/") + SITE_ID + "/locker/cmd"; }
String topicDoor() { return String("sites/") + SITE_ID + "/locker/door"; }
String topicTele() { return String("sites/") + SITE_ID + "/locker/tele"; }

// ======== TELEMETRY ========
void publishTele(bool online, bool retained)
{
    StaticJsonDocument<128> doc;
    doc["device"] = DEVICE_ID;
    doc["online"] = online;
    char buf[128];
    size_t n = serializeJson(doc, buf, sizeof(buf));
    bool ok = client.publish(topicTele().c_str(), (uint8_t *)buf, n, retained);
    LOGF("[MQTT ->] %s (%s, retained=%d)\n", topicTele().c_str(), ok ? "sent" : "send-failed", (int)retained);
}

// ======== RELAY ========
void pulseRelay(int lockerId, int durationMs)
{
    if (lockerId < 1 || lockerId > MAX_LOCKER_ID)
    {
        LOGF("[RELAY] invalid lockerId=%d\n", lockerId);
        return;
    }
    if (lockerId <= LOCKER_OFFSET || lockerId > LOCKER_OFFSET + NUM_CHANNELS)
    {
        LOGF("[RELAY] lockerId=%d not assigned to this controller\n", lockerId);
        return;
    }

    int localId = lockerId - LOCKER_OFFSET;
    int pin = RELAY_PINS[localId];
    if (pin < 0)
    {
        LOGF("[RELAY] lockerId=%d (local=%d) has no pin mapping\n", lockerId, localId);
        return;
    }

    LOGF("[RELAY] locker_id=%d -> pin=%d, pulse=%dms (active_%s)\n",
         lockerId, pin, durationMs, RELAY_ACTIVE_LOW ? "LOW" : "HIGH");

    digitalWrite(pin, RELAY_ON());
    delay(durationMs);
    digitalWrite(pin, RELAY_OFF());
    LOGF("[RELAY] done\n");
}

// ======== CMD HANDLER ========
void handleCmd(char *topic, byte *payload, unsigned int len)
{
    // Log raw inbound payload
    LOGF("[MQTT <-] %s  ", topic);
    for (unsigned int i = 0; i < len; i++)
        Serial.write(payload[i]);
    Serial.println();

    // Parse JSON
    StaticJsonDocument<512> doc; // enough for typical unlock command
    DeserializationError err = deserializeJson(doc, payload, len);
    if (err)
    {
        LOGF("JSON parse err: %s\n", err.c_str());
        return;
    }

    // Accept alt field names (locker_id/channel, duration_ms/pulse_ms)
    const char *action = doc["action"] | "unlock";
    int lockerId = doc["locker_id"] | (int)(doc["channel"] | -1);
    int durationMs = doc["duration_ms"] | (int)(doc["pulse_ms"] | 1200);
    const char *userId = doc["user_id"] | "";
    const char *reqId = doc["request_id"] | "";

    double conf = doc["confidence"].isNull() ? 0.0 : doc["confidence"].as<double>();
    double live = doc["liveness"].isNull() ? 0.0 : doc["liveness"].as<double>();

    LOGF("[CMD] action=%s locker_id=%d duration_ms=%d user=%s req=%s conf=%.3f live=%.3f\n",
         action, lockerId, durationMs, userId, reqId, conf, live);

    if (strcmp(action, "unlock") == 0 && lockerId >= 1)
    {
        pulseRelay(lockerId, durationMs);

        // Emit door event
        StaticJsonDocument<384> ev;
        ev["locker_id"] = lockerId;
        ev["user_id"] = userId;
        ev["door_state"] = "open";
        ev["status"] = "unlocked";
        ev["confidence"] = conf;
        ev["liveness"] = live;
        ev["request_id"] = reqId;
        ev["source"] = DEVICE_ID;

        char out[384];
        size_t n = serializeJson(ev, out, sizeof(out));
        bool ok = client.publish(topicDoor().c_str(), (uint8_t *)out, n, false);
        LOGF("[MQTT ->] %s (%s)\n", topicDoor().c_str(), ok ? "sent" : "send-failed");
    }
}

void mqttCallback(char *topic, byte *payload, unsigned int len)
{
    handleCmd(topic, payload, len);
}

// ======== MQTT CONNECT ========
void ensureMqtt()
{
    while (!client.connected())
    {
        String cid = String(DEVICE_ID) + "-" + String((uint32_t)esp_random(), HEX);

        // Last Will: retained "online:false"
        bool ok = client.connect(
            cid.c_str(),
            nullptr, nullptr,
            topicTele().c_str(), 0, true,
            "{\"device\":\"" DEVICE_ID "\",\"online\":false}");

        LOGF("[MQTT] connect %s, state=%d\n", ok ? "OK" : "FAIL", client.state());
        if (ok)
        {
            client.subscribe(topicCmd().c_str(), 1);
            LOGF("[MQTT] subscribed: %s\n", topicCmd().c_str());
            publishTele(true, true); // set retained online:true
        }
        else
        {
            delay(2000);
        }
    }
}

// ======== SETUP / LOOP ========
unsigned long lastTele = 0;

void setup()
{
    Serial.begin(115200);
    delay(200);
    LOGF("\nBooting…\n");

    // Init relays
    for (int i = 1; i <= NUM_CHANNELS; ++i)
    {
        if (RELAY_PINS[i] >= 0)
        {
            pinMode(RELAY_PINS[i], OUTPUT);
            digitalWrite(RELAY_PINS[i], RELAY_OFF());
        }
    }

    // WiFi
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    while (WiFi.status() != WL_CONNECTED)
    {
        delay(300);
        Serial.print(".");
    }
    LOGF("\nWiFi up: %s  IP=%s\n", WIFI_SSID, WiFi.localIP().toString().c_str());

    // MQTT
    client.setServer(MQTT_HOST, MQTT_PORT);
    WiFi.setSleep(false); // reduce dropouts
    client.setKeepAlive(60);
    client.setSocketTimeout(5);
    client.setBufferSize(1024);
    client.setCallback(mqttCallback);

    LOGF("SITE=%s DEVICE=%s\n", SITE_ID, DEVICE_ID);
    LOGF("cmd topic:  %s\n", topicCmd().c_str());
    LOGF("door topic: %s\n", topicDoor().c_str());
    LOGF("tele topic: %s\n", topicTele().c_str());
}

void loop()
{
    if (!client.connected())
        ensureMqtt();
    client.loop();

    // periodic heartbeat (not retained)
    if (millis() - lastTele > 30000)
    {
        publishTele(true, false);
        lastTele = millis();
    }
}
