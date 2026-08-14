#!/usr/bin/env bash
set -euo pipefail

compose=(docker -H unix:///run/docker-ragflow.sock compose -f docker/docker-compose.yml)
api_key=${QWEN_API_KEY:-local-demo-key}
model=${QWEN_SERVED_NAME:-qwen3.5-9b}

"${compose[@]}" exec -T vllm-qwen curl -fsS http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $api_key" -H 'Content-Type: application/json' \
  -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with OK\"}],\"max_tokens\":8}" \
  | grep -q '"content"'

"${compose[@]}" exec -T ragflow-cpu curl -fsS http://embedding:80/embed \
  -H 'Content-Type: application/json' \
  -d '{"inputs":"Viettel nghiên cứu và phát triển nền tảng trí tuệ nhân tạo"}' \
  | grep -Eq '\[[[:space:]]*\['

"${compose[@]}" exec -T ragflow-cpu curl -fsS http://paddleocr:8080/health \
  | grep -q '"status":"ok"'

echo "Direct Qwen, embedding, and PaddleOCR service checks passed."
echo "Full ingest/query validation requires an authenticated RAGFlow API token and a document chosen for OCR."
