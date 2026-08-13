#!/bin/sh
set -eu

repo="${QWEN_HF_REPO:-Qwen/Qwen3.5-9B}"
revision="${QWEN_REVISION:-main}"
destination="${QWEN_LOCAL_PATH:-/models/qwen3.5-9b}"
marker="$destination/.ragflow-hf-revision"

if [ -f "$marker" ] && [ "$(cat "$marker")" = "$repo@$revision" ] && [ -f "$destination/config.json" ]; then
  echo "Model already present: $repo@$revision"
  exit 0
fi

mkdir -p "$destination"
if [ -n "${HF_TOKEN:-}" ]; then
  hf download "$repo" --revision "$revision" --local-dir "$destination" --token "$HF_TOKEN"
else
  hf download "$repo" --revision "$revision" --local-dir "$destination"
fi
printf '%s\n' "$repo@$revision" > "$marker"
