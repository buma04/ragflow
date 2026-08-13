#!/usr/bin/env bash
set -euo pipefail

mode=${1:-}
env_file=${2:-docker/.env}
case "$mode" in
  aux-gpu)       profiles='${DOC_ENGINE},${DEVICE},tei-gpu,paddleocr-gpu' ;;
  embedding-gpu) profiles='${DOC_ENGINE},${DEVICE},tei-gpu,paddleocr-cpu' ;;
  ocr-gpu)       profiles='${DOC_ENGINE},${DEVICE},tei-cpu,paddleocr-gpu' ;;
  aux-cpu)       profiles='${DOC_ENGINE},${DEVICE},tei-cpu,paddleocr-cpu' ;;
  *) echo "Usage: $0 {aux-gpu|embedding-gpu|ocr-gpu|aux-cpu} [docker/.env]" >&2; exit 2 ;;
esac
sed -i -E "s|^COMPOSE_PROFILES=.*|COMPOSE_PROFILES=$profiles|; s|^AUX_MODE=.*|AUX_MODE=$mode|" "$env_file"
echo "Selected $mode in $env_file"
