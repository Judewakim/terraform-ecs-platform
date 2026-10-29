"""Shortlink API: a deliberately small service. The infrastructure is the point."""

from __future__ import annotations

import json
import logging
import os
import re
import secrets
import string
import sys
import time
import uuid
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, RedirectResponse
from pydantic import BaseModel, Field, HttpUrl

from .store import CodeTaken, LinkStore, MemoryStore

ALPHABET = string.ascii_letters + string.digits
CODE_LEN = 7
CODE_RE = re.compile(r"^[A-Za-z0-9]{4,16}$")
MAX_URL_LEN = 2048


class JsonFormatter(logging.Formatter):
    """One JSON object per line, so CloudWatch Logs Insights can query fields."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {"level": record.levelname, "msg": record.getMessage(), "logger": record.name}
        payload.update(getattr(record, "fields", {}))
        return json.dumps(payload)


handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
log = logging.getLogger("shortlink")
log.handlers = [handler]
log.setLevel(os.getenv("LOG_LEVEL", "INFO"))
log.propagate = False


def build_store() -> LinkStore:
    if os.getenv("STORE", "postgres") == "memory":
        return MemoryStore()

    from psycopg.conninfo import make_conninfo

    from .credentials import SecretsManagerCredentials
    from .store import PostgresStore

    # No user or password here: each new connection reads them from Secrets Manager.
    conninfo = make_conninfo(
        host=os.environ["DB_HOST"],
        port=os.getenv("DB_PORT", "5432"),
        dbname=os.environ["DB_NAME"],
        sslmode=os.getenv("DB_SSLMODE", "require"),
        connect_timeout=5,
    )
    return PostgresStore(conninfo, SecretsManagerCredentials(os.environ["DB_SECRET_ARN"]))


def new_code() -> str:
    return "".join(secrets.choice(ALPHABET) for _ in range(CODE_LEN))


class CreateLink(BaseModel):
    url: HttpUrl = Field(description="http or https URL to shorten")


def create_app(store: LinkStore | None = None) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.store = store or build_store()
        log.info("startup", extra={"fields": {"version": os.getenv("APP_VERSION", "dev")}})
        yield

    app = FastAPI(title="Shortlink", lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)

    @app.middleware("http")
    async def access_log(request: Request, call_next):
        request_id = (request.headers.get("x-request-id") or str(uuid.uuid4()))[:64]
        start = time.perf_counter()
        try:
            response = await call_next(request)
        except Exception:
            log.exception("unhandled", extra={"fields": {"request_id": request_id}})
            response = JSONResponse({"detail": "internal error"}, status_code=500)
        response.headers["x-request-id"] = request_id
        if request.url.path not in ("/health",):
            log.info(
                "request",
                extra={
                    "fields": {
                        "request_id": request_id,
                        "method": request.method,
                        "path": request.url.path,
                        "status": response.status_code,
                        "latency_ms": round((time.perf_counter() - start) * 1000, 1),
                    }
                },
            )
        return response

    @app.get("/health")
    def health():
        """Liveness: the process is up. Never touches the database."""
        return {"status": "ok"}

    @app.get("/ready")
    def ready(request: Request):
        """Readiness: the database answers. The ALB health check uses this."""
        if not request.app.state.store.ping():
            raise HTTPException(status_code=503, detail="database unavailable")
        return {"status": "ready", "version": os.getenv("APP_VERSION", "dev")}

    @app.post("/links", status_code=201)
    def create_link(body: CreateLink, request: Request):
        url = str(body.url)
        if len(url) > MAX_URL_LEN:
            raise HTTPException(status_code=422, detail="url too long")
        for _ in range(5):
            try:
                link = request.app.state.store.create(new_code(), url)
                break
            except CodeTaken:
                continue
        else:
            raise HTTPException(status_code=503, detail="could not allocate a code")
        return {"code": link.code, "url": link.url, "short": f"/{link.code}"}

    @app.get("/links/{code}")
    def link_stats(code: str, request: Request):
        if not CODE_RE.match(code):
            raise HTTPException(status_code=404)
        link = request.app.state.store.get(code)
        if link is None:
            raise HTTPException(status_code=404)
        return {"code": link.code, "url": link.url, "hits": link.hits, "created_at": link.created_at.isoformat()}

    @app.get("/{code}")
    def follow(code: str, request: Request):
        if not CODE_RE.match(code):
            raise HTTPException(status_code=404)
        url = request.app.state.store.resolve(code)
        if url is None:
            raise HTTPException(status_code=404)
        return RedirectResponse(url, status_code=302)

    return app


app = create_app()
