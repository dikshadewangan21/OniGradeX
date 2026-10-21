import logging

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from slowapi.util import get_remote_address

from .config import get_settings
from .routers import analytics, auth, certificates, disputes, rules, system

log = logging.getLogger("onigrader")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")


def create_app() -> FastAPI:
    s = get_settings()
    app = FastAPI(title="OniGrader API", version="1.0.0")
    limiter = Limiter(key_func=get_remote_address, default_limits=[s.rate_limit])
    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
    app.add_middleware(SlowAPIMiddleware)
    origins = [o.strip() for o in s.cors_origins.split(",") if o.strip()] if s.cors_origins else ["*"]
    app.add_middleware(CORSMiddleware, allow_origins=origins,
                       allow_methods=["*"], allow_headers=["*"])

    from starlette.exceptions import HTTPException as StarletteHTTPException

    @app.exception_handler(Exception)
    async def unhandled(request: Request, exc: Exception):
        if isinstance(exc, (HTTPException, StarletteHTTPException)):
            return JSONResponse({"detail": exc.detail}, status_code=exc.status_code, headers=getattr(exc, "headers", None))
        log.exception("Unhandled error on %s %s", request.method, request.url.path)
        return JSONResponse({"detail": "Internal server error"}, status_code=500)

    for r in (system.router, auth.router, rules.router, certificates.router, disputes.router, analytics.router):
        app.include_router(r)
    return app


app = create_app()
