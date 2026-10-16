import time
from collections import defaultdict
from threading import Lock
from fastapi import HTTPException

# In-memory sliding-window log rate limiter with thread safety
_timestamps: dict[str, list[float]] = defaultdict(list)
_lock = Lock()


def _parse_limit(limit_str: str) -> tuple[int, float]:
    """Parse a limit string like '5/minute', '30/minute', '10/second' into (count, window_seconds)."""
    parts = limit_str.strip().split("/")
    count = int(parts[0])
    unit = parts[1].lower() if len(parts) > 1 else "minute"
    if unit in ("s", "sec", "second", "seconds"):
        window = 1.0
    elif unit in ("m", "min", "minute", "minutes"):
        window = 60.0
    elif unit in ("h", "hr", "hour", "hours"):
        window = 3600.0
    elif unit in ("d", "day", "days"):
        window = 86400.0
    else:
        window = 60.0
    return count, window


def check_rate_limit(key: str, limit_str: str, resource_name: str = "request") -> None:
    """Check if the key exceeds the rate limit. Raises HTTP 429 if exceeded."""
    count, window = _parse_limit(limit_str)
    now = time.time()
    cutoff = now - window

    with _lock:
        bucket = _timestamps[key]
        # Prune timestamps older than cutoff
        _timestamps[key] = [t for t in bucket if t > cutoff]
        if len(_timestamps[key]) >= count:
            oldest = _timestamps[key][0]
            retry_after = max(1, int(window - (now - oldest)))
            raise HTTPException(
                status_code=429,
                detail=f"Rate limit exceeded for {resource_name}. Please retry after {retry_after} seconds.",
                headers={"Retry-After": str(retry_after)},
            )
        _timestamps[key].append(now)


def reset_rate_limits() -> None:
    """Clear all rate limit records (used in test suites)."""
    with _lock:
        _timestamps.clear()
