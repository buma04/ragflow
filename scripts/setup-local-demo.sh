#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)

cd "$repo_root"

if [[ ${RAGFLOW_SETUP_AFTER_PULL:-0} != 1 ]]; then
  git pull --ff-only origin main
  exec env RAGFLOW_SETUP_AFTER_PULL=1 "$repo_root/scripts/setup-local-demo.sh" "$@"
fi
if ((EUID == 0)); then
  ./scripts/setup-ragflow-docker.sh
else
  sudo ./scripts/setup-ragflow-docker.sh
fi
./scripts/check-demo-resources.sh
./scripts/set-demo-aux-mode.sh aux-gpu
docker -H unix:///run/docker-ragflow.sock compose -f docker/docker-compose.yml config --quiet
docker -H unix:///run/docker-ragflow.sock compose -f docker/docker-compose.yml up -d --build

echo "Local RAGFlow demo startup requested successfully."
echo "Run: docker -H unix:///run/docker-ragflow.sock compose -f docker/docker-compose.yml ps"
