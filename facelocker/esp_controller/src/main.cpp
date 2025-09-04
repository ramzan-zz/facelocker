#include <Arduino.h>
mqtt.subscribe(TOPIC_CMD);
}
else
{
    delay(1000);
}
}
}

void setup()
{
    Serial.begin(115200);
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    while (WiFi.status() != WL_CONNECTED)
    {
        delay(300);
    }
    mqtt.setServer(MQTT_HOST, MQTT_PORT);
    mqtt.setCallback(handle_cmd);

    for (int i = 0; i < LOCKER_COUNT; i++)
    {
        pinMode(LOCK_PINS[i], OUTPUT);
        setOutput(i, false);
        pinMode(DOOR_PINS[i], INPUT_PULLUP); // adjust per sensor wiring
    }
}

void loop()
{
    if (!mqtt.connected())
        reconnect_mqtt();
    mqtt.loop();

    uint32_t now = millis();
    for (int i = 0; i < LOCKER_COUNT; i++)
    {
        if (channels[i].active && (int32_t)(now - channels[i].until_ms) >= 0)
        {
            channels[i].active = false;
            setOutput(i, false);
        }
    }

    // Periodic door state publish (optional, throttle)
    static uint32_t lastDoor = 0;
    if (now - lastDoor > 1000)
    {
        lastDoor = now;
        for (int i = 0; i < LOCKER_COUNT; i++)
        {
            const char *state = digitalRead(DOOR_PINS[i]) ? "open" : "closed"; // depends on wiring
            StaticJsonDocument<192> doc;
            doc["locker_id"] = i;
            doc["door_state"] = state;
            char buf[192];
            size_t n = serializeJson(doc, buf);
            mqtt.publish(TOPIC_DOOR, buf, n);
        }
    }
}