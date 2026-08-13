FROM python:3.11-slim

ARG PADDLE_DEVICE_PACKAGE=paddlepaddle==3.2.2
RUN apt-get update && apt-get install -y --no-install-recommends curl libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir "${PADDLE_DEVICE_PACKAGE}" "paddleocr[doc-parser]==3.3.2" fastapi==0.116.1 uvicorn==0.35.0 python-multipart==0.0.20

WORKDIR /app
COPY app.py /app/app.py
EXPOSE 8080
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
