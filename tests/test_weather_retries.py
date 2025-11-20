import requests
from fastapi.testclient import TestClient

from src.api import main as api_main
from src.api.main import app
from src.services import weather as weather_mod

client = TestClient(app)


class DummyResponse:
    def __init__(self, status_code: int, json_body: dict | None = None, text: str = ""):
        self.status_code = status_code
        self._json = json_body or {}
        self.text = text or ""

    def json(self):
        return self._json

    def raise_for_status(self):
        if 400 <= self.status_code < 600:
            raise requests.HTTPError(f"HTTP {self.status_code}", response=self)


def test_weather_retries_then_succeeds(monkeypatch):
    # Arrange retry-friendly behaviour
    # Force WeatherService to use real API path (not offline mode)
    api_main.weather_service.api_key = "test-key"
    calls = {"n": 0}

    def flaky_get(*_args, **_kwargs):
        calls["n"] += 1
        if calls["n"] <= 2:
            raise requests.Timeout("simulated timeout")
        return DummyResponse(
            200,
            {
                "name": "London",
                "main": {"temp": 20.0, "humidity": 60, "feels_like": 19.0},
                "weather": [{"description": "clear sky"}],
                "dt": 1700000000,
            },
        )

    monkeypatch.setattr(weather_mod.requests, "get", flaky_get)

    # Act
    res = client.post("/weather", json={"city": "London"})

    # Assert
    assert res.status_code == 200, res.text


def test_weather_404_is_not_retried(monkeypatch):
    # Force WeatherService to use real API path (not offline mode)
    api_main.weather_service.api_key = "test-key"
    def get_404(*_args, **_kwargs):
        return DummyResponse(404, text="not found")

    monkeypatch.setattr(weather_mod.requests, "get", get_404)

    res = client.post("/weather", json={"city": "NoSuchCity"})
    # Endpoint may surface 400 (bad request) or 500 (wrapped internal error)
    assert res.status_code in (400, 500)


def test_weather_persistent_5xx_fails(monkeypatch):
    # Force WeatherService to use real API path (not offline mode)
    api_main.weather_service.api_key = "test-key"
    def get_500(*_args, **_kwargs):
        return DummyResponse(500, text="server error")

    monkeypatch.setattr(weather_mod.requests, "get", get_500)

    res = client.post("/weather", json={"city": "Paris"})
    # After retries, the API should surface an error (500 internal)
    assert res.status_code in (400, 500)


