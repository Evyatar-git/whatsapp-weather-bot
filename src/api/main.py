from fastapi import FastAPI, Form, Response, Depends, HTTPException, Request
from contextlib import asynccontextmanager
from datetime import datetime
from src.config.logging import setup_logging
from src.config.settings import settings
from src.database import get_db, init_database, test_database_connection
from src.models.schemas import WeatherRequest, WeatherResponse
from src.services.weather import WeatherService
from sqlalchemy.orm import Session
import logging
from twilio.twiml.messaging_response import MessagingResponse
from twilio.request_validator import RequestValidator
import html
from prometheus_fastapi_instrumentator import Instrumentator
from prometheus_client import Counter, Histogram
from collections import defaultdict
from typing import Dict, Any
import time

# Setup logging
logger = setup_logging()

@asynccontextmanager
async def lifespan(app: FastAPI) -> Any:
    """Application lifespan handler for startup and shutdown events."""
    try:
        logger.info("Initializing database on startup...")
        init_database()
        logger.info("Database initialized successfully")
    except Exception as e:
        logger.error(f"Failed to initialize database on startup: {e}", exc_info=True)
        logger.warning("Application will continue to start, but database operations may fail. Health check will report database status.")
    
    yield
    
    logger.info("Application shutting down...")

app = FastAPI(title="WhatsApp Weather Bot", version="1.0.0", lifespan=lifespan)

# Prometheus instrumentation
instrumentator = Instrumentator(
    should_group_status_codes=False,
    should_ignore_untemplated=True,
    should_respect_env_var=True,
    should_instrument_requests_inprogress=True,
    excluded_handlers=["/metrics"],
    env_var_name="ENABLE_METRICS",
)
instrumentator.instrument(app).expose(app)

# Custom business metrics
weather_requests_total = Counter(
    'weather_requests_total', 
    'Total weather requests', 
    ['city', 'status']
)

whatsapp_messages_total = Counter(
    'whatsapp_messages_total', 
    'Total WhatsApp messages processed', 
    ['message_type']
)

webhook_rate_limited_total = Counter(
    'webhook_rate_limited_total',
    'Total webhook requests rate-limited',
    ['sender']
)

database_operations_duration = Histogram(
    'database_operations_duration_seconds',
    'Database operation duration',
    ['operation']
)

account_sid = settings.twilio_account_sid
auth_token = settings.twilio_auth_token
from_number = settings.twilio_whatsapp_from

twilio_client = None
weather_service = WeatherService()

if account_sid and auth_token:
    from twilio.rest import Client
    try:
        twilio_client = Client(account_sid, auth_token)
        logger.info("Twilio client initialized successfully")
    except Exception as e:
        logger.error(f"Failed to initialize Twilio client: {str(e)}")
else:
    logger.warning("Twilio credentials not found, running in test mode")

RATE_LIMIT_WINDOW_SECONDS = 60
RATE_LIMIT_MAX_REQUESTS = 5
_request_times: Dict[str, list[float]] = defaultdict(list)

def is_rate_limited(sender: str) -> bool:
    now = time.time()
    window_start = now - RATE_LIMIT_WINDOW_SECONDS
    times = _request_times[sender]

    while times and times[0] < window_start:
        times.pop(0)

    if len(times) >= RATE_LIMIT_MAX_REQUESTS:
        return True

    times.append(now)
    return False

def send_message(to_number: str, message: str):
    logger.info(f"Sending message to {to_number}, length: {len(message)}")
    
    if not twilio_client:
        logger.info(f"Test mode: message not sent to {to_number}")
        return "test_mode"
    
    if not to_number.startswith("whatsapp:"):
        to_number = f"whatsapp:{to_number}"
    
    try:
        msg = twilio_client.messages.create(
            from_=from_number,
            body=message,
            to=to_number
        )
        logger.info("Message sent successfully", 
                   to_number=to_number, 
                   message_sid=msg.sid)
        return msg.sid
    except Exception as e:
        logger.error("Failed to send message", 
                    to_number=to_number, 
                    error=str(e))
        return None

def get_message_response(message_text: str, db: Session | None = None) -> tuple[str, str]:
    """
    Process a message and return the response text and message type.
    Returns: (response_text, message_type)
    """
    message = message_text.strip().lower()
    
    if message in ["hello", "hi", "start"]:
        response = """WhatsApp Weather Bot

Commands:
- Send city name for weather (e.g., 'London' or 'New York')
- 'help' for commands
- 'ping' to test

Example: London"""
        message_type = 'greeting'
        
    elif message in ["help", "?"]:
        response = """Available commands:
- Send city name for weather
- 'ping' - test bot
- 'help' - show commands

Supported: Any city worldwide"""
        message_type = 'help'
        
    elif message == "ping":
        response = "Weather bot is working!"
        message_type = 'ping'
        
    else:
        # Treat any other message as a city name
        try:
            # Validate city name using Pydantic
            weather_request = WeatherRequest(city=message_text.strip())
            
            if db:
                result = weather_service.get_current_weather(
                    city=weather_request.city, 
                    db=db
                )
                
                if result["status"] == "success":
                    response = weather_service.format_weather_message(result)
                    message_type = 'weather_success'
                    logger.info(f"Weather data retrieved for {result['data']['city']}")
                else:
                    response = f"""Weather Error

Could not fetch weather for: {weather_request.city}
Error: {result.get('error', 'Unknown error')}

Try a different city name."""
                    message_type = 'weather_error'
            else:
                # No database available, return error
                response = "Database not available. Please try again later."
                message_type = 'database_error'
                
        except ValueError as e:
            response = f"""Invalid Input

Error: {str(e)}

Please send a valid city name (letters only)."""
            message_type = 'invalid_input'
            logger.warning(f"Invalid city name: {str(e)}")
        except Exception as e:
            response = "Sorry, an error occurred. Please try again later."
            message_type = 'error'
            logger.error(f"Weather request error: {str(e)}")
    
    return response, message_type

