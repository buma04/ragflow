#!/bin/sh
set -eu

threshold_mib=${QWEN_MIN_FREE_VRAM_MIB:-18432}
command -v nvidia-smi >/dev/null || { echo "ERROR: nvidia-smi is unavailable in vLLM container" >&2; exit 1; }
gpu_count=$(nvidia-smi --query-gpu=index --format=csv,noheader | wc -l)
[ "$gpu_count" -eq 2 ] || {
  echo "ERROR: vLLM must see exactly two GPUs (physical 0 and 1); saw $gpu_count. GPU 2 will not be substituted." >&2
  exit 1
}
for index in 0 1; do
  free=$(nvidia-smi --query-gpu=index,memory.free --format=csv,noheader,nounits | awk -F, -v target="$index" '$1+0 == target {gsub(/ /,"",$2); print $2}')
  [ -n "$free" ] && [ "$free" -ge "$threshold_mib" ] || {
    echo "ERROR: vLLM-visible GPU $index has ${free:-unknown} MiB free; need $threshold_mib MiB. Stop other processes or lower memory utilization/context/sequence count; GPU 2 will not be used." >&2
    exit 1
  }
done

set -- serve "${QWEN_LOCAL_PATH:-/models/qwen3.5-9b}" \
  --served-model-name "${QWEN_SERVED_NAME:-qwen3.5-9b}" \
  --api-key "${QWEN_API_KEY:-local-demo-key}" \
  --tensor-parallel-size "${VLLM_TENSOR_PARALLEL_SIZE:-2}" \
  --dtype "${VLLM_DTYPE:-bfloat16}" \
  --gpu-memory-utilization "${VLLM_GPU_MEMORY_UTILIZATION:-0.75}" \
  --max-model-len "${VLLM_MAX_MODEL_LEN:-16384}" \
  --max-num-seqs "${VLLM_MAX_NUM_SEQS:-4}" \
  --host 0.0.0.0 --port 8000

[ "${VLLM_LANGUAGE_MODEL_ONLY:-true}" = true ] && set -- "$@" --language-model-only
[ "${VLLM_ENFORCE_EAGER:-true}" = true ] && set -- "$@" --enforce-eager
exec vllm "$@"
