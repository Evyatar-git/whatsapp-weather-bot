from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, text
from sqlalchemy.orm import DeclarativeBase, sessionmaker
from datetime import datetime, timezone
import logging
import os
from pathlib import Path
from src.config.settings import settings

logger = logging.getLogger(__name__)

class Base(DeclarativeBase):
    pass

def _prepare_sqlite_path(db_url: str) -> str:
    """Prepare SQLite database path for container compatibility."""
    if db_url.startswith("sqlite:///"):
        db_path = db_url.replace("sqlite:///", "")
        
        if not os.path.isabs(db_path):
            db_dir = Path(db_path).parent
            db_dir.mkdir(parents=True, exist_ok=True)
            logger.info(f"Created database directory: {db_dir}")
            
            db_path = os.path.abspath(db_path)
            db_url = f"sqlite:///{db_path}"
            logger.info(f"Using absolute database path: {db_path}")
    
    return db_url

raw_database_url = settings.database_url
if raw_database_url.startswith("sqlite:///"):
    DATABASE_URL = _prepare_sqlite_path(raw_database_url)
else:
    DATABASE_URL = raw_database_url

is_postgresql = DATABASE_URL.startswith("postgresql://") or DATABASE_URL.startswith("postgres://")

if is_postgresql:
    engine = create_engine(
        DATABASE_URL,
        pool_pre_ping=True,
        pool_size=5,
        max_overflow=10,
        pool_recycle=3600
    )
else:
    engine = create_engine(DATABASE_URL, pool_pre_ping=True)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

class WeatherData(Base):
    __tablename__ = "weather_data"
    
    id = Column(Integer, primary_key=True)
    city = Column(String(100), nullable=False)
    temperature = Column(Float, nullable=False)
    description = Column(String(200))
    humidity = Column(Integer)
    feels_like = Column(Float)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

def get_db():
    db = SessionLocal()
    try:
        yield db
    except Exception as e:
        logger.error(f"Database error: {e}")
        db.rollback()
        raise e
    finally:
        db.close()

def init_database():
    """Initialize database with proper error handling and migration support."""
    try:
        Base.metadata.create_all(bind=engine)
        
        with engine.connect() as conn:
            if is_postgresql:
                result = conn.execute(text("""
                    SELECT table_name 
                    FROM information_schema.tables 
                    WHERE table_schema = 'public'
                """))
            else:
                result = conn.execute(text("SELECT name FROM sqlite_master WHERE type='table'"))
            
            tables = result.fetchall()
            table_names = [t[0] for t in tables]
            logger.info(f"Database initialized successfully with tables: {table_names}")
        
    except Exception as e:
        logger.error(f"Failed to initialize database: {e}")
        raise e

def migrate_database():
    """Run database migrations if needed."""
    try:
        # For SQLite, we just recreate tables if schema changed
        # In production, you'd want more sophisticated migration handling
        init_database()
        logger.info("Database migration completed successfully")
    except Exception as e:
        logger.error(f"Database migration failed: {e}")
        raise e

def test_database_connection():
    try:
        with engine.connect() as conn:
            result = conn.execute(text("SELECT 1"))
            result.fetchone()
        logger.info("Database connection test successful")
        return True
    except Exception as e:
        logger.error(f"Database connection test failed: {e}")
        return False