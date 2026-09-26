#!/bin/sh
set -e

OUTPUT_DIR="${OUTPUT_DIR:-/output}"

if [ ! -d "$OUTPUT_DIR" ]; then
    echo "ERROR: OUTPUT_DIR ($OUTPUT_DIR) does not exist or is not mounted"
    exit 1
fi

echo "Copying llama-server to $OUTPUT_DIR/llama-server"
cp /usr/local/bin/llama-server "$OUTPUT_DIR/llama-server"
chmod +x "$OUTPUT_DIR/llama-server"

echo "Done. llmama-server binary placed at $OUTPUT_DIR/llama-server"
echo "Built from ArtomYuan/llama.cpp-rocm commit:"
/usr/local/bin/llama-server --version 2>&1 || true