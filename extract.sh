#!/usr/bin/env bash
# Extract a mountable llama.cpp + ROCm runtime bundle from a llama-cpp-rdna-boosts
# server image, trimmed to a single AMD GPU architecture.
#
# The result can be bind-mounted into a container that has no ROCm installed
# (e.g. ghcr.io/mostlygeek/llama-swap:vulkan) and invoked with LD_LIBRARY_PATH.
#
# Nothing is ever *started*: the image is inspected via `docker create` +
# `docker cp`, so no server process, model load, or GPU allocation happens here.
set -euo pipefail

REPO_SRC="${REPO_SRC:-stew675/llama-cpp-rdna-boosts}"
REGISTRY_IMAGE="${REGISTRY_IMAGE:-ghcr.io/stew675/llama-cpp-rdna-boosts}"
ROCM_LINE="${ROCM_LINE:-10.2}"           # 10.2 (current) or 7.14.1. 10.1 is RETIRED.
GFX="${GFX:-gfx1201}"                    # target ISA, e.g. gfx1201 (RX 9070), gfx1100, gfx1151
GFX_FALLBACK="${GFX_FALLBACK:-}"         # optional extra ISA kept for hipBLASLt
RELEASE="${RELEASE:-}"                   # empty = resolve latest from release.json
OUT="${OUT:-bundle}"
PULL="${PULL:-1}"

