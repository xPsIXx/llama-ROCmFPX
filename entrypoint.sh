#!/bin/sh
set -e

OUTPUT_DIR="${OUTPUT_DIR:-/output}"

if [ ! -d "$OUTPUT_DIR" ]; then
    echo "ERROR: OUTPUT_DIR ($OUTPUT_DIR) does not exist or is not mounted"
    exit 1
fi

echo "Copying llama binaries to $OUTPUT_DIR/"
cp /usr/local/bin/llama-server    "$OUTPUT_DIR/llama-server"
cp /usr/local/bin/llama-cli       "$OUTPUT_DIR/llama-cli"
cp /usr/local/bin/llama-quantize  "$OUTPUT_DIR/llama-quantize"
chmod +x "$OUTPUT_DIR/llama-server" "$OUTPUT_DIR/llama-cli" "$OUTPUT_DIR/llama-quantize"

echo "Done. Binaries placed at $OUTPUT_DIR/"
echo "Built from charlie12345/ROCmFPX commit:"
/usr/local/bin/llama-server --version 2>&1 || true