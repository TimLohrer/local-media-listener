#!/usr/bin/env bash
set -euo pipefail

# Usage: build-macos.sh <amd64|arm64|universal>
usage() { echo "Usage: $0 <amd64|arm64|universal>"; exit 1; }
[ $# -ge 1 ] || usage

arch="$1"
case "$arch" in
  amd64)
    EXTRA_CMAKE_ARGS="-DCMAKE_OSX_ARCHITECTURES=x86_64"
    ;;
  arm64)
    EXTRA_CMAKE_ARGS="-DCMAKE_OSX_ARCHITECTURES=arm64"
    ;;
  universal)
    EXTRA_CMAKE_ARGS="-DCMAKE_OSX_ARCHITECTURES=x86_64;arm64"
    ;;
  *)
    echo "Invalid arch: $arch"
    usage
    ;;
esac

# Export for build.sh
export EXTRA_CMAKE_ARGS
# Override BUILD_DIR to isolate builds
export BUILD_DIR="build-${arch}"
# Call the existing build script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
./build.sh 