# Local Qwen/BGE/PaddleOCR demo

The default allocation is vLLM 0.26.0 on physical GPUs 0 and 1 (TP=2), with
both TEI BGE-M3 and PP-StructureV3 on physical GPU 2. TEI and PaddleOCR are
separate containers intentionally sharing GPU 2; GPU assignment is visibility,
not exclusive ownership. The vLLM reservation lists only devices 0 and 1, so it
cannot see GPU 2.

Before deployment, run `scripts/check-demo-resources.sh` on the target Linux
host. It checks Docker, NVIDIA Container Toolkit, three visible GPUs, 18 GiB
free on GPUs 0 and 1, and 40 GiB disk space. This repository intentionally does
not run that check automatically because model download and deployment may be
managed separately.

Start the complete project with:

```bash
docker compose -f docker/docker-compose.yml up -d --build
```

The one-shot downloader stores `Qwen/Qwen3.5-9B` in the `qwen_models` volume.
It records the repository and revision only after `hf download` succeeds.
Compose starts vLLM only after that service exits successfully. TEI and Paddle
model caches use the `tei_data` and `paddle_models` volumes.
The downloader image is built locally from `python:3.13-slim-bookworm` and a
pinned `huggingface_hub`; it does not rely on a non-existent prebuilt Hub image.

Internal endpoints are:

- RAGFlow to vLLM: `http://vllm-qwen:8000/v1`
- RAGFlow to TEI: `http://embedding:80`
- RAGFlow to PaddleOCR: `http://paddleocr:8080`

`service_conf.yaml.template` supplies chat and embedding defaults for newly
created tenants. After RAGFlow becomes healthy, `local-model-bootstrap` uses
the repository's model-provider services to upsert VLLM and PaddleOCR for every
tenant and selects the local chat/embedding/OCR defaults. It is idempotent and
does not hardcode tenant IDs. This demo intentionally replaces existing tenant
defaults; do not use that bootstrap behavior in a shared deployment.

Auxiliary modes are mutually exclusive Compose profiles. Select one with:

```bash
scripts/set-demo-aux-mode.sh aux-gpu
scripts/set-demo-aux-mode.sh embedding-gpu
scripts/set-demo-aux-mode.sh ocr-gpu
scripts/set-demo-aux-mode.sh aux-cpu
```

Then run the same Compose command. Never enable both `tei-cpu`/`tei-gpu` or
both `paddleocr-cpu`/`paddleocr-gpu`: each pair shares a network alias and port.

If vLLM runs out of memory, first remove unrelated GPU processes, then lower
memory utilization to 0.70, context to 8192, and sequence count to 2, in that
order. Do not change TP to 3 and do not silently use GPU 2.

After the stack is healthy, `scripts/smoke-test-demo.sh` performs direct service
checks. Its RAGFlow integration stage is intentionally not fabricated: an
authenticated API token and a user-owned dataset are required.

`aux-gpu` is the default and enables `tei-gpu` plus `paddleocr-gpu`; both
services independently request physical GPU 2. The remaining modes preserve
CPU fallbacks when their combined VRAM demand is too high.

The vLLM pin is deliberate: Qwen3.5 support is present in the current vLLM
model implementation, while older vLLM images predate this architecture. The
deployment host still needs an NVIDIA driver compatible with the CUDA runtime
in that image. PP-StructureV3 can exceed 16 GiB on GPU with all submodels
enabled, so the shared default may require switching one or both auxiliary
services to CPU on a memory-constrained deployment.
