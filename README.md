# llama-ROCmFPX Builder

Builds the canonical [charlie12345/ROCmFPX](https://github.com/charlie12345/ROCmFPX)
fork with **Vulkan** (primary) + **HIP** (gfx1201) support for AMD GPUs, and
outputs `llama-server` / `llama-cli` / `llama-quantize` to a shared volume that
llama-swap reads. Comments aside, this is the upstream-minded build: Vulkan
needs no ROCm userspace on the host, which is what the existing llama-swap
stack runs.

## Why Vulkan

- The Unraid host has **no ROCm userspace** installed (`/opt/rocm*` empty).
- The existing llama-swap stack uses the **Vulkan** backend via `/dev/dri`.
- Upstream `build-rocmfp4.sh` enables `GGML_VULKAN=ON`, and their own tests
  measured Vulkan as the fastest decode backend on tested hardware.

## Usage

### On Unraid

1. Create a container from `ghcr.io/xpsixx/llama-rocmfpx:latest`
2. Add a volume mount: `/mnt/user/AI/llama-swap/bin` → `/output`
3. Set env var `OUTPUT_DIR=/output`
4. Run once — it copies the binaries to the mounted path and exits

From Unraid CLI:
```bash
docker run --rm \
  -v /mnt/user/AI/llama-swap/bin:/output \
  -e OUTPUT_DIR=/output \
  ghcr.io/xpsixx/llama-rocmfpx:latest
```

> **Note:** the repo is `llama-ROCmFPX`; GitHub container registry lowercases
> it, so the image name is `ghcr.io/xpsixx/llama-rocmfpx` (not `rocmpfx`).

### In llama-swap config.yaml

Point a model's `cmd` at the mounted binary (llama-swap spawns `llama-server`
from the path you give it):

```yaml
models:
  "your-model":
    cmd: |
      /mnt/user/AI/llama-swap/bin/llama-server --port ${PORT}
      --model /path/to/model.gguf
      --ctx-size 32768
```

Then `docker pull ghcr.io/xpsixx/llama-rocmfpx:latest`, re-run the container to
refresh `/mnt/user/AI/llama-swap/bin`, and restart llama-swap.

### Updating

Click **Update** on the Unraid Docker UI for this container, or:

```bash
docker pull ghcr.io/xpsixx/llama-rocmfpx:latest
docker run --rm \
  -v /mnt/user/AI/llama-swap/bin:/output \
  -e OUTPUT_DIR=/output \
  ghcr.io/xpsixx/llama-rocmfpx:latest
```

## How it works

- **GitHub Actions** rebuilds on every push to `main`, on a `repository_dispatch`
  `upstream-changed` event (so you can fire one on upstream commits), and
  weekly via cron as a fallback.
- The **Dockerfile** clones `charlie12345/ROCmFPX`, builds `llama-server`
  with `-DGGML_VULKAN=ON` (and `-DGGML_HIP=ON` targeting gfx1201). The build
  stage is a plain Ubuntu + Vulkan toolchain — **no ROCm SDK needed**.
- The **entrypoint** copies the binaries to `$OUTPUT_DIR` and exits.
- Built GPU target: **gfx1201** (RX 9070 / 9070 XT). Change `Dockerfile`
  `CMAKE_HIP_ARCHITECTURES` if you want a different one.