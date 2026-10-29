import json

from shortlink.credentials import SecretsManagerCredentials


class FakeSecretsManager:
    def __init__(self):
        self.password = "first"
        self.calls = 0

    def get_secret_value(self, SecretId):
        self.calls += 1
        return {"SecretString": json.dumps({"username": "app", "password": self.password})}


def test_caches_within_ttl():
    sm = FakeSecretsManager()
    creds = SecretsManagerCredentials("arn:test", ttl_seconds=300, client=sm)
    creds.get()
    creds.get()
    assert sm.calls == 1


def test_invalidate_refetches_rotated_password():
    sm = FakeSecretsManager()
    creds = SecretsManagerCredentials("arn:test", ttl_seconds=300, client=sm)
    assert creds.get().password == "first"
    sm.password = "rotated"
    creds.invalidate()
    assert creds.get().password == "rotated"


def test_expired_ttl_refetches():
    sm = FakeSecretsManager()
    creds = SecretsManagerCredentials("arn:test", ttl_seconds=0, client=sm)
    creds.get()
    creds.get()
    assert sm.calls == 2
