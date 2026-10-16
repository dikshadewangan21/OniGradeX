# OniGrader Security & Integrity Model

This document outlines the security architecture, threat model, and honest limitations of OniGrader (SIH26031).

---

## 1. Threat Model & Assumptions

OniGrader operates in agricultural wholesale mandis across India, where connectivity is intermittent and physical devices may be operating offline for hours before syncing.

### Actors
- **Farmers**: Can register accounts, view certificates issued for their mobile phone number, dispute grades, and receive dispute resolution notifications.
- **Procurement Officers**: Capture batch photos at mandis, run on-device TFLite inference, issue certificates offline, and sync them when connectivity is restored.
- **Central Admins**: Manage mandis, create officer accounts, update versioned grading rules, review disputes, assign re-inspections, and audit flagged anomalies.

---

## 2. Cryptographic Integrity & Offline Guarantees

### Canonical Payload & Device Hashing
1. When an officer issues a certificate on the mobile device, all core inspection metrics (count, fresh %, defective %, grade, geo-coordinates, timestamp, rule version, model version, image SHA-256) are serialized into **recursively sorted-key canonical JSON** (`canonical_payload`).
2. The device computes `device_hash = SHA256(canonical_payload)`.
3. The certificate and image are persisted to the device's local SQLite database.

### Real Limitation: Rooted Devices Prior to Sync
> [!WARNING]
> On a rooted Android device, **before the certificate is synced**, a root user with SQLite editor access could modify stored local rows and recompute the device SHA-256 hash.
> 
> Therefore, **the device hash is tamper-evident against unintended data corruption and post-sync tampering, but cannot offer hardware-level tamper resistance without hardware keystore attestation.**

### Server HMAC Signature & Non-Repudiation
1. Upon reconnection, the mobile device syncs the certificate via `POST /api/v1/certificates/sync`.
2. The server independently verifies:
   - `SHA256(canonical_payload) == device_hash`.
   - Every single field in `canonical_payload` matches the submitted JSON schema.
   - `grade` strictly follows from the recorded `rule_version` thresholds (`evaluate_grade`).
   - `model_version` matches the server's registered model version.
   - `batch_confidence >= rule.min_confidence`.
3. If valid, the server signs the record using HMAC-SHA256:
   $$\text{server\_signature} = \text{HMAC-SHA256}(K_{\text{signing}}, \text{cert\_id} \parallel \text{officer\_id} \parallel \text{canonical\_payload})$$
4. Only server-signed certificates are valid on the public verification portal (`GET /api/v1/verify/{id}`).

---

## 3. Server-Side Model Proof Limitation

> [!IMPORTANT]
> The server **cannot prove that the on-device TFLite model produced the inspection numbers** versus a modified client binary.

### Mitigations:
1. **Immutable Image Hash**: The certificate binds the SHA-256 hash of the raw batch photograph (`image_sha256`).
2. **Audit & Re-Inspection**: If a farmer disputes a certificate, the admin assigns an independent re-inspection, and the server can re-run inference on the uploaded image using the registered model version.
3. **Statistical Anomaly Detection**: The backend flags officers whose Grade A proportions statistically deviate from mandi averages (`GET /api/v1/analytics/flags`).

---

## 4. Rate Limiting & DoS Protection

- **Login**: Rate limited per phone number (default 5 attempts/minute) with HTTP 429 and `Retry-After` headers to prevent credential brute-forcing.
- **Certificate Sync**: Rate limited per authenticated officer (default 30 syncs/minute) to prevent sync queue flooding.
- **Max Image Size**: 8 MB limit on batch image uploads with MIME type enforcement (`image/jpeg`, `image/png`).

---

## 5. Offline Sync & Idempotency

- Certificates are indexed by client-generated UUIDv4.
- `POST /api/v1/certificates/sync` is strictly idempotent: retrying after network timeout returns the existing signed record without duplicate creation.
