import json
from pathlib import Path

import jsonschema

from ..config import get_settings

SCHEMA_PATH = Path(__file__).resolve().parents[3] / "ml" / "contract" / "model_metadata.schema.json"


def read_status() -> dict:
    """Reports what is actually installed. Never invents a version or accuracy."""
    s = get_settings()
    meta_path, model_path = Path(s.model_metadata_path), Path(s.model_file_path)
    status = {
        "metadata_present": meta_path.is_file(),
        "model_file_present": model_path.is_file(),
        "ready": False,
        "version": None,
        "problems": [],
        "metadata": None,
    }
    if not status["metadata_present"]:
        status["problems"].append("model_metadata.json not found")
    if not status["model_file_present"]:
        status["problems"].append("model file not found")
    if status["metadata_present"]:
        try:
            meta = json.loads(meta_path.read_text())
            schema = json.loads(SCHEMA_PATH.read_text())
            errors = sorted(jsonschema.Draft202012Validator(schema).iter_errors(meta), key=lambda e: list(e.path))
            if errors:
                status["problems"].extend(
                    f"metadata invalid at {'/'.join(map(str, e.path)) or '<root>'}: {e.message}" for e in errors[:10])
            else:
                status["version"] = str(meta["version"])
                status["metadata"] = meta
        except json.JSONDecodeError:
            status["problems"].append("model_metadata.json is not valid JSON")
    status["ready"] = not status["problems"]
    return status


def registered_version() -> str | None:
    st = read_status()
    return st["version"] if st["ready"] else None
