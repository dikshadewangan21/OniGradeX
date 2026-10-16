# OniGrader – Requirements Checklist (from SIH26031 PPT & Implementation)

Status legend:
- **DONE**: Implemented and verified with passing unit/widget/integration tests in the workspace.
- **BLOCKED-ML**: Model-dependent interface implemented and verified with test fixtures; awaiting your trained model and dataset (Manual steps M1–M6).
- **EXT**: Needs external credential/service (e.g. e-NAM live API key, production HTTPS domain - Manual steps M8, M11).

| # | PPT / System requirement | Where | Status |
|---|--------------------------|-------|--------|
| 1 | Three roles: Central Admin, Procurement Officer, Farmer | backend `auth`, Flutter role routing | **DONE** (backend + app verified on emulator) |
| 2 | Batch photo capture, instant grading | Flutter `capture`, `ml/` contract, on-device TFLite | **BLOCKED-ML** (App blocks grading when model is missing) |
| 3 | Per-onion detection of rot / sprout / skin-peel / undersized | model contract `ml/contract/model_metadata.schema.json` | **BLOCKED-ML** (Schema validated, parser tested) |
| 4 | Grade A / B / C / Rejected mapping (NAFED standards) | admin-managed versioned `grading_rules` (no thresholds hardcoded) | **DONE** (Validated form editor + backend rules engine) |
| 5 | % fresh / % defective, payout scales with % fresh | `payout` computed from result + rate | **DONE** (Parity verified with Python) |
| 6 | Grad-CAM heatmap as visual proof | model must export `heatmap` output; app renders only if present; boxes only otherwise | **DONE** (Conditional rendering implemented in `CaptureScreen`) |
| 7 | Diameter via pixel-to-mm | reference object of known size (e.g. ₹5 coin, 25mm, configurable in admin rule); refused if reference missing | **DONE** (Implemented in `CaptureScreen`, stored in `details.median_diameter_mm`) |
| 8 | Weight-fraud check (MiDaS volume vs scale) | backend flags when both supplied; volume comes from model; admin density constant (0.96 g/cm³) | **DONE** (Backend flag logic + app weight mismatch computation) |
| 9 | Shelf-life estimate | backend stores value only if model artifact provides it | **DONE** (Strictly guarded by model metadata declaration) |
| 10 | Live e-NAM price, 24h cache fallback | `/prices/enam`, needs endpoint + key in env | **EXT** (Cached fallback operational) |
| 11 | Tamper-proof certificate (SHA-256, QR, PDF) | device hash + server HMAC signature + public verify endpoint | **DONE** (Plumbing integration test verified roundtrip) |
| 12 | Offline-first, SQLite on device, sync when online | Flutter sqflite + sync queue; `/certificates/sync` idempotent | **DONE** (Offline queueing + retry verified) |
| 13 | Officer anomaly alerts (repeated Grade A on bad loads) | `/analytics/flags` rule-based, thresholds in env | **DONE** |
| 14 | Farmer views own certificates, raises dispute by cert ID | `/disputes` | **DONE** |
| 15 | Admin dispute queue → re-inspection | `/disputes/{id}/assign`, `/disputes/assigned`, `/disputes/{id}/reinspect`, `/disputes/{id}/resolve` | **DONE** (Alembic migration 0002 + full workflow tests) |
| 16 | Admin analytics: mandis, stock health, trends | `/analytics/*` aggregates from DB | **DONE** |
| 17 | Admin updates grading rules centrally w/o app rebuild | `/rules`, validated form in `AdminHome` | **DONE** |
| 18 | Geo-tagged, timestamped certificates | lat/lon/captured_at required | **DONE** |
| 19 | Low-confidence grades prompt re-capture | `min_confidence` in active rule | **DONE** |
| 20 | Unified YOLO layout & on-device NMS | `Detector` supports separate and unified YOLOv5/v7/v8/v11 tensors | **DONE** (Tested in `detector_layout_test.dart`) |
| 21 | Model verification CLI runner | `tool/check_model_on_image.dart` | **DONE** (Tested with test fixtures) |
| 22 | On-device latency benchmark screen | `BenchmarkScreen` reports median latency over N runs in debug mode | **DONE** (Tested in `benchmark_screen_test.dart`) |
| 23 | Validated grading rule editor form | Replaces raw JSON editor in Admin UI with structured form | **DONE** (In `AdminHome`) |
| 24 | Per-user backend rate limits | 5 attempts/min on login, 30 syncs/min on sync | **DONE** (Tested in `test_phase5_features.py`) |
| 25 | In-app dispute notifications | Notification list for farmers and officers on dispute status change | **DONE** (Tested in `test_phase5_features.py`) |
| 26 | Multi-language localization (en, hi, mr) | Hindi + Marathi support via Flutter intl/ARB | **DONE** (`app_en.arb`, `app_hi.arb`, `app_mr.arb`) |

## Honest Limitations and Architectural Realities
- Performance numbers ("<1 s on a ₹6,000 phone", "50+ onions per frame"): Performance cannot be claimed until the real INT8 model is exported and measured on physical target devices.
- "Tamper-proof": On a purely offline device, certificates are tamper-*evident* once synced and server-signed with HMAC-SHA256. Until sync, a rooted device could modify local SQLite rows and recompute SHA-256 hashes.
- Server Verification: The server verifies cryptographic signatures, image hash, rule consistency, and officer authorization, but cannot prove what the camera sensor saw.
