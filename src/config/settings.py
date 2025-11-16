import os
from typing import Optional

class Settings:
    def __init__(self):
        self.database_url = os.getenv("DATABASE_URL", "sqlite:///./weather_bot.db")
        self.api_host = os.getenv("API_HOST", "0.0.0.0")
        self.api_port = int(os.getenv("API_PORT", "8000"))
        self.debug = os.getenv("DEBUG", "false").lower() == "true"
        self.log_level = os.getenv("LOG_LEVEL", "INFO")
        
        # Try to get secrets from Parameter Store first (when running in AWS)
        self._load_secrets()
        
    def _load_secrets(self):
        """Load secrets from environment variables or Parameter Store."""
        # Check if we're running in AWS (EKS) by looking for AWS-specific environment variables
        if os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION"):
            try:
                from .parameter_store import parameter_store
                secrets = parameter_store.get_parameters([
                    "openweather-key",
                    "account-sid", 
                    "auth-token",
                    "whatsapp-from"
                ])
                
                self.weather_api_key = secrets.get("openweather-key") or os.getenv("WEATHER_API_KEY", "")
                self.twilio_account_sid = secrets.get("account-sid") or os.getenv("TWILIO_ACCOUNT_SID", "")
                self.twilio_auth_token = secrets.get("auth-token") or os.getenv("TWILIO_AUTH_TOKEN", "")
                self.twilio_whatsapp_from = secrets.get("whatsapp-from") or os.getenv("TWILIO_WHATSAPP_FROM", "")
            except Exception as e:
                # Fallback to environment variables if Parameter Store fails
                self.weather_api_key = os.getenv("WEATHER_API_KEY", "")
                self.twilio_account_sid = os.getenv("TWILIO_ACCOUNT_SID", "")
                self.twilio_auth_token = os.getenv("TWILIO_AUTH_TOKEN", "")
                self.twilio_whatsapp_from = os.getenv("TWILIO_WHATSAPP_FROM", "")
        else:
            # Running locally, use environment variables
            self.weather_api_key = os.getenv("WEATHER_API_KEY", "")
            self.twilio_account_sid = os.getenv("TWILIO_ACCOUNT_SID", "")
            self.twilio_auth_token = os.getenv("TWILIO_AUTH_TOKEN", "")
            self.twilio_whatsapp_from = os.getenv("TWILIO_WHATSAPP_FROM", "")
        
    def validate(self):
        """
        Validate non-fatal config invariants.
        Note: Offline mode is supported when WEATHER_API_KEY is missing, so we do not raise.
        Returns True if everything looks good; False if running in offline mode.
        """
        if not self.weather_api_key:
            # Deliberately allow offline mode; callers can decide how to proceed.
            return False
        return True

settings = Settings()
