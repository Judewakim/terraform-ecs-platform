"""Storage backends for short links.

The service talks to a `LinkStore`. Production uses `PostgresStore`; tests use
`MemoryStore`, so the API can be tested without a database.
"""

from __future__ import annotations

import threading
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Protocol


@dataclass(frozen=True)
class Link:
    code: str
    url: str
    created_at: datetime
    hits: int


class CodeTaken(Exception):
    """Raised when a generated code collides with an existing one."""


class LinkStore(Protocol):
    def create(self, code: str, url: str) -> Link: ...
    def get(self, code: str) -> Link | None: ...
    def resolve(self, code: str) -> str | None: ...
    def ping(self) -> bool: ...


class MemoryStore:
    """In-process store for tests and local runs without Postgres."""

    def __init__(self) -> None:
        self._links: dict[str, Link] = {}
        self._lock = threading.Lock()

    def create(self, code: str, url: str) -> Link:
        with self._lock:
            if code in self._links:
                raise CodeTaken(code)
            link = Link(code, url, datetime.now(timezone.utc), 0)
            self._links[code] = link
            return link

    def get(self, code: str) -> Link | None:
        return self._links.get(code)

    def resolve(self, code: str) -> str | None:
        with self._lock:
            link = self._links.get(code)
            if link is None:
                return None
            self._links[code] = Link(link.code, link.url, link.created_at, link.hits + 1)
            return link.url

    def ping(self) -> bool:
        return True


SCHEMA = """
CREATE TABLE IF NOT EXISTS links (
    code        VARCHAR(16) PRIMARY KEY,
    url         TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    hits        BIGINT      NOT NULL DEFAULT 0
);
"""


class PostgresStore:
    """Postgres-backed store. Uses a small connection pool per task.

    `credentials` supplies the username and password for every new connection,
    so a rotated password is picked up without restarting the task.
    """

    def __init__(self, conninfo: str, credentials, min_size: int = 1, max_size: int = 5) -> None:
        # Imported here so tests don't need the driver installed.
        import psycopg
        from psycopg_pool import ConnectionPool

        class RotatingConnection(psycopg.Connection):
            @classmethod
            def connect(cls, conninfo: str = "", **kwargs):
                creds = credentials.get()
                try:
                    return super().connect(conninfo, user=creds.username, password=creds.password, **kwargs)
                except psycopg.OperationalError as exc:
                    if "password authentication failed" not in str(exc):
                        raise
                    # Password rotated since we cached it: refetch once and retry.
                    credentials.invalidate()
                    creds = credentials.get()
                    return super().connect(conninfo, user=creds.username, password=creds.password, **kwargs)

        self._pool = ConnectionPool(
            conninfo,
            connection_class=RotatingConnection,
            min_size=min_size,
            max_size=max_size,
            max_lifetime=900,  # recycle connections every 15 minutes
            open=True,
        )
        with self._pool.connection() as conn:
            conn.execute(SCHEMA)

    def create(self, code: str, url: str) -> Link:
        from psycopg.errors import UniqueViolation

        try:
            with self._pool.connection() as conn:
                row = conn.execute(
                    "INSERT INTO links (code, url) VALUES (%s, %s) RETURNING code, url, created_at, hits",
                    (code, url),
                ).fetchone()
        except UniqueViolation as exc:
            raise CodeTaken(code) from exc
        return Link(*row)

    def get(self, code: str) -> Link | None:
        with self._pool.connection() as conn:
            row = conn.execute(
                "SELECT code, url, created_at, hits FROM links WHERE code = %s", (code,)
            ).fetchone()
        return Link(*row) if row else None

    def resolve(self, code: str) -> str | None:
        with self._pool.connection() as conn:
            row = conn.execute(
                "UPDATE links SET hits = hits + 1 WHERE code = %s RETURNING url", (code,)
            ).fetchone()
        return row[0] if row else None

    def ping(self) -> bool:
        try:
            with self._pool.connection(timeout=2) as conn:
                conn.execute("SELECT 1")
            return True
        except Exception:
            return False
