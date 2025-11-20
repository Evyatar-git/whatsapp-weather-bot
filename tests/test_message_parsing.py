from datetime import datetime
from unittest.mock import Mock

from src.api import main as api_main
from src.api.main import get_message_response


def test_greeting_returns_menu(monkeypatch):
    fake_db = Mock()
    text, typ = get_message_response("hello", db=fake_db)
    assert "Commands" in text
    assert typ == "greeting"


def test_help_returns_help_text(monkeypatch):
    fake_db = Mock()
    text, typ = get_message_response("help", db=fake_db)
    assert "Available commands" in text
    assert typ == "help"


def test_ping_returns_ok(monkeypatch):
    fake_db = Mock()
    text, typ = get_message_response("ping", db=fake_db)
    assert "working" in text.lower()
    assert typ == "ping"


def test_invalid_city_is_rejected(monkeypatch):
    fake_db = Mock()
    text, typ = get_message_response("L0nd0n", db=fake_db)
    assert "Invalid Input" in text
    assert typ == "invalid_input"


def test_weather_success(monkeypatch):
    fake_db = Mock()

    def fake_weather_success(city: str, db):
        return {
            "status": "success",
            "data": {
                "city": "London",
                "temperature": 20.0,
                "description": "clear sky",
                "humidity": 60,
                "feels_like": 19.0,
                "timestamp": datetime.now(),
            },
        }

    monkeypatch.setattr(api_main.weather_service, "get_current_weather", fake_weather_success)

    text, typ = get_message_response("London", db=fake_db)
    assert "Weather Update for London" in text
    assert "Temperature" in text
    assert typ == "weather_success"


def test_weather_error(monkeypatch):
    fake_db = Mock()

    def fake_weather_error(city: str, db):
        return {"status": "error", "error": "not found"}

    monkeypatch.setattr(api_main.weather_service, "get_current_weather", fake_weather_error)

    text, typ = get_message_response("Atlantis", db=fake_db)
    assert "Weather Error" in text
    assert "not found" in text
    assert typ == "weather_error"

