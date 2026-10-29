import pytest
from fastapi.testclient import TestClient

from shortlink.main import create_app
from shortlink.store import MemoryStore


class DownStore(MemoryStore):
    def ping(self) -> bool:
        return False


@pytest.fixture
def client():
    with TestClient(create_app(MemoryStore())) as c:
        yield c


def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


def test_ready(client):
    assert client.get("/ready").status_code == 200


def test_ready_fails_when_db_down():
    with TestClient(create_app(DownStore())) as c:
        assert c.get("/ready").status_code == 503
        # Liveness stays up so ECS doesn't kill tasks over a database outage.
        assert c.get("/health").status_code == 200


def test_create_follow_and_count(client):
    r = client.post("/links", json={"url": "https://example.com/page"})
    assert r.status_code == 201
    code = r.json()["code"]

    follow = client.get(f"/{code}", follow_redirects=False)
    assert follow.status_code == 302
    assert follow.headers["location"] == "https://example.com/page"

    assert client.get(f"/links/{code}").json()["hits"] == 1


@pytest.mark.parametrize("bad", ["javascript:alert(1)", "ftp://example.com", "not a url", ""])
def test_rejects_non_http_urls(client, bad):
    assert client.post("/links", json={"url": bad}).status_code == 422


def test_rejects_overlong_url(client):
    assert client.post("/links", json={"url": "https://e.com/" + "a" * 3000}).status_code == 422


@pytest.mark.parametrize("code", ["nope123", "../etc", "a" * 40])
def test_unknown_or_invalid_code_is_404(client, code):
    assert client.get(f"/{code}", follow_redirects=False).status_code == 404


def test_request_id_header(client):
    r = client.get("/ready", headers={"x-request-id": "abc"})
    assert r.headers["x-request-id"] == "abc"
