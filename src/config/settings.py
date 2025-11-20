import os
import logging
from typing import Optional

logger = logging.getLogger(__name__)

class Settings:
    def __init__(self):
        self.api_host = os.getenv("API_HOST", "0.0.0.0")
        self.api_port = int(os.getenv("API_PORT", "8000"))
        self.debug = os.getenv("DEBUG", "false").lower() == "true"
        self.log_level = os.getenv("LOG_LEVEL", "INFO")
        
        self.database_url = self._get_database_url()
        self._load_secrets()
        
    def _get_database_url(self):
        """Get database URL from environment or Parameter Store."""
        db_url = os.getenv("DATABASE_URL")
        if db_url:
            return db_url
        
        if os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION"):
            try:
                import boto3
                region = os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION", "us-east-1")
                ssm = boto3.client('ssm', region_name=region)
                
                try:
                    params = ssm.get_parameters(
                        Names=[
                            "/weather-bot/database/host",
                            "/weather-bot/database/port",
                            "/weather-bot/database/name",
                            "/weather-bot/database/username",
                            "/weather-bot/database/password"
                        ],
                        WithDecryption=True
                    )
                    
                    if len(params['Parameters']) == 5:
                        db_config = {p['Name'].split('/')[-1]: p['Value'] for p in params['Parameters']}
                        
                        if all(k in db_config for k in ['host', 'port', 'name', 'username', 'password']):
                            logger.info("Using PostgreSQL database from Parameter Store")
                            # RDS requires SSL connections
                            return f"postgresql://{db_config['username']}:{db_config['password']}@{db_config['host']}:{db_config['port']}/{db_config['name']}?sslmode=require"
                except Exception as param_error:
                    logger.warning(f"Database parameters not found in Parameter Store: {param_error}")
                    pass
            except Exception as e:
                logger.warning(f"Parameter Store not available: {e}")
        
        return "sqlite:///./weather_bot.db"
    
    def _load_secrets(self):
        """Load secrets from environment variables or Parameter Store."""
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
                self.weather_api_key = os.getenv("WEATHER_API_KEY", "")
                self.twilio_account_sid = os.getenv("TWILIO_ACCOUNT_SID", "")
                self.twilio_auth_token = os.getenv("TWILIO_AUTH_TOKEN", "")
                self.twilio_whatsapp_from = os.getenv("TWILIO_WHATSAPP_FROM", "")
        else:
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
