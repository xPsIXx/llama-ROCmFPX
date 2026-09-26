#!/bin/sh
set -e

# Where to place the built binaries. Map this to a path llama-swap can read.
OUTPUT_DIR="${OUTPUT_DIR:-/output}"

# Output names — default to a distinct suffix so we never overwrite
# llama-swap's own stock /app/llama-server when both share a mount.
SERVER_BIN="${SERVER_BIN:-llama-rocmfpx-server}"
CLI_BIN="${CLI_BIN:-llama-rocmfpx-cli}"
QUANT_BIN="${QUANT_BIN:-llama-rocmfpx-quantize}"

if [ ! -d "$OUTPUT_DIR" ]; then
    echo "ERROR: OUTPUT_DIR ($OUTPUT_DIR) does not exist or is not mounted"
    exit 1
fi

echo "== Copying built binaries into $OUTPUT_DIR =="

copy_file() {
    local src="$1"   # source path inside this container
    local dst="$2"   # full destination path

    if [ ! -f "$src" ]; then
        echo "ERROR: source missing: $src"
        exit 1
    fi

    local src_size
    src_size="$(stat -c %s "$src" 2>/dev/null || echo "?")"

    if [ -f "$dst" ]; then
        # Overwriting an existing file: report old vs new size
        local old_size
        old_size="$(stat -c %s "$dst" 2>/dev/null || echo "?")"
        echo "OVERWRITE: $dst"
        echo "    old: $old_size bytes"
        echo "    new: $src_size bytes (from $src)"
        cp -f "$src" "$dst"
    else
        echo "CREATE: $dst  ($src_size bytes, from $src)"
        cp "$src" "$dst"
    fi

    chmod +x "$dst"
}

copy_file /usr/local/bin/llama-server   "$OUTPUT_DIR/$SERVER_BIN"
copy_file /usr/local/bin/llama-cli      "$OUTPUT_DIR/$CLI_BIN"
copy_file /usr/local/bin/llama-quantize "$OUTPUT_DIR/$QUANT_BIN"

echo
echo "== Done. Files present in $OUTPUT_DIR: =="
ls -la "$OUTPUT_DIR"
echo
echo "Built from charlie12345/ROCmFPX commit:"
/usr/local/bin/llama-server --version 2>&1 || true