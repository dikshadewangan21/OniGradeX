"""TEST FIXTURE BACKEND SERVER
Runs FastAPI backend configured exclusively with TEST FIXTURES.
Used for Phase 3 plumbing integration testing (NOT A REAL MODEL).
"""
import argparse
import os
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

# Configure test fixture environment variables
os.environ["DATABASE_URL"] = f"sqlite:///{ROOT / 'backend' / 'plumbing_fixture.db'}"
os.environ["MODEL_METADATA_PATH"] = str(ROOT / "app" / "test" / "fixtures" / "model_metadata.json")
os.environ["MODEL_FILE_PATH"] = str(ROOT / "app" / "test" / "fixtures" / "onion_model.tflite")
os.environ["JWT_SECRET"] = "test-fixture-jwt-secret-key-12345"
os.environ["CERTIFICATE_SIGNING_KEY"] = "test-fixture-cert-signing-key-12345"
os.environ["UPLOAD_DIR"] = str(ROOT / "backend" / "plumbing_uploads")

from app import config, db, models
from app.security import hash_password

config.get_settings.cache_clear()
db.reset_engine()
db.Base.metadata.drop_all(db.get_engine())
db.Base.metadata.create_all(db.get_engine())

s = next(db.get_db())
# Create test officer
officer_id = str(uuid.uuid4())
officer = models.User(
    id=officer_id,
    phone="9000000003",
    name="Test Officer (Fixture)",
    password_hash=hash_password("officerpassword123"),
    role=models.Role.officer,
    is_active=True,
)
s.add(officer)
s.flush()

# Create active grading rule
rule = models.GradingRule(
    version=1,
    is_active=True,
    created_by=officer_id,
    definition={
        "min_confidence": 0.5,
        "reject_grade": "Rejected",
        "grades": [
            {"grade": "A", "max_defective_pct": 10},
            {"grade": "URS", "max_defective_pct": 30, "max_rot_pct": 5},
        ],
    },
)
s.add(rule)
s.commit()

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8009)
    args = parser.parse_args()

    import uvicorn
    from app.main import app
    print(f"Starting TEST FIXTURE server on port {args.port}...")
    uvicorn.run(app, host="127.0.0.1", port=args.port, log_level="warning")
