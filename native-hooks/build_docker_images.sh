#!/bin/bash

set -e

echo "==> Building Linux amd64 build image..."
docker build -f Dockerfile.linux.amd64 -t local-media-listener/linux-builder:amd64 .

echo "==> Building Linux arm64 build image..."
docker build -f Dockerfile.linux.arm64 -t local-media-listener/linux-builder:arm64 .

echo "==> Docker images built successfully."
echo "    - local-media-listener/linux-builder:amd64"
echo "    - local-media-listener/linux-builder:arm64"
echo ""
echo "You can now run the build scripts which will use these pre-built images."
echo "This will significantly speed up your builds!" 