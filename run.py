import os

import uvicorn
from dotenv import load_dotenv

load_dotenv(".env.local")

if __name__ == "__main__":
    host = os.getenv("API_HOST", "0.0.0.0")
    port = int(os.getenv("API_PORT", "8000"))
    debug = os.getenv("DEBUG", "true").lower() == "true"
    
    uvicorn.run(
        "src.api.main:app",
        host=host,
        port=port,
        reload=debug
    )