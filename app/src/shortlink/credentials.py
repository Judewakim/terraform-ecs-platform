"""Database credentials read from Secrets Manager at connection time.

RDS rotates the managed password automatically (every 7 days by default). A
password injected once at container start goes stale after a rotation, so the
app fetches the secret itself, caches it briefly, and refetches when a login
fails.
"""

from __future__ import annotations

import json
import threading
import time
from dataclasses import dataclass


@dataclass(frozen=True)
class DbCredentials:
    username: str
    password: str


class SecretsManagerCredentials:
    def __init__(self, secret_arn: str, ttl_seconds: int = 300, client=None) -> None:
        if client is None:
            import boto3

            client = boto3.client("secretsmanager")
        self._client = client
        self._secret_arn = secret_arn
        self._ttl = ttl_seconds
        self._lock = threading.Lock()
        self._cached: DbCredentials | None = None
        self._fetched_at = 0.0

    def get(self) -> DbCredentials:
        with self._lock:
            if self._cached is None or time.monotonic() - self._fetched_at > self._ttl:
                self._refresh_locked()
            return self._cached

    def invalidate(self) -> None:
        with self._lock:
            self._cached = None

    def _refresh_locked(self) -> None:
        value = self._client.get_secret_value(SecretId=self._secret_arn)["SecretString"]
        data = json.loads(value)
        self._cached = DbCredentials(username=data["username"], password=data["password"])
        self._fetched_at = time.monotonic()