log() { printf '[extract] %s\n' "$*"; }
die() { printf '[extract] ERROR: %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null || die "docker not found"
command -v python3 >/dev/null || die "python3 not found"

# ---------------------------------------------------------------- resolve tag
if [ -z "$RELEASE" ]; then
  log "resolving latest release from ${REPO_SRC}/release.json"
  RELEASE=$(curl -fsSL "https://raw.githubusercontent.com/${REPO_SRC}/main/release.json" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["release"])') \
    || die "could not read release.json"
fi
TAG="server-rocm-${ROCM_LINE}-${RELEASE}"
IMAGE="${REGISTRY_IMAGE}:${TAG}"
log "target image: ${IMAGE}"

# ------------------------------------------------------------------- prepare
if [ "$PULL" = "1" ]; then
  log "pulling ${IMAGE} (several GB)"
  docker pull "$IMAGE" >/dev/null
fi

CID="rdna-extract-$$"
cleanup() { docker rm -f "$CID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# create-never-start: no server process, no GPU touch
docker create --name "$CID" "$IMAGE" >/dev/null

rm -rf "$OUT"
mkdir -p "$OUT/app" "$OUT/rocm/lib"

# --------------------------------------------------- llama.cpp side (/app)
log "extracting llama.cpp binaries and libs"
APP_SRC="/tmp/rdna-app-$$"
mkdir -p "$APP_SRC"
docker cp "$CID:/app" "$APP_SRC/app" >/dev/null
SRC="$APP_SRC/app"

cp -a "$SRC/llama-server" "$APP_SRC/llama" "$OUT/app/" 2>/dev/null || true
for pat in 'libllama*.so*' 'libggml*.so*' 'libmtmd.so*'; do
  # shellcheck disable=SC2086
  cp -a $SRC/$pat "$OUT/app/" 2>/dev/null || true
done
rm -rf "$APP_SRC"

[ -x "$OUT/app/llama-server" ] || die "llama-server missing from image /app"

# ------------------------------------------- ROCm runtime closure (shared libs)
# Walk the dependency graph *recursively* from llama-server, its impl lib and the
# HIP backend, keeping only sonames that resolve inside the ROCm tree. Base-image
# libraries (glibc, libstdc++, libssl, ...) are intentionally not bundled: the
# target container already provides them.
#
# NOTE: the script below runs inside the image, so it must not contain a single
# quote character -- it is embedded here inside a single-quoted shell argument.
log "resolving recursive ROCm shared-library closure inside the image"
CLOSURE=$(
  docker run --rm --entrypoint bash "$IMAGE" -c '
    set -e
    declare -A seen=()
    frontier=(/app/llama-server /app/libllama-server-impl.so /app/libggml-hip.so /app/libllama.so.1 /app/libllama-common.so.1)
    rounds=0
    while [ ${#frontier[@]} -gt 0 ] && [ $rounds -lt 40 ]; do
      rounds=$((rounds+1))
      next=()
      for f in "${frontier[@]}"; do
        [ -e "$f" ] || continue
        while read -r soname p; do
          [ -n "$p" ] && [ -e "$p" ] || continue
          real=$(readlink -f "$p")
          case "$real" in /opt/rocm/*) ;; *) continue ;; esac
          if [ -z "${seen[$real]:-}" ]; then
            seen[$real]=1
            next+=("$real")
          fi
          printf "%s %s\n" "$soname" "$real"
        done < <(ldd "$f" 2>/dev/null | awk "{ if (\$3 ~ /^\//) print \$1 \" \" \$3 }")
      done
      frontier=("${next[@]}")
    done
    _rbl=$(find /opt/rocm -maxdepth 4 -name "librocblas.so.5*" -print -quit 2>/dev/null || true)
    if [ -n "$_rbl" ]; then printf "ROCMROOT %s\n" "$(dirname "$(readlink -f "$_rbl")")"; fi
    for k in "${!seen[@]}"; do printf "REAL %s\n" "$k"; done | sort
  '
) || die "closure resolution failed (image must ship bash + ldd)"

ROCM_LIB=$(printf '%s\n' "$CLOSURE" | awk '$1=="ROCMROOT"{print $2}' | head -1)
LIBS=$(printf '%s\n' "$CLOSURE" | awk '$1=="REAL"{print $2}' | sort -u)
PAIRS=$(printf '%s\n' "$CLOSURE" | awk '$1!="REAL" && $1!="ROCMROOT" && $2 ~ /^\//{print $1"|"$2}')
[ -n "$LIBS" ] || die "empty ROCm closure"
[ -n "$ROCM_LIB" ] || die "could not determine the ROCm library directory"

# Copy real files (-L dereferences), then recreate the SONAME alias symlinks the
# dynamic loader actually asks for: DT_NEEDED entries name libfoo.so.5 while the
# on-disk file is libfoo.so.5.8, and only the symlink bridges the two.
count=0
for p in $LIBS; do
  if docker cp -L "$CID:$p" "$OUT/rocm/lib/" >/dev/null 2>&1; then
    count=$((count + 1))
  else
    log "  WARN could not copy $p"
  fi
done
links=0
while IFS='|' read -r soname real; do
  [ -n "$soname" ] && [ -n "$real" ] || continue
  base=$(basename "$real")
  [ "$soname" = "$base" ] && continue
  [ -e "$OUT/rocm/lib/$base" ] || continue
  ln -sfn "$base" "$OUT/rocm/lib/$soname"
  links=$((links + 1))
done <<< "$PAIRS"
log "copied ${count} runtime libraries + ${links} soname links from ${ROCM_LIB} ($(du -sh "$OUT/rocm/lib" | cut -f1))"

# --------------------------------------------------------- Tensile kernel archives
# rocBLAS ships one kernel archive per GPU ISA; the full set is ~800 MB and only
# the target ISA (plus the non-ISA index files) is needed.
log "extracting rocBLAS kernel archives for ${GFX}"
mkdir -p "$OUT/rocm/lib/rocblas"
if docker cp "$CID:$ROCM_LIB/rocblas/library" "$OUT/rocm/lib/rocblas/library" >/dev/null 2>&1; then
  # Drop every file whose name pins a different GPU ISA -- archives come as
  # .hsaco, .co and .dat variants, so match the "gfx" substring, not an
  # extension. Names without "gfx" are index/fallback files: always kept.
  find "$OUT/rocm/lib/rocblas/library" -maxdepth 1 -type f \
    -name '*gfx*' -not -name "*${GFX}*" -delete
  log "  rocblas kernels: $(du -sh "$OUT/rocm/lib/rocblas/library" | cut -f1), $(ls "$OUT/rocm/lib/rocblas/library" | wc -l) files"
else
  die "rocBLAS kernel library not found at ${ROCM_LIB}/rocblas/library"
fi

log "extracting hipBLASLt kernel archives for ${GFX}"
mkdir -p "$OUT/rocm/lib/hipblaslt/library"
FOUND_HBLASLT=0
for isa in "$GFX" "$GFX_FALLBACK"; do
  [ -n "$isa" ] || continue
  if docker cp "$CID:$ROCM_LIB/hipblaslt/library/$isa" "$OUT/rocm/lib/hipblaslt/library/" >/dev/null 2>&1; then
    FOUND_HBLASLT=1
  fi
done
[ "$FOUND_HBLASLT" = "1" ] || die "hipBLASLt kernel library not found for ${GFX}"
# top-level Tensile metadata / fallback files beside the ISA dirs
HBL_TMP="/tmp/rdna-hblaslt-$$"
if docker cp "$CID:$ROCM_LIB/hipblaslt/library" "$HBL_TMP" >/dev/null 2>&1; then
  find "$HBL_TMP" -maxdepth 1 -type f -exec cp -a {} "$OUT/rocm/lib/hipblaslt/library/" \; 2>/dev/null || true
  rm -rf "$HBL_TMP"
fi
log "  hipBLASLt kernels: $(du -sh "$OUT/rocm/lib/hipblaslt" | cut -f1)"

# ---------------------------------------------------------------- manifest
BLOCKS=$(docker inspect "$CID" --format '{{index .Config.Labels "io.github.stew675.rdna-boosts.blocks"}}' 2>/dev/null || echo "")
CREATED=$(docker inspect "$CID" --format '{{index .Config.Labels "org.opencontainers.image.created"}}' 2>/dev/null || echo "")
cat > "$OUT/manifest.json" <<EOF
{
  "image": "${IMAGE}",
  "release": "${RELEASE}",
  "rocm_line": "${ROCM_LINE}",
  "gfx": "${GFX}",
  "patches": "${BLOCKS}",
  "image_created": "${CREATED}",
  "generated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "libraries": $(printf '%s\n' "$LIBS" | wc -l),
  "files": $(find "$OUT" -type f | wc -l),
  "size": "$(du -sh "$OUT" | cut -f1)"
}
EOF

log "bundle ready: $OUT ($(du -sh "$OUT" | cut -f1), $(find "$OUT" -type f | wc -l) files)"
cat "$OUT/manifest.json"
