import os
import sys

import pytest

sys.path.append(os.path.dirname(os.path.dirname(__file__)))

from datetime import datetime

from src.models.schemas import ErrorResponse, WeatherRequest, WeatherResponse


def test_weather_request_validation():
    # Valid request
    valid_request = WeatherRequest(city="London")
    assert valid_request.city == "London"
    
    # Test city validation
    with pytest.raises(ValueError):
        WeatherRequest(city="")
    
    with pytest.raises(ValueError):
        WeatherRequest(city="123")
    
    # Test city formatting
    formatted_request = WeatherRequest(city="  london  ")
    assert formatted_request.city == "London"

def test_weather_response():
    response = WeatherResponse(
        city="London",
        temperature=22.5,
        description="Sunny",
        created_at=datetime.now()
    )
    assert response.city == "London"
    assert response.temperature == 22.5

def test_error_response():
    error = ErrorResponse(
        error="Validation Error",
        detail="City name is required",
        timestamp=datetime.now()
    )
    assert error.error == "Validation Error"
    assert error.detail == "City name is required"
