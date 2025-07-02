#!/bin/bash

set -e

echo "==> Starting cross-platform native build..."

if ! docker image inspect local-media-listener/linux-builder:amd64 >/dev/null 2>&1 || \
   ! docker image inspect local-media-listener/linux-builder:arm64 >/dev/null 2>&1; then
  echo "Optimized Docker images not found. Running './build_docker_images.sh' first..."
  ./build_docker_images.sh
fi

echo "==> Building macOS targets..."
./build_darwin.sh

echo "==> Building Linux targets..."
./build_linux.sh

echo ""
echo "✅ All builds completed successfully!" 