#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
# Root output directory for all compiled libraries (relative to script location).
# All final artifacts will be placed directly in this folder with OS/ARCH suffixes.
OUTPUT_ROOT_DIR="../src/main/resources/lib"

# Temporary build directory for intermediate Go libs and headers (relative to script location).
# This directory is used to store the Go-generated static archive (.a) and its corresponding
# C header file (.h) before they are used by the C bridge compilation.
TMP_BUILD_DIR="./tmp_native_build"

# Go package path (relative to this script's location).
# This assumes your Go entry point files (e.g., main_linux.go) are directly in the current directory.
GO_PACKAGE_BASE_PATH="."

# Define host paths for Go caches
HOST_GO_MOD_CACHE="$HOME/go/pkg/mod"
HOST_GO_BUILD_CACHE="$HOME/.cache/go-build"

# --- Pre-requisite Checks and Installations (Linux only) ---
# Function to check for essential build dependencies, primarily Docker, on Linux.
check_dependencies() {
  echo "==> Checking build dependencies for Linux..."
  
  # Docker is essential for Linux CGO cross-compilation as it provides a consistent
  # environment with necessary tools and libraries (like libdbus-1-dev).
  if ! command -v docker &> /dev/null; then
    echo "Docker CLI not found. Please install Docker and ensure it's running."
    exit 1
  else
    # Verify that the Docker daemon is running.
    if ! docker info &> /dev/null; then
      echo "Docker daemon is not running. Please start Docker."
      exit 1
    fi
    echo "Docker is installed and running."
  fi

  # Check if our optimized images exist
  if ! docker image inspect local-media-listener/linux-builder:amd64 >/dev/null 2>&1; then
    echo "Error: Optimized Docker image 'local-media-listener/linux-builder:amd64' not found."
    echo "Please run './build_docker_images.sh' first to build the optimized images."
    exit 1
  fi
  if ! docker image inspect local-media-listener/linux-builder:arm64 >/dev/null 2>&1; then
    echo "Error: Optimized Docker image 'local-media-listener/linux-builder:arm64' not found."
    echo "Please run './build_docker_images.sh' first to build the optimized images."
    exit 1
  fi
  
  echo "==> All Linux dependencies checked."
}

# --- Helper Function for building a single architecture ---
build_arch() {
  local target_arch=$1
  echo "==> Building for linux/$target_arch..."

  local temp_output_dir="$TMP_BUILD_DIR/linux-${target_arch}"
  mkdir -p "$temp_output_dir" "$HOST_GO_MOD_CACHE" "$HOST_GO_BUILD_CACHE"

  docker run --rm \
    -v "$(pwd)":/app \
    -v "$HOST_GO_MOD_CACHE":/go/pkg/mod \
    -v "$HOST_GO_BUILD_CACHE":/root/.cache/go-build \
    -v "$(pwd)/$OUTPUT_ROOT_DIR":/resource-lib \
    -w /app \
    "local-media-listener/linux-builder:${target_arch}" \
    bash -c "
      set -e
      
      export GOOS=linux
      export GOARCH=$target_arch
      export CGO_ENABLED=1

      go build -buildmode=c-archive -o \"/app/$temp_output_dir/libnative_hook_linux_${target_arch}.a\" \"$GO_PACKAGE_BASE_PATH/main_linux.go\"
      cp \"/app/$temp_output_dir/libnative_hook_linux_${target_arch}.h\" \"./bridge/\"

      cd bridge
      
      gcc -c -fPIC \"bridge_linux_${target_arch}.c\" -o \"bridge_linux_${target_arch}.o\" \
        -I\"/app/$temp_output_dir\" -I. -I\"/usr/lib/jvm/java-17-openjdk-${target_arch}/include\" -I\"/usr/lib/jvm/java-17-openjdk-${target_arch}/include/linux\"
      
      gcc -shared -o \"libbridge_linux_${target_arch}.so\" \"bridge_linux_${target_arch}.o\" \
        -L\"/app/$temp_output_dir\" -lnative_hook_linux_${target_arch}

      mv \"libbridge_linux_${target_arch}.so\" \"/resource-lib\"
    "
}

# Cleanup function to remove previously built artifacts and temporary files.
cleanup() {
  echo "==> Cleaning up previous build artifacts..."
  # Remove all .so files from the final output directory (these will now only be the consolidated bridge .so).
  rm -f "$OUTPUT_ROOT_DIR"/*.so
  # Remove temporary build directories, which contain the Go static archives (.a) and headers.
  rm -rf "$TMP_BUILD_DIR/linux*"
  # Remove Go-generated headers that might be left in bridge/
  rm -f ./bridge/*.h 
  # Remove object files from bridge/
  rm -f ./bridge/*.o 
  echo "Cleanup complete."
}

# --- Main Build Process ---

# Record the start time for build duration calculation.
CURRENT_UNIX_TIMESTAMP=$(date +%s)

# Step 1: Check for necessary build dependencies (Docker).
check_dependencies

# Step 2: Clean up previous builds to ensure a fresh start.
cleanup
# Ensure the root output directory exists for the final artifacts.
mkdir -p "$OUTPUT_ROOT_DIR"

# --- Parallel Build ---
echo "==> Starting parallel builds for all architectures..."
build_arch "arm64" &
build_arch "amd64" &

wait

# Record the end time and calculate build duration.
NOW_UNIX_TIMESTAMP=$(date +%s)

echo "==> All Linux builds completed. Final consolidated libraries are in: $OUTPUT_ROOT_DIR"
echo "==> Build duration: $(( (NOW_UNIX_TIMESTAMP - CURRENT_UNIX_TIMESTAMP) / 60 ))m $(( (NOW_UNIX_TIMESTAMP - CURRENT_UNIX_TIMESTAMP) % 60 ))s"
