# Test Fixtures (TEST FIXTURE ONLY)

> **WARNING:** The files in this directory are purely **TEST FIXTURES**. They do not contain or represent a real machine learning model, weights, or training data. They are never bundled into release builds (`app/assets/model/` is the production asset path).

## Purpose
Phase 3 integration testing tests the entire plumbing round-trip:
1. `summarize()` post-processing of detection outputs
2. `evaluateGrade()` against admin-published rules
3. `buildCertificate()` canonical payload creation and SHA-256 device hashing
4. `POST /api/v1/certificates/sync` to the test backend
5. `GET /api/v1/verify/{id}` public certificate verification

This proves that all data contracts, canonical serializations, hashing, signing, and verification logic work end-to-end without requiring a real trained ML model.
