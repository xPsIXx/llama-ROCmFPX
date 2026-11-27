#!/usr/bin/env bash
# Verify an extracted bundle actually links and loads.
#
# Checks, in order:
#   1. every shared library the HIP backend needs resolves inside the bundle
#      (run against the *target* container image, which must not ship ROCm)
#   2. llama-server --version runs
#   3. llama-server --list-devices sees the GPU (only when /dev/kfd is present)
#
# No model is loaded and no llama-server instance is left running.
set -euo pipefail

BUNDLE="${1:-bundle}"
TARGET_IMAGE="${TARGET_IMAGE:-ghcr.io/mostlygeek/llama-swap:vulkan}"
BUNDLE_ABS=$(cd "$BUNDLE" && pwd)
# Path as the DOCKER HOST sees it. Identical to BUNDLE_ABS in normal use; set it
# explicitly when the bundle lives inside a container (e.g. a Hermes/agent
# workspace whose /opt/data is really /mnt/user/appdata/<name> on the host).
HOST_BUNDLE="${HOST_BUNDLE:-$BUNDLE_ABS}"
MOUNT="/bundle"
LP="/bundle/app:/bundle/rocm/lib"

fail() { printf '[verify] FAIL: %s\n' "$*" >&2; exit 1; }

[ -x "$BUNDLE_ABS/app/llama-server" ] || fail "no llama-server in $BUNDLE_ABS/app"
[ -d "$BUNDLE_ABS/rocm/lib" ] || fail "no rocm/lib in $BUNDLE_ABS"

printf '[verify] target container: %s\n' "$TARGET_IMAGE"
printf '[verify] bundle: %s (%s)\n' "$BUNDLE_ABS" "$(du -sh "$BUNDLE_ABS" | cut -f1)"

OUT=$(docker run --rm --entrypoint sh \
  -v "$HOST_BUNDLE:$MOUNT:ro" "$TARGET_IMAGE" -c "
    set -e
    echo '--- unresolved in llama-server'
    LD_LIBRARY_PATH='$LP' ldd $MOUNT/app/llama-server | grep 'not found' || true
    echo '--- unresolved in libggml-hip.so'
    LD_LIBRARY_PATH='$LP' ldd $MOUNT/app/libggml-hip.so | grep 'not found' || true
    echo '--- version'
    LD_LIBRARY_PATH='$LP' timeout 60 $MOUNT/app/llama-server --version 2>&1 | head -2
  ") || fail "container run failed"

printf '%s\n' "$OUT"

if printf '%s\n' "$OUT" | grep -q 'not found'; then
  fail "unresolved shared libraries in the bundle"
fi
printf '%s\n' "$OUT" | grep -q 'version:' || fail "llama-server --version produced no version line"

if [ -e /dev/kfd ] && [ -e /dev/dri ]; then
  printf '[verify] GPU present, enumerating devices\n'
  DEV=$(docker run --rm --device /dev/dri --device /dev/kfd --group-add video \
    --entrypoint sh -v "$HOST_BUNDLE:$MOUNT:ro" "$TARGET_IMAGE" -c \
    "LD_LIBRARY_PATH='$LP' timeout 120 $MOUNT/app/llama-server --list-devices 2>&1 | tail -5")
  printf '%s\n' "$DEV"
  printf '%s\n' "$DEV" | grep -qiE 'ROCm[0-9]|gfx' || fail "HIP backend enumerated no devices"
else
  printf '[verify] no /dev/kfd on this host — skipping device enumeration (runtime-only host)\n'
fi

printf '[verify] OK\n'
