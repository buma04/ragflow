#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)

cd "$repo_root"

git pull --ff-only origin main
./scripts/check-demo-resources.sh
./scripts/set-demo-aux-mode.sh aux-gpu
docker compose -f docker/docker-compose.yml config --quiet
docker compose -f docker/docker-compose.yml up -d --build

echo "Local RAGFlow demo startup requested successfully."
echo "Run: docker compose -f docker/docker-compose.yml ps"
