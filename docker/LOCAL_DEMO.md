# Local Qwen/BGE/PaddleOCR demo

The default allocation is vLLM 0.26.0 on physical GPUs 0 and 1 (TP=2), with
both TEI BGE-M3 and PP-StructureV3 on physical GPU 2. TEI and PaddleOCR are
separate containers intentionally sharing GPU 2; GPU assignment is visibility,
not exclusive ownership. The vLLM reservation lists only devices 0 and 1, so it
cannot see GPU 2.

The PaddleOCR GPU image installs PaddlePaddle 3.2.2 from Paddle's pinned CUDA
11.8 wheel index. CUDA 11.8 is selected for compatibility with the deployment
host's NVIDIA 535 driver; Paddle GPU 3.x is not installed from the default PyPI
index.

The setup installs and starts a dedicated `docker-ragflow.service`. Its socket
is `/run/docker-ragflow.sock`, while its images, writable layers, containers,
and volumes live under `/u01/docker-ragflow`. It does not reconfigure or restart
the default Docker daemon. A matching `containerd-ragflow.service` uses
`/run/containerd-ragflow/containerd.sock` and `/u01/containerd-ragflow`, so it
does not connect to the system containerd or mix containerd/shim versions. The
dedicated daemon also uses a separate socket, PID, exec root, data root, address
pool, and a dedicated `docker-ragflow0` bridge on `10.230.0.0/24`. It does not
reuse the default daemon's `docker0`. Docker documents multiple daemons on one
host as experimental.

The resource preflight checks the dedicated daemon, NVIDIA runtime, three
visible GPUs, 18 GiB free on GPUs 0 and 1, and at least 40 GiB free under
`/u01/docker-ragflow`. It also verifies that the daemon reports that exact
Docker data root. On subsequent idempotent runs, an already-running RAGFlow
vLLM container owns the expected GPU 0/1 allocation, so the free-VRAM startup
gate is skipped without stopping or restarting that container.

Start the complete project with:

```bash
./scripts/setup-local-demo.sh
```

This single entrypoint fast-forwards `origin/main`, installs or updates the
dedicated systemd service, runs the resource preflight, selects the default
`aux-gpu` profile, validates Compose, and builds/starts the stack. Run it as
root, or as a sudo-capable user. The equivalent manual Compose command is:

```bash
docker -H unix:///run/docker-ragflow.sock compose \
  -f docker/docker-compose.yml up -d --build
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

The demo publishes RAGFlow on a dedicated host-port range so it does not claim
the existing services' ports:

- Web HTTP: `http://HOST:8989`
- Web HTTPS: `https://HOST:18443`
- HTTP API: `http://HOST:19380`
- Admin API: `http://HOST:19381`
- MCP: `http://HOST:19382`
- Go admin/API: ports `19383` and `19384`

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

Existing GPU processes are left untouched. If vLLM needs a smaller allocation,
lower memory utilization to 0.70, context to 8192, and sequence count to 2, in
that order. Do not change TP to 3 and do not silently use GPU 2.

After the stack is healthy, `scripts/smoke-test-demo.sh` performs direct service
checks. Its RAGFlow integration stage is intentionally not fabricated: an
authenticated API token and a user-owned dataset are required.

All lifecycle commands must target the dedicated socket explicitly:

```bash
docker -H unix:///run/docker-ragflow.sock compose -f docker/docker-compose.yml ps
docker -H unix:///run/docker-ragflow.sock compose -f docker/docker-compose.yml logs -f
docker -H unix:///run/docker-ragflow.sock compose -f docker/docker-compose.yml down
```

`aux-gpu` is the default and enables `tei-gpu` plus `paddleocr-gpu`; both
services independently request physical GPU 2. The remaining modes preserve
CPU fallbacks when their combined VRAM demand is too high.

The vLLM pin is deliberate: Qwen3.5 support is present in the current vLLM
model implementation, while older vLLM images predate this architecture. The
deployment host still needs an NVIDIA driver compatible with the CUDA runtime
in that image. PP-StructureV3 can exceed 16 GiB on GPU with all submodels
enabled, so the shared default may require switching one or both auxiliary
services to CPU on a memory-constrained deployment.
