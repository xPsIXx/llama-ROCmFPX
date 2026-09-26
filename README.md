# llama-ROCmFPX Builder

Builds the canonical [charlie12345/ROCmFPX](https://github.com/charlie12345/ROCmFPX)
fork with a **Vulkan** backend for AMD GPUs, and outputs `llama-server`,
`llama-cli`, and `llama-quantize` to a folder of your choosing via a shared
volume that llama-swap reads.

This supports my llama-swap setup: each built binary gets its own name, so I
can point specific models at this custom llama-server through the llama-swap
config without overwriting the stock `/app/llama-server`. It's the
upstream-minded build — Vulkan needs no ROCm userspace on the host, which is
what the existing llama-swap stack already runs.

## Why Vulkan

- The Unraid host has **no ROCm userspace** installed (`/opt/rocm*` empty).
- The existing llama-swap stack uses the **Vulkan** backend via `/dev/dri`.
- Upstream `build-rocmfp4.sh` enables `GGML_VULKAN=ON`, and their own tests
  measured Vulkan as the fastest decode backend on tested hardware.

## Usage

### On Unraid

1. Create a container from `ghcr.io/xpsixx/llama-rocmfpx:latest`
2. Add a volume mount so the built binaries land where llama-swap can read them —
   e.g. a host path shared with the llama-swap container, or directly onto
   llama-swap's `/app` via a bind mount.
3. Set env vars:
   - `OUTPUT_DIR` — destination directory (default `/output`)
   - `SERVER_BIN`  — filename for the built llama-server (default `llama-rocmfpx-server`)
   - `CLI_BIN`     — filename for llama-cli (default `llama-rocmfpx-cli`)
   - `QUANT_BIN`   — filename for llama-quantize (default `llama-rocmfpx-quantize`)
   - Defaults use a `rocmfpx` suffix so the built `llama-server` never overwrites
     llama-swap's own stock `/app/llama-server` when both share a mount.
   - The entrypoint also copies the dlopen'd backend modules (`ggml-*.so` — the
     CPU instruction variants and the Vulkan backend) into the same folder, so
     the renamed binary finds them at runtime. Point llama-swap's `cmd:` at the
     `SERVER_BIN` name as usual; keep the `.so` files next to it in the folder.
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

Point a model's `cmd` at the built binary (llama-swap spawns it from the path
you give it — use the `SERVER_BIN` name from above). If you bind-mounted the
built binary onto llama-swap's `/app/llama-rocmfpx-server`:

```yaml
models:
  "your-model":
    cmd: |
      /app/llama-rocmfpx-server --port ${PORT}
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
  with `-DGGML_VULKAN=ON` (Vulkan-only, no ROCm SDK needed at build or runtime).
  The build stage is a plain Ubuntu + Vulkan toolchain.
- The **entrypoint** copies the binaries to `$OUTPUT_DIR` and exits.
- Built backend: **Vulkan**, which runs on the host's `/dev/dri` with the Mesa
  radeon driver — no AMDGPU compute install required.
