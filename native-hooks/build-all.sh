#!/usr/bin/env bash
set -euo pipefail

# check if this is run by bash
if [ -z "${BASH_SOURCE[0]}" ]; then
    echo "This script must be run by bash"
    exit 1
fi

START_TIME=$(date +%s)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

chmod +x ./clean.sh
./clean.sh

echo "==> Starting all builds in parallel"

# Linux builds
chmod +x ./build-linux.sh
./build-linux.sh amd64 &
./build-linux.sh arm64 &

# macOS build (universal)
chmod +x ./build-macos.sh
./build-macos.sh universal &

# Wait for all builds to finish
wait

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "==> All builds completed successfully in $((DURATION / 60))m $((DURATION % 60))s" 
echo "==> Run ./build-windows.ps1 on a windows host to complete the build process"
