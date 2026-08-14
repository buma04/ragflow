#!/usr/bin/env bash
set -euo pipefail

threshold_mib=${QWEN_MIN_FREE_VRAM_MIB:-18432}
disk_min_gib=${DEMO_MIN_DISK_GIB:-40}
docker_socket=${RAGFLOW_DOCKER_SOCKET:-/run/docker-ragflow.sock}
docker_data_root=${RAGFLOW_DOCKER_DATA_ROOT:-/u01/docker-ragflow}
docker_cmd=(docker -H "unix://$docker_socket")

command -v docker >/dev/null || { echo "ERROR: Docker CLI not found" >&2; exit 1; }
"${docker_cmd[@]}" info >/dev/null 2>&1 || { echo "ERROR: dedicated RAGFlow Docker daemon unavailable at $docker_socket" >&2; exit 1; }
command -v nvidia-smi >/dev/null || { echo "ERROR: nvidia-smi not found" >&2; exit 1; }

mapfile -t gpu_rows < <(nvidia-smi --query-gpu=index,name,memory.total,memory.used,memory.free --format=csv,noheader,nounits)
((${#gpu_rows[@]} >= 3)) || { echo "ERROR: at least 3 GPUs required; found ${#gpu_rows[@]}" >&2; exit 1; }
printf '%s\n' "${gpu_rows[@]}"

vllm_containers=$("${docker_cmd[@]}" ps \
  --filter label=com.docker.compose.service=vllm-qwen \
  --filter status=running --quiet)
vllm_container=${vllm_containers%%$'\n'*}
if [[ -n "$vllm_container" ]]; then
  vllm_status=$("${docker_cmd[@]}" inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$vllm_container")
  echo "Existing RAGFlow vLLM container is running ($vllm_status); its expected GPU 0/1 allocation is preserved."
else
  for index in 0 1; do
    free=$(printf '%s\n' "${gpu_rows[@]}" | awk -F, -v target="$index" '$1+0 == target {gsub(/ /,"",$5); print $5}')
    [[ -n "$free" && "$free" -ge "$threshold_mib" ]] || {
      echo "ERROR: GPU $index has ${free:-unknown} MiB free; need $threshold_mib MiB before starting vLLM. Existing processes are not modified and GPU 2 will not be substituted." >&2
      exit 1
    }
  done
fi

"${docker_cmd[@]}" info --format '{{json .Runtimes}}' | grep -qi nvidia || { echo "ERROR: NVIDIA Container Toolkit runtime not detected in dedicated daemon" >&2; exit 1; }
[[ -d "$docker_data_root" ]] || { echo "ERROR: Docker data root missing: $docker_data_root" >&2; exit 1; }
free_kib=$(df -Pk "$docker_data_root" | awk 'NR==2 {print $4}')
((free_kib >= disk_min_gib * 1024 * 1024)) || { echo "ERROR: less than ${disk_min_gib} GiB free at $docker_data_root" >&2; exit 1; }
actual_root=$("${docker_cmd[@]}" info --format '{{.DockerRootDir}}')
[[ "$actual_root" == "$docker_data_root" ]] || { echo "ERROR: dedicated daemon uses $actual_root instead of $docker_data_root" >&2; exit 1; }
echo "Resource preflight passed. Existing GPU processes and the default Docker daemon were not modified."