def handle_message(phone_number: str, message_text: str, db: Session):
    """Legacy function for backward compatibility."""
    logger.info("Handling message", 
               phone_number=phone_number, 
               message_length=len(message_text))
    
    response, message_type = get_message_response(message_text, db)
    
    # Send immediate response for weather requests
    if message_type in ['weather_success', 'weather_error']:
        send_message(f"whatsapp:{phone_number}", "Fetching weather data... Please wait.")
    
    logger.info(f"Response prepared for {phone_number}, length: {len(response)}")
    return response

@app.get("/")
async def root():
    logger.info("Root endpoint accessed")
    return {"message": "WhatsApp Weather Bot", "status": "running"}

@app.get("/health")
async def health():
    logger.info("Health check requested")
    
    try:
        database_connected = test_database_connection()
        
        health_status = {
            "status": "healthy" if database_connected else "unhealthy",
            "twilio_configured": bool(twilio_client),
            "credentials_present": bool(account_sid and auth_token),
            "database_connected": database_connected,
            "timestamp": datetime.now().isoformat()
        }
        
        logger.info("Health check completed successfully")
        return health_status
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return {
            "status": "error",
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }

@app.post("/weather", response_model=WeatherResponse)
async def get_weather(request: WeatherRequest, db: Session = Depends(get_db)):
    logger.info(f"Weather API requested for city: {request.city}")
    
    try:
        with database_operations_duration.labels(operation='weather_lookup').time():
            result = weather_service.get_current_weather(city=request.city, db=db)
        
        if result["status"] == "success":
            data = result["data"]
            
            # Record successful weather request
            weather_requests_total.labels(city=request.city, status='success').inc()
            
            # Weather data is already stored by weather_service.get_current_weather()
            response = WeatherResponse(
                city=data["city"],
                temperature=data["temperature"],
                description=data["description"],
                humidity=data.get("humidity"),
                feels_like=data.get("feels_like"),
                created_at=datetime.now()  # Use current timestamp since data was just fetched
            )
            
            logger.info(f"Weather API completed successfully for {request.city}")
            return response
        else:
            # Record failed weather request
            weather_requests_total.labels(city=request.city, status='error').inc()
            logger.error(f"Weather API failed for {request.city}: {result.get('error')}")
            raise HTTPException(
                status_code=400,
                detail=f"Weather data not found for {request.city}: {result.get('error', 'Unknown error')}"
            )
            
    except Exception as e:
        # Record failed weather request
        weather_requests_total.labels(city=request.city, status='exception').inc()
        logger.error(f"Weather API error for {request.city}: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")

@app.post("/webhook")
async def webhook(request: Request, From: str = Form(...), Body: str = Form(...)):
    logger.info(f"Webhook received from {From}, body length: {len(Body)}")
    try:
        # Rate limiting per sender
        if is_rate_limited(From):
            webhook_rate_limited_total.labels(sender=From).inc()
            logger.warning(f"Rate limit exceeded for sender {From}")
            return Response(status_code=429, content="Too many requests, please try again later.")

        # Validate Twilio signature when credentials are configured
        if auth_token:
            try:
                signature = request.headers.get("X-Twilio-Signature", "")
                form_data = dict((await request.form()).items())
                url = str(request.url)
                validator = RequestValidator(auth_token)
                if not validator.validate(url, form_data, signature):
                    logger.warning("Twilio signature validation failed")
                    return Response(status_code=403, content="Forbidden")
            except Exception as e:
                logger.exception(f"Signature validation error: {e}")
                return Response(status_code=403, content="Forbidden")

        message_text = Body.strip()
        
        # Use consolidated message handler
        db = next(get_db())
        try:
            reply_text, message_type = get_message_response(message_text, db)
            
            # Update metrics based on message type
            whatsapp_messages_total.labels(message_type=message_type).inc()
            
            # Update weather-specific metrics
            if message_type == 'weather_success':
                weather_requests_total.labels(city=message_text.strip(), status='success').inc()
            elif message_type == 'weather_error':
                weather_requests_total.labels(city=message_text.strip(), status='error').inc()
                
        finally:
            db.close()

        # Build TwiML safely via Twilio helper to avoid XML issues
        safe_text = html.escape(reply_text)
        resp = MessagingResponse()
        resp.message(safe_text)

        logger.info(f"Webhook processed and replying with TwiML, reply_length={len(safe_text)}")
        return Response(content=str(resp), media_type="application/xml", status_code=200)

    except Exception as e:
        logger.exception(f"Webhook error: {str(e)}")
        return Response(status_code=500, content="Internal Server Error")

if __name__ == "__main__":
    import uvicorn
    
    logger.info("Starting server", 
               host=settings.api_host, 
               port=settings.api_port, 
               debug=settings.debug)
    uvicorn.run("src.api.main:app", 
               host=settings.api_host, 
               port=settings.api_port, 
               reload=settings.debug)