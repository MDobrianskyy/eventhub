# Stage 1: build dependencies
FROM python:3.13-slim AS builder

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt gunicorn


# Stage 2: production image
FROM python:3.13-slim

# Create non-root user
RUN addgroup --system appgroup && adduser --system --ingroup appgroup --home /home/appuser appuser

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application code and fix permissions
COPY app.py .
RUN chown -R appuser:appgroup /app

# Drop privileges
USER appuser

EXPOSE 5050

CMD ["gunicorn", "--bind", "0.0.0.0:5052", "--workers", "2", "--threads", "4", "app:app"]
