from fastapi.testclient import TestClient

from src.api.main import app

client = TestClient(app)


def post_webhook(
    signature: str | None = None,
    sender: str = "whatsapp:+15555550123",
    body: str = "London"
):
    headers = {"Content-Type": "application/x-www-form-urlencoded"}
    if signature is not None:
        headers["X-Twilio-Signature"] = signature
    return client.post("/webhook", data={"From": sender, "Body": body}, headers=headers)


def test_webhook_signature_bypassed_when_token_unset(monkeypatch):
    # Ensure auth token not set → signature validation bypassed for local/dev
    monkeypatch.delenv("TWILIO_AUTH_TOKEN", raising=False)
    res = post_webhook(signature=None)
    assert res.status_code == 200


def test_webhook_signature_valid_when_token_set(monkeypatch):
    # Simulate presence of auth token
    monkeypatch.setenv("TWILIO_AUTH_TOKEN", "dummy-token")

    # Patch the validator to accept the request
    from src.api import main as api_main
    # Ensure runtime uses a non-empty token (module-level variable)
    monkeypatch.setattr(api_main, "auth_token", "dummy-token", raising=False)
    class DummyValidator:
        def __init__(self, *_args, **_kwargs):
            pass
        def validate(self, *_args, **_kwargs):
            return True

    monkeypatch.setattr(api_main, "RequestValidator", DummyValidator)

    res = post_webhook(signature="anything")
    assert res.status_code == 200


def test_webhook_signature_rejected_when_invalid(monkeypatch):
    # Simulate presence of auth token
    monkeypatch.setenv("TWILIO_AUTH_TOKEN", "dummy-token")

    # Patch the validator to reject the request
    from src.api import main as api_main
    # Ensure runtime uses a non-empty token (module-level variable)
    monkeypatch.setattr(api_main, "auth_token", "dummy-token", raising=False)
    class DummyValidator:
        def __init__(self, *_args, **_kwargs):
            pass
        def validate(self, *_args, **_kwargs):
            return False

    monkeypatch.setattr(api_main, "RequestValidator", DummyValidator)

    res = post_webhook(signature="bad-signature")
    assert res.status_code == 403

