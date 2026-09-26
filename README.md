# llama-ROCmFPX Builder

Builds the latest [ArtomYuan/llama.cpp-rocm](https://github.com/ArtomYuan/llama.cpp-rocm) fork with ROCm/HIP support for AMD GPUs.

## Usage

### On Unraid

1. Create a container from `ghcr.io/xpsixx/llama-rocmpfx:latest`
2. Add a volume mount: `/mnt/user/AI/llama-swap/bin` → `/output`
3. Set env var `OUTPUT_DIR=/output`
4. Run once — it copies `llama-server` to the mounted path and exits

From Unraid CLI:
```bash
docker run --rm \
  -v /mnt/user/AI/llama-swap/bin:/output \
  -e OUTPUT_DIR=/output \
  ghcr.io/xpsixx/llama-rocmpfx:latest
```

### In llama-swap config.yaml

```yaml
models:
  "your-model":
    cmd: |
      /mnt/user/AI/llama-swap/bin/llama-server --port ${PORT}
      --model /path/to/model.gguf
      --ctx-size 32768
```

### Updating

Click **Update** on the Unraid Docker UI for this container, or:

```bash
docker pull ghcr.io/xpsixx/llama-rocmpfx:latest
docker run --rm \
  -v /mnt/user/AI/llama-swap/bin:/output \
  -e OUTPUT_DIR=/output \
  ghcr.io/xpsixx/llama-rocmpfx:latest
```

## How it works

- **GitHub Actions** rebuilds on every push to `main` and weekly via cron
- The **Dockerfile** clones the upstream fork, builds `llama-server` with `-DGGML_HIP=ON`
- The **entrypoint** copies the binary to `$OUTPUT_DIR` and exits
- The AMDGPU targets include RDNA 4 (gfx1201) for RX 9070