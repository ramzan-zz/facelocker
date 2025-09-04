#pragma once

// WiFi
#define WIFI_SSID "Zayan"
#define WIFI_PASS "Zayan123"

// MQTT
#define MQTT_HOST "192.168.70.243" // or your broker IP/domain
#define MQTT_PORT 1883
#define MQTT_USERNAME ""
#define MQTT_PASSWORD ""

// Site/Topics
#define SITE_ID "site-001"
#define TOPIC_CMD "sites/" SITE_ID "/locker/cmd"
#define TOPIC_TELE "sites/" SITE_ID "/locker/tele"
// #define TOPIC_DOOR "sites/" SITE_ID "/locker/door"

// Lockers
#define LOCKER_COUNT 16

// GPIO mapping (adjust to your board)
static const int LOCK_PINS[LOCKER_COUNT] = {
    14, 27, 26, 25, 33, 32, 15, 4, 16,
    17, 5, 18, 19, 21, 22, 23};

// static const int DOOR_PINS[LOCKER_COUNT] = {
//     34, 35, 36, 39, 2, 0, 4, 15, 5, 18,
//     19, 21, 22, 23, 25, 26, 27, 32, 33, 14};

// Unlock pulse
#define DEFAULT_UNLOCK_MS 1200