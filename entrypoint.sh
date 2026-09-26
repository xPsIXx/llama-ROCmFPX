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

echo "Copying binaries to $OUTPUT_DIR/"
cp /usr/local/bin/llama-server   "$OUTPUT_DIR/$SERVER_BIN"
cp /usr/local/bin/llama-cli      "$OUTPUT_DIR/$CLI_BIN"
cp /usr/local/bin/llama-quantize "$OUTPUT_DIR/$QUANT_BIN"
chmod +x "$OUTPUT_DIR/$SERVER_BIN" "$OUTPUT_DIR/$CLI_BIN" "$OUTPUT_DIR/$QUANT_BIN"

echo "Done. Binaries placed at $OUTPUT_DIR/:"
echo "  server  -> $SERVER_BIN"
echo "  cli     -> $CLI_BIN"
echo "  quantize-> $QUANT_BIN"
echo "Built from charlie12345/ROCmFPX commit:"
/usr/local/bin/llama-server --version 2>&1 || true