from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator


class WeatherRequest(BaseModel):
    city: str = Field(..., min_length=1, max_length=100, description="City name")

    @field_validator('city')
    @classmethod
    def validate_city(cls, v: str) -> str:
        if not v.strip():
            raise ValueError('City name cannot be empty')
        if any(char.isdigit() for char in v):
            raise ValueError('City name cannot contain numbers')
        return v.strip().title()

class WeatherResponse(BaseModel):
    city: str
    temperature: float
    description: str
    humidity: Optional[int] = None
    feels_like: Optional[float] = None
    created_at: datetime

class ErrorResponse(BaseModel):
    error: str
    detail: Optional[str] = None
    timestamp: datetime