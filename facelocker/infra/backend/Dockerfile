# infra/backend/Dockerfile
FROM python:3.11-slim

WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# System deps: compiler toolchain + OpenCV runtime libs
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc g++ cmake \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
    && rm -rf /var/lib/apt/lists/*

# (optional, helps with some builds)
# RUN pip install --no-cache-dir "cython<3"

COPY infra/backend/requirements.txt /app/requirements.txt
RUN python -m pip install --upgrade pip && \
    pip install --no-cache-dir -r /app/requirements.txt

# Make sure faces dir exists (extra safety)
RUN mkdir -p /app/data/faces

COPY backend /app/backend

CMD ["uvicorn", "backend.app.main:app", "--host", "0.0.0.0", "--port", "8000"]
