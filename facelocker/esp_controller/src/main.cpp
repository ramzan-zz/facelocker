#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

// RELAY_ACTIVE_LOW comes from platformio.ini build_flags (-D RELAY_ACTIVE_LOW=0/1)
#ifndef RELAY_ACTIVE_LOW
#define RELAY_ACTIVE_LOW 1
#endif

inline int RELAY_ON() { return RELAY_ACTIVE_LOW ? LOW : HIGH; }
inline int RELAY_OFF() { return RELAY_ACTIVE_LOW ? HIGH : LOW; }

// ======== CONFIG ========
#define WIFI_SSID "Zayan"
#define WIFI_PASS "Zayan123"
#define MQTT_HOST "192.168.70.14" // <-- your PC's IP
#define MQTT_PORT 1883
#define SITE_ID "site-001"
#define DEVICE_ID "esp32-01"

// Map locker_id (1..16) -> ESP32 GPIO pins (edit to match your wiring)
const int NUM_CHANNELS = 16;
const int RELAY_PINS[NUM_CHANNELS + 1] = {
    /*0*/ -1,
    /*1*/ 14, /*2*/ 27, /*3*/ 26, /*4*/ 25,
    /*5*/ 33, /*6*/ 32, /*7*/ 15, /*8*/ 4,
    /*9*/ 16, /*10*/ 17, /*11*/ 5, /*12*/ 18,
    /*13*/ 19, /*14*/ 21, /*15*/ 22, /*16*/ 23};
// ========================

WiFiClient wifi;
PubSubClient client(wifi);

String topicCmd() { return String("sites/") + SITE_ID + "/locker/cmd"; }
String topicDoor() { return String("sites/") + SITE_ID + "/locker/door"; }
String topicTele() { return String("sites/") + SITE_ID + "/locker/tele"; }

void publishTele(bool online)
{
    StaticJsonDocument<128> doc;
    doc["device"] = DEVICE_ID;
    doc["online"] = online;
    char buf[128];
    size_t n = serializeJson(doc, buf, sizeof(buf));
    client.publish(topicTele().c_str(), (uint8_t *)buf, n, true);
}

void pulseRelay(int lockerId, int durationMs)
{
    if (lockerId < 1 || lockerId > NUM_CHANNELS)
        return;
    int pin = RELAY_PINS[lockerId];
    if (pin < 0)
        return;

    digitalWrite(pin, RELAY_ON());
    delay(durationMs);
    digitalWrite(pin, RELAY_OFF());
}

void handleCmd(char *topic, byte *payload, unsigned int len)
{
    JsonDocument doc; // ArduinoJson v7 style
    DeserializationError err = deserializeJson(doc, payload, len);
    if (err)
    {
        Serial.printf("JSON parse err: %s\n", err.c_str());
        return;
    }

    const char *action = doc["action"] | "unlock";
    int lockerId = doc["locker_id"] | -1;
    int durationMs = doc["duration_ms"] | 1200;
    const char *userId = doc["user_id"] | "";
    const char *reqId = doc["request_id"] | "";

    // 👇 explicitly read as double so it doesn’t fall back to 0
    double conf = doc["confidence"].isNull() ? 0.0 : doc["confidence"].as<double>();
    double live = doc["liveness"].isNull() ? 0.0 : doc["liveness"].as<double>();

    if (strcmp(action, "unlock") == 0 && lockerId >= 1)
    {
        pulseRelay(lockerId, durationMs);

        JsonDocument ev;
        ev["locker_id"] = lockerId;
        ev["user_id"] = userId;
        ev["door_state"] = "open";
        ev["status"] = "unlocked";
        ev["confidence"] = conf; // <-- now forwarded correctly
        ev["liveness"] = live;   // <--
        ev["request_id"] = reqId;
        ev["source"] = DEVICE_ID;

        char out[384];
        size_t n = serializeJson(ev, out, sizeof(out));
        client.publish(topicDoor().c_str(), (uint8_t *)out, n, false);
    }
}

void mqttCallback(char *topic, byte *payload, unsigned int len)
{
    handleCmd(topic, payload, len);
}

void ensureMqtt()
{
    while (!client.connected())
    {
        String cid = String(DEVICE_ID) + "-" + String((uint32_t)esp_random(), HEX);
        // Last Will: retained "offline"
        bool ok = client.connect(
            cid.c_str(), nullptr, nullptr,
            topicTele().c_str(), 0, true,
            "{\"device\":\"" DEVICE_ID "\",\"online\":false}");
        Serial.printf("[MQTT] connect %s, state=%d\n", ok ? "OK" : "FAIL", client.state());
        if (ok)
        {
            client.subscribe(topicCmd().c_str(), 1);
            publishTele(true); // retained "online" to overwrite offline

            client.publish(topicTele().c_str(),
                           (const uint8_t *)"{\"device\":\"esp32-01\",\"online\":true}",
                           strlen("{\"device\":\"esp32-01\",\"online\":true}"),
                           false); // retained=false
        }
        else
        {
            delay(2000);
        }
    }
}

void setup()
{
    // Relays
    for (int i = 1; i <= NUM_CHANNELS; ++i)
    {
        if (RELAY_PINS[i] >= 0)
        {
            pinMode(RELAY_PINS[i], OUTPUT);
            digitalWrite(RELAY_PINS[i], RELAY_OFF());
        }
    }

    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    while (WiFi.status() != WL_CONNECTED)
        delay(300);

    client.setServer(MQTT_HOST, MQTT_PORT);
    WiFi.setSleep(false); // disable Wi-Fi modem sleep to reduce dropouts
    client.setKeepAlive(60);
    client.setSocketTimeout(5);
    client.setBufferSize(1024);
    client.setCallback(mqttCallback);
}

unsigned long lastTele = 0;

void loop()
{
    if (!client.connected())
        ensureMqtt();
    client.loop();

    if (millis() - lastTele > 30000)
    {
        JsonDocument hb;
        hb["device"] = DEVICE_ID;
        hb["online"] = true;
        char buf[128];
        size_t n = serializeJson(hb, buf, sizeof(buf));
        client.publish(topicTele().c_str(), (uint8_t *)buf, n, false); // not retained
        lastTele = millis();
    }
}
