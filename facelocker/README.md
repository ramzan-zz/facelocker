# FaceLocker – quick start


## 1) Infra (MQTT + backend)
cd infra
cp ../.env.example ../.env
# edit .env if needed
docker compose up -d --build
# Backend: http://localhost:8000/docs


## 2) Seed data (optional)
Use Swagger at /docs to POST some Users, Lockers, Assignments, or open a Python shell and insert into SQLite.


## 3) ESP32 controller
- Open `esp_controller` in PlatformIO
- Edit `include/config.h` with your Wi‑Fi + MQTT
- Wire one solenoid + relay to, say, channel 0 (GPIO 13 as provided)
- Build & upload; open serial monitor; ensure MQTT connects


## 4) Tablet app (Flutter)
- Open `mobile_tablet`
- Update backend base URL and MQTT host IP (use LAN IP of your PC/server)
- `flutter pub get`
- Run on Android tablet
- Press **Scan & Unlock** (stub recognizer returns fake user `U_0001`)


## 5) Admin web
- Open `admin_web`
- `flutter run -d chrome`


## Next steps
- Replace recognizer stub with TFLite ArcFace model
- Add proper auth & RBAC to backend
- Enable TLS on Mosquitto and use client certs