# llama-cpp-rdna-boosts bundle

Portable, GPU-arch-trimmed extraction of the patched **llama.cpp + ROCm runtime** from
[`stew675/llama-cpp-rdna-boosts`](https://github.com/stew675/llama-cpp-rdna-boosts)
prebuilt server images — so a container that has **no ROCm installed** (for example
`ghcr.io/mostlygeek/llama-swap:vulkan`) can launch the HIP build by bind-mounting a
directory and setting `LD_LIBRARY_PATH`.

Nothing is ever started at build time: images are inspected with `docker create` +
`docker cp`, so no server process, model load, or GPU allocation happens while the
bundle is assembled.

## Why

The upstream project publishes full ROCm container images (~10.5 GB compressed,
~22 GB expanded). If you already run a llama-server orchestrator such as
[llama-swap](https://github.com/mostlygeek/llama-swap) with your own model mounts,
config, health checks and proxy behaviour, dropping in a second full ROCm container
means duplicating the runtime, the mounts and the orchestration.

This repo produces a **~2.5 GB bundle** you can mount into the container you already
run:

```
llama-rdna-boosts/
  app/     llama-server, llama, libllama*, libggml* (incl. libggml-hip.so), libmtmd
  rocm/    the resolved ROCm soname closure + Tensile kernel archives for ONE ISA
  manifest.json
```

The bundle contains only what the loader actually resolves **inside** the ROCm tree;
base-image libraries (glibc, libstdc++, libssl, …) are deliberately excluded so the
bundle stays version-agnostic.

## Requirements

- Target container must provide **glibc ≥ 2.38** and **GLIBCXX ≥ 3.4.32**
  (Ubuntu 24.04+ satisfy this; check with `ldd --version`).
- The container needs `--device /dev/kfd --device /dev/dri --group-add video`.
- Host must have the `amdgpu` driver — no ROCm installation on the host is required.
- `docker`, `python3`, `curl`.

## Build locally

```bash
./extract.sh                    # latest upstream release, gfx1201, ROCm 10.2
GFX=gfx1100 ./extract.sh        # RDNA3 (RX 7800 XT, 7900 XTX)
ROCM_LINE=7.14.1 ./extract.sh   # alternate ROCm line
RELEASE=v18-919794500-r368 ./extract.sh   # pin a specific upstream release
```

Environment knobs: `GFX`, `GFX_FALLBACK`, `ROCM_LINE`, `RELEASE`, `OUT`,
`REPO_SRC`, `REGISTRY_IMAGE`, `PULL`.

Verify it links and loads before deploying:

```bash
./verify.sh bundle
# [verify] bundle: /…/bundle (2.5G)
# --- unresolved in libggml-hip.so
# --- version
# version: 1.0.0-dev (build 0, commit unknown)
# [verify] OK
```

`verify.sh` runs inside a ROCm-less target image (`TARGET_IMAGE`, default
llama-swap:vulkan) and additionally enumerates devices when `/dev/kfd` is present.

## Deploy

```bash
sudo mkdir -p /mnt/user/appdata/llama-swap/llama-rdna-boosts
sudo tar -xzf rdna-boosts-gfx1201-rocm10.2-<release>.tar.gz -C /tmp
sudo cp -a /tmp/bundle/. /mnt/user/appdata/llama-swap/llama-rdna-boosts/
```

Mount it into your server container (`.../llama-rdna-boosts -> /app/llama-rdna-boosts`)
and add a model entry:

```yaml
FlashNext-rdna:
  cmd: /app/llama-rdna-boosts/app/llama-server --port ${PORT} --host 0.0.0.0
       -m /models/Qwen3.8-Flash-Next-IQ3_XXS-00001-of-00002.gguf
       --n-gpu-layers 999 --cpu-moe --moe-cache-mib 3072 --ctx-size 131072
       --cache-type-k q8_0 --cache-type-v q8_0 --batch-size 2048 --ubatch-size 2048
       -fa on --threads 8 --parallel 1 --metrics
  env:
    LD_LIBRARY_PATH: /app/llama-rdna-boosts/app:/app/llama-rdna-boosts/rocm/lib
```

`LD_LIBRARY_PATH` must include **both** `app/` (llama's own libs) and `rocm/lib/`.
If your orchestrator cannot set env vars per model, wrap the binary in a two-line
shell script that exports `LD_LIBRARY_PATH` and `exec`s `llama-server`.

## What gets trimmed

Measured on `gfx1201` / ROCm 10.2 (`v18-919794500-r368`):

| Component | Full image | Bundle |
|---|---|---|
| llama.cpp binaries | ~2 GB (all ISA kernels embedded in `libggml-hip.so`) | same — cannot be trimmed |
| ROCm soname closure | 22 GB tree | ~0.5 GB (28 real libs + ~127 soname symlinks, incl. the `librocm_sysdeps_*` shims) |
| rocBLAS kernels | 803 MB (every ISA) | ~0.5 GB (`gfx1201` only: `.hsaco`, `.co`, `.dat` + index files) |
| hipBLASLt kernels | 2.4 GB (every ISA) | ~0.16 GB (`gfx1201`) |
| **total** | — | **~3.1 GB** |

Set `GFX_FALLBACK=gfx1200` to keep a second ISA's hipBLASLt kernels (adds ~0.2 GB).
`libggml-hip.so` is the one irreducible piece: it carries code objects for every
targeted GPU family. Rebuild from source with a single `AMDGPU_TARGETS` entry if
size matters more than build time.

## Troubleshooting

- **`not found` for `librocblas.so.5` but the file `librocblas.so.5.8` is present** —
  the bundle lost its soname symlinks. `docker cp -L` copies real files only; the
  loader needs the `soname → realfile` aliases, which `extract.sh` recreates.
- **`libggml-hip.so` misses `librocm_sysdeps_*` / `librocsolver` / `libomp`** — the
  closure was computed non-recursively. Those are transitive deps living in
  `lib/rocm_sysdeps/lib` and `lib/llvm/lib`; the walk must follow `ldd` of every
  discovered library, not just the top-level binaries.
- **A foreign ISA's kernels survive pruning** — Tensile archives come as `.hsaco`,
  `.co` *and* `.dat`; prune on the `gfx` substring, never on one extension.
- **`verify.sh` reports the binary missing while it exists** — the path passed to
  `docker -v` must be one the *host* can see. Set `HOST_BUNDLE` when running from a
  container/agent workspace whose paths are not host paths.
- **`ldd` says everything resolves but generation fails** — the target container's
  glibc is too old. Check `ldd --version` (needs ≥ 2.38) and `libstdc++` (≥ 3.4.32).

## Verified

`extract.sh` + `verify.sh` were run against `server-rocm-10.2-v18-919794500-r368`
with `GFX=gfx1201`, deployed into `ghcr.io/mostlygeek/llama-swap:vulkan` (which has
no ROCm at all) on an RX 9070 host: all shared libraries resolved and
`llama-server --list-devices` reported
`ROCm0: AMD Radeon RX 9070 (gfx1201) (16304 MiB)`.

## Weekly CI

`.github/workflows/weekly-bundle.yml` runs **Mondays 05:00 UTC** and on demand:

1. reads `release.json` from upstream to learn the current release (`v18-…-rNNN`)
2. skips entirely if a GitHub release for that asset already exists (idempotent —
   weekly runs are a safety net, not a rebuild loop)
3. pulls the pinned `server-rocm-<line>-<release>` image, extracts, trims, verifies
4. uploads the bundle as a workflow artifact **and** publishes it as a prerelease
   asset with a `.sha256`

Manual dispatch accepts `rocm_line`, `gfx`, `release` and `force`.

## Notes and caveats

- **ROCm 10.1 is retired upstream** (2026-11-23); use `10.2` or `7.14.1`. The
  `server-rocm-10.1` tag many blog posts cite is stale.
- The ISA (`gfx…`) must match your card. One bundle serves one architecture family;
  build per arch or keep a fallback ISA in `GFX_FALLBACK`.
- ROCm's loader prefers hipBLASLt; if a Tensile kernel archive is missing for the
  running ISA, GEMMs silently fall back to slower paths rather than failing.
- `libggml-hip.so` requires `libgomp`; it is bundled (resolved from the ROCm tree) so
  a minimal base image does not need its own OpenMP runtime.
- This project ships **no** llama.cpp or ROCm source — it repackages prebuilt
  artifacts. Licensing follows upstream: llama.cpp is MIT; ROCm and its components
  carry their own terms.

## License

Scripts in this repo: MIT. Extracted binaries retain their upstream licenses.
