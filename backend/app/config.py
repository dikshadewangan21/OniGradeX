from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

REPO_ROOT = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+psycopg://onigrader:onigrader@localhost:5432/onigrader"
    # Required secrets: no defaults on purpose. Startup fails loudly if unset.
    jwt_secret: str
    certificate_signing_key: str
    jwt_expire_minutes: int = 720

    upload_dir: str = str(REPO_ROOT / "backend" / "uploads")
    max_upload_bytes: int = 8 * 1024 * 1024
    allowed_image_types: str = "image/jpeg,image/png"

    model_metadata_path: str = str(REPO_ROOT / "ml" / "artifacts" / "model_metadata.json")
    model_file_path: str = str(REPO_ROOT / "ml" / "artifacts" / "onion_model.tflite")

    # e-NAM: no public documented key-free API is assumed. Configure yours.
    enam_api_url: str = ""
    enam_api_key: str = ""
    enam_cache_hours: int = 24

    # Anomaly rules (admin-tunable via env; thresholds are policy, not model output)
    flag_min_batches: int = 5
    flag_grade_a_share: float = 0.8
    flag_grade_a_max_defective_pct: float = 20.0
    weight_mismatch_tolerance_pct: float = 15.0

    rate_limit: str = "60/minute"
    rate_limit_login: str = "5/minute"
    rate_limit_sync: str = "30/minute"
    cors_origins: str = ""


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
