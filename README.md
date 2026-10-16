# OniGrader (SIH26031)

Offline-first onion grading for procurement: Flutter app (on-device TFLite) + FastAPI/PostgreSQL backend.
**Honest status:** no dataset, no trained model, no accuracy claims. See "What is verified" below.

## Layout
`app/` Flutter · `backend/` FastAPI + Alembic · `ml/` contracts, validators, templates · `tests/` · `docs/REQUIREMENTS.md` (PPT feature map)

## Architecture
- **Inference is on-device** (PPT: offline, low-end phones). The backend re-applies the admin's grading rule to submitted metrics and rejects certificates whose grade doesn't follow from their own numbers. It cannot prove the device model produced those numbers; it records model version and image SHA-256 so a re-inspection can re-run the image.
- **Certificates:** device builds canonical JSON, SHA-256 (`device_hash`), saves to SQLite; on sync the server verifies hash, fields, model version and rule, then HMAC-signs. `GET /api/v1/verify/{id}` (public, used by the QR) re-checks hash, signature and DB columns. *Tamper-evident after sync, not tamper-proof before it.*
- **Roles:** admin (rules, users, mandis, disputes, analytics), officer (grade, sync), farmer (own certificates by phone, disputes). Self-signup is farmer-only.
- Grading thresholds, e-NAM prices, mandis come from DB/config. No rules published = officers cannot grade. No model installed = app and backend say so.

## Run the backend
```bash
cp .env.example .env     # fill JWT_SECRET, CERTIFICATE_SIGNING_KEY (openssl rand -hex 32), POSTGRES_PASSWORD
docker compose up --build
docker compose exec -e ADMIN_PASSWORD=... api python -m app.cli create-admin --phone +91XXXXXXXXXX --name "Admin"
```
Without Docker: `pip install -r backend/requirements.txt`, set env vars, `cd backend && alembic upgrade head && uvicorn app.main:app`.
Interactive API docs at `/docs`. Put HTTPS (reverse proxy) in front of any real deployment.

First-time admin steps: add mandi -> create officer -> publish grading rule (thresholds are your policy to enter).

## Build the app
Needs Flutter >= 3.22 and the Android SDK (not reachable where this was written).
```bash
cd app && flutter create . --platforms=android   # generates android/ scaffolding (not included)
# AndroidManifest.xml: add CAMERA, ACCESS_FINE_LOCATION, INTERNET permissions
flutter pub get && flutter test
flutter run --dart-define=API_BASE_URL=https://your-server
flutter build apk --debug --dart-define=API_BASE_URL=https://your-server
```
tflite_flutter/geolocator may need `minSdkVersion 26`; keep `.tflite` uncompressed (`aaptOptions { noCompress 'tflite' }`).

## Your manual work
Follow `ml/README.md`: dataset -> train -> evaluate -> export -> validate -> install -> publish rules -> device test.

## Tests
```bash
pip install -r backend/requirements.txt pyyaml
pytest tests/backend tests/ml                                      # SQLite
TEST_DATABASE_URL=postgresql+psycopg://... pytest tests/backend    # PostgreSQL
cd app && flutter test                                             # Dart logic + parity with ml vectors
```

## What is verified (this build)
| Verified by execution | Not verified |
|---|---|
| 32 API tests on SQLite and on PostgreSQL 16; 17 ML-tooling tests | Flutter app: **never compiled or run** (no SDK reachable); expect compile errors to fix |
| Alembic up/down/up on PostgreSQL | APK: **not built** |
| Live uvicorn smoke test (health, auth, model-unavailable, no-rules) | `detector.dart` against a real TFLite model |
| | Docker image build; e-NAM integration (needs your endpoint; adapter in `routers/system.py`); Dart tests |

## Not implemented (needs your data or decisions)
Grad-CAM heatmap (app draws detection boxes), pixel-to-mm diameter, MiDaS weight estimate, shelf-life model, area-based rot %, Hindi localisation, push notifications, re-inspection scheduling beyond dispute status, per-user rate limits (per-IP only), rule editor is raw JSON.
