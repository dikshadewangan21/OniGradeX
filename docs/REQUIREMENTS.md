# OniGrader – Requirements Checklist (from SIH26031 PPT)

Status legend: DONE = implemented and tested here; CODE = implemented, cannot be executed in this sandbox; BLOCKED-ML = needs your trained model/dataset; EXT = needs external credential/service.

| # | PPT requirement | Where | Status |
|---|-----------------|-------|--------|
| 1 | Three roles: Central Admin, Procurement Officer, Farmer | backend `auth`, Flutter role routing | DONE (backend) / CODE (app) |
| 2 | Batch photo capture, instant grading | Flutter `capture`, `ml/` contract, on-device TFLite | BLOCKED-ML |
| 3 | Per-onion detection of rot / sprout / skin-peel / undersized | model contract `ml/contract/model_metadata.schema.json` | BLOCKED-ML |
| 4 | Grade A / URS / Rejected mapping (NAFED standards) | admin-managed versioned `grading_rules` (no thresholds hardcoded) | DONE (backend) / CODE (app) |
| 5 | % fresh / % defective, payout scales with % fresh | `payout` computed from result + rate | DONE |
| 6 | Grad-CAM heatmap as visual proof | model must export heatmap output; app renders only if present | BLOCKED-ML |
| 7 | Diameter via pixel-to-mm | needs calibration reference; part of model/pipeline contract | BLOCKED-ML |
| 8 | Weight-fraud check (MiDaS volume vs scale) | backend flags when both supplied; volume comes from model | DONE (flag logic) / BLOCKED-ML (volume) |
| 9 | Shelf-life estimate | backend stores value only if model artifact provides it | BLOCKED-ML |
| 10 | Live e-NAM price, 24h cache fallback | `/prices/enam`, needs endpoint + key in env | EXT |
| 11 | Tamper-proof certificate (SHA-256, QR, PDF) | device hash + server HMAC signature + public verify endpoint | DONE (backend) / CODE (app) |
| 12 | Offline-first, SQLite on device, sync when online | Flutter drift/sqflite + sync queue; `/certificates/sync` idempotent | DONE (backend) / CODE (app) |
| 13 | Officer anomaly alerts (repeated Grade A on bad loads) | `/analytics/flags` rule-based, thresholds in env | DONE |
| 14 | Farmer views own certificates, raises dispute by cert ID | `/disputes` | DONE |
| 15 | Admin dispute queue → re-inspection | `/disputes/{id}/resolve` | DONE |
| 16 | Admin analytics: mandis, stock health, trends | `/analytics/*` aggregates from DB | DONE |
| 17 | Admin updates grading rules centrally w/o app rebuild | `/rules`, app fetches on sync | DONE |
| 18 | Geo-tagged, timestamped certificates | lat/lon/captured_at required | DONE |
| 19 | Low-confidence grades prompt re-capture | `min_confidence` in active rule | DONE |

## Things in the PPT that I am NOT claiming
- "<1 s on a ₹6,000 phone", "50+ onions per frame", "3 s batch grading": performance claims; only measurable once your model exists.
- "Tamper-proof" on a purely offline device is only tamper-*evident* once the record syncs and the server signs it. Until sync, a rooted device could alter the record and recompute the hash.
- The server cannot prove the on-device model actually produced the submitted numbers. It records model version + image SHA-256 so a re-inspection can re-run the image.
- The rule-based pipeline mentioned under "Project Status" was not provided, so it is not included.

## Manual work for you (see `ml/README.md`)
Dataset, labeling, training, export of the TFLite model plus `model_metadata.json`, grading thresholds entered by an admin via `/rules`.
