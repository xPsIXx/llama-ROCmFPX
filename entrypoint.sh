#!/bin/sh
# Bundle carrier entrypoint.
#
# Run this image once with a bind mount and it copies the extracted
# llama.cpp + ROCm runtime bundle onto that mount, then exits. The mounted
# folder is what llama-swap (or any other launcher) then reads the binary
# from -- same idea as the original llama-ROCmFPX image, which carried
# statically-linked llama-server binaries and dropped them into a mount.
#
#   docker run --rm -v /path/to/mount:/output IMAGE[:tag]
#
# Knobs:
#   OUTPUT_DIR   destination inside the container   (default /output)
#   MODE         copy | verify                      (default copy)
#                verify prints the manifest and file list without writing
set -eu

SRC="${SRC_DIR:-/bundle}"
OUT="${OUTPUT_DIR:-/output}"
MODE="${MODE:-copy}"

[ -d "$SRC" ] || { echo "entrypoint: no bundle at $SRC"; exit 1; }
[ -x "$SRC/app/llama-server" ] || { echo "entrypoint: $SRC/app/llama-server missing"; exit 1; }

if [ "$MODE" = "verify" ]; then
  echo "=== manifest ==="
  cat "$SRC/manifest.json" 2>/dev/null || echo "(no manifest)"
  echo "=== payload ==="
  echo "app:  $(find "$SRC/app" -type f | wc -l) files, $(du -sh "$SRC/app" | cut -f1)"
  echo "rocm: $(find "$SRC/rocm" -type f | wc -l) files, $(du -sh "$SRC/rocm" | cut -f1)"
  echo "=== entry point ==="
  ls -la "$SRC/app/llama-server"
  exit 0
fi

mkdir -p "$OUT"

# Warn loudly when OUTPUT_DIR is not a bind mount: the copy would vanish with
# the container, which looks like a silent no-op to the caller.
if ! grep -q " $OUT " /proc/mounts 2>/dev/null; then
  echo "entrypoint: WARNING $OUT does not look like a mount point; the copy will"
  echo "entrypoint: be discarded when this container exits. Pass -v <host dir>:/output"
fi

echo "entrypoint: copying bundle -> $OUT"
cp -a "$SRC/." "$OUT/"

if [ -f "$OUT/manifest.json" ]; then
  echo "entrypoint: manifest at $OUT/manifest.json"
  grep -E '"(release|gfx|rocm_line|size)"' "$OUT/manifest.json" || true
fi

echo "entrypoint: done — $(du -sh "$OUT" | cut -f1) in $OUT"
echo "entrypoint: LD_LIBRARY_PATH must include both"
echo "entrypoint:   $OUT/app:$OUT/rocm/lib"
