"""Integration test against a real Postgres (CI runs one as a service).

Skipped unless PG_ADMIN_DSN is set. Proves the app keeps working after the
database password rotates while its cached copy is stale.
"""

import json
import os

import pytest

ADMIN_DSN = os.getenv("PG_ADMIN_DSN")
pytestmark = pytest.mark.skipif(not ADMIN_DSN, reason="PG_ADMIN_DSN not set")


class FakeSecretsManager:
    def __init__(self, password):
        self.password = password

    def get_secret_value(self, SecretId):
        return {"SecretString": json.dumps({"username": "rotation_test", "password": self.password})}


@pytest.fixture
def admin():
    import psycopg

    with psycopg.connect(ADMIN_DSN, autocommit=True) as conn:
        conn.execute("DROP DATABASE IF EXISTS rotation_test")
        conn.execute("DROP ROLE IF EXISTS rotation_test")
        conn.execute("CREATE ROLE rotation_test LOGIN PASSWORD 'pw1'")
        conn.execute("CREATE DATABASE rotation_test OWNER rotation_test")
        yield conn


def test_survives_password_rotation(admin):
    from psycopg.conninfo import conninfo_to_dict, make_conninfo
    from psycopg_pool import ConnectionPool

    from shortlink.credentials import SecretsManagerCredentials
    from shortlink.store import PostgresStore

    parts = conninfo_to_dict(ADMIN_DSN)
    conninfo = make_conninfo(host=parts.get("host", "localhost"), port=parts.get("port", "5432"), dbname="rotation_test", sslmode="disable")

    sm = FakeSecretsManager("pw1")
    creds = SecretsManagerCredentials("arn:test", ttl_seconds=3600, client=sm)
    store = PostgresStore(conninfo, creds, min_size=1, max_size=2)
    store.create("abc1234", "https://example.com")

    # Rotate: the database and the secret change, the app's cache does not.
    admin.execute("ALTER ROLE rotation_test PASSWORD 'pw2'")
    sm.password = "pw2"

    # New connections, as the pool's max_lifetime recycling would open.
    cls = store._pool.connection_class
    store._pool.close()
    store._pool = ConnectionPool(conninfo, connection_class=cls, min_size=1, max_size=2, open=True)
    try:
        assert store.ping()
        assert store.resolve("abc1234") == "https://example.com"
    finally:
        store._pool.close()
