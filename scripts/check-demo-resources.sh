#!/usr/bin/env bash
set -euo pipefail

threshold_mib=${QWEN_MIN_FREE_VRAM_MIB:-18432}
disk_min_gib=${DEMO_MIN_DISK_GIB:-40}
model_root=${DEMO_MODEL_ROOT:-docker/models}

command -v docker >/dev/null || { echo "ERROR: Docker CLI not found" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "ERROR: Docker daemon unavailable" >&2; exit 1; }
command -v nvidia-smi >/dev/null || { echo "ERROR: nvidia-smi not found" >&2; exit 1; }

mapfile -t gpu_rows < <(nvidia-smi --query-gpu=index,name,memory.total,memory.used,memory.free --format=csv,noheader,nounits)
((${#gpu_rows[@]} >= 3)) || { echo "ERROR: at least 3 GPUs required; found ${#gpu_rows[@]}" >&2; exit 1; }
printf '%s\n' "${gpu_rows[@]}"

for index in 0 1; do
  free=$(printf '%s\n' "${gpu_rows[@]}" | awk -F, -v target="$index" '$1+0 == target {gsub(/ /,"",$5); print $5}')
  [[ -n "$free" && "$free" -ge "$threshold_mib" ]] || {
    echo "ERROR: GPU $index has ${free:-unknown} MiB free; need $threshold_mib MiB. Stop other GPU processes or lower the documented vLLM memory/context settings; GPU 2 will not be substituted." >&2
    exit 1
  }
done

docker info --format '{{json .Runtimes}}' | grep -qi nvidia || { echo "ERROR: NVIDIA Container Toolkit runtime not detected" >&2; exit 1; }
mkdir -p "$model_root"
free_kib=$(df -Pk "$model_root" | awk 'NR==2 {print $4}')
((free_kib >= disk_min_gib * 1024 * 1024)) || { echo "ERROR: less than ${disk_min_gib} GiB free at $model_root" >&2; exit 1; }
echo "Resource preflight passed. GPU 2 availability is auxiliary-only; select a CPU auxiliary mode if needed."
