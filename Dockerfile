# Multi-stage build for better security and smaller image
FROM python:3.11-slim AS builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Production stage
FROM python:3.11-slim

# Create non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Install runtime OS packages (curl for healthcheck)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy Python packages from builder stage
COPY --from=builder /root/.local /home/appuser/.local

# Copy application code
COPY src/ ./src/
COPY run.py .

# Create database directory and ensure proper permissions
RUN mkdir -p /app/data && \
    chown -R appuser:appuser /app && \
    chmod 755 /app/data

# Switch to non-root user
USER appuser

# Add user's local bin to PATH
ENV PATH=/home/appuser/.local/bin:$PATH
# Ensure Python can locate packages installed into the user site directory
ENV PYTHONPATH=/home/appuser/.local/lib/python3.11/site-packages:/app

EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -fsS http://localhost:8000/health || exit 1

CMD ["python", "run.py"]