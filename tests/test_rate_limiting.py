import time
from fastapi.testclient import TestClient

from src.api.main import app


client = TestClient(app)


def post_webhook(sender: str, body: str = "London"):
    return client.post(
        "/webhook",
        data={"From": sender, "Body": body},
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )


def test_rate_limiting_allows_first_5_blocks_6th(monkeypatch):
    # Ensure signature validation is off for this test
    monkeypatch.delenv("TWILIO_AUTH_TOKEN", raising=False)

    # Make the window short so the test runs fast
    from src.api import main as api_main
    monkeypatch.setattr(api_main, "RATE_LIMIT_WINDOW_SECONDS", 2)
    monkeypatch.setattr(api_main, "RATE_LIMIT_MAX_REQUESTS", 5)

    sender = "whatsapp:+10000000000"

    # First 5 requests succeed
    for _ in range(5):
        r = post_webhook(sender)
        assert r.status_code == 200

    # 6th is rate-limited
    r = post_webhook(sender)
    assert r.status_code == 429

    # After window elapses, it should succeed again
    time.sleep(2.2)
    r = post_webhook(sender)
    assert r.status_code == 200


def test_rate_limit_metric_increments(monkeypatch):
    # Ensure signature validation is off for this test
    monkeypatch.delenv("TWILIO_AUTH_TOKEN", raising=False)

    # Tight limit for faster test
    from src.api import main as api_main
    monkeypatch.setattr(api_main, "RATE_LIMIT_WINDOW_SECONDS", 2)
    monkeypatch.setattr(api_main, "RATE_LIMIT_MAX_REQUESTS", 1)

    sender = "whatsapp:+10000000001"

    # First allowed
    assert post_webhook(sender).status_code == 200
    # Second blocked
    assert post_webhook(sender).status_code == 429

    # Assert metric exposed if metrics endpoint is enabled
    metrics_resp = client.get("/metrics")
    if metrics_resp.status_code == 200:
        assert f'webhook_rate_limited_total{{sender="{sender}"}}' in metrics_resp.text

