#!/usr/bin/env bash
set -euo pipefail

# Resolve this script's directory (native-hooks folder)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Project root is parent of native-hooks
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Usage
usage() { echo "Usage: $0 <amd64|arm64|all>"; exit 1; }
[ $# -ge 1 ] || usage

arch="$1"
if [ "$arch" = "all" ]; then
  "$0" amd64
  "$0" arm64
  exit 0
fi

# Validate arch
if [ "$arch" != "amd64" ] && [ "$arch" != "arm64" ]; then
  echo "Invalid architecture: $arch"
  usage
fi

# Set Docker image and Dockerfile paths
image="lml-linux-${arch}"
dockerfile="${SCRIPT_DIR}/docker/Dockerfile.linux-${arch}"
# Always specify the target platform for Docker
if [ "$arch" = "arm64" ]; then
  platform="--platform linux/arm64"
else
  platform="--platform linux/amd64"
fi

# Build or reuse the Docker image
echo "==> Building Docker image ${image} for Linux ${arch}..."
docker build ${platform} -t "${image}" -f "${dockerfile}" "${SCRIPT_DIR}"

# Run the native build inside the container, mounting the entire project
# Override BUILD_DIR to isolate arch-specific builds
BUILD_DIR_OVERRIDE="build-${arch}"
echo "==> Running build.sh in Docker container for Linux ${arch} (BUILD_DIR=${BUILD_DIR_OVERRIDE})..."
docker run --rm ${platform} \
  -e BUILD_DIR="${BUILD_DIR_OVERRIDE}" \
  -v "${PROJECT_ROOT}":/workspace \
  -w /workspace/native-hooks "${image}" \
  bash build.sh

echo "==> Built Linux ${arch} successfully!" 