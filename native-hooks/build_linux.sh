#!/bin/bash

set -e

# --- Configuration ---
# Root output directory for all compiled libraries (relative to script location)
# All final artifacts will be placed directly in this folder with OS/ARCH suffixes.
OUTPUT_ROOT_DIR="../src/main/resources/lib"

# Temporary build directory for intermediate Go libs and headers (relative to script location)
# All final artifacts will be placed directly in this folder with OS/ARCH suffixes.
TMP_BUILD_DIR="./tmp_native_build"

# Go package path (relative to this script's location)
# This assumes your Go entry point files are directly in the current directory
# e.g., main_linux.go
GO_PACKAGE_BASE_PATH="."

# --- Pre-requisite Checks and Installations (Linux only) ---
check_dependencies() {
  echo "==> Checking build dependencies for Linux..."
  
  # Docker is essential for Linux CGO cross-compilation
  if ! command -v docker &> /dev/null; then
    echo "Docker CLI not found. Please install Docker and ensure it's running."
    exit 1
  else
    if ! docker info &> /dev/null; then
      echo "Docker daemon is not running. Please start Docker."
      exit 1
    fi
    echo "Docker is installed and running."
  fi
  
  echo "==> All Linux dependencies checked."
}


# --- Helper Functions ---

# Function to build the Go shared library for Linux
# Args:
# $1: target_arch (e.g., "amd64", "arm64")
# $2: go_source_file (e.g., "main_linux.go")
# $3: temp_output_dir (where to place the compiled Go lib and its header temporarily)
# $4: final_output_filename_base (e.g., "native_hook")
build_go() {
  local target_arch=$1
  local go_source_file=$2
  local temp_output_dir=$3
  local final_output_filename_base=$4
  
  echo "==> Building Go project for linux/$target_arch (source: $go_source_file)"
  
  # Unset previous environment variables for clean build context
  unset GOOS
  unset GOARCH
  unset CGO_ENABLED
  unset CC
  unset CXX
  unset DOCKER_PLATFORM_ARG # Clear any previous platform arg
  
  local output_extension="so"
  local lib_prefix="lib"
  
  # Construct the full Go library name including OS and arch suffix
  local output_go_lib_name="${lib_prefix}${final_output_filename_base}_linux_${target_arch}.${output_extension}"
  # This is the path to the Go lib in the temporary directory
  local temp_go_lib_path="${temp_output_dir}/${output_go_lib_name}"
  
  # Ensure the temporary output directory exists
  mkdir -p "$temp_output_dir"
  
  local go_build_cmd="go build -buildmode=c-shared -o \"$temp_go_lib_path\" \"$GO_PACKAGE_BASE_PATH/$go_source_file\""
  
  export GOOS=linux
  export GOARCH="$target_arch"
  export CGO_ENABLED=1
  
  # Determine Docker platform for multi-arch builds
  case "$target_arch" in
    "amd64") DOCKER_PLATFORM_ARG="--platform linux/amd64" ;;
    "arm64") DOCKER_PLATFORM_ARG="--platform linux/arm64" ;;
    *) DOCKER_PLATFORM_ARG="" ;; # Fallback, should be handled by case above
  esac
  
  echo " (Using Docker $DOCKER_PLATFORM_ARG for Linux Go cross-compilation to provide libdbus-1-dev)"
  docker run --rm $DOCKER_PLATFORM_ARG -v "$(pwd)":/app -w /app golang:1.21-bullseye bash -c "\
    apt-get update && \
    apt-get install -y libdbus-1-dev && \
    export GOOS=linux && \
    export GOARCH=$target_arch && \
    export CGO_ENABLED=1 && \
    go build -buildmode=c-shared -o \"$temp_go_lib_path\" \"$GO_PACKAGE_BASE_PATH/$go_source_file\" \
    "
  # Move the generated header file to the bridge directory
  cp "${temp_go_lib_path%.so}.h" "./bridge/${lib_prefix}${final_output_filename_base}_linux_${target_arch}.h"
  cp "${temp_go_lib_path}" "./bridge/${temp_go_lib_path#./*/*/}"
  cp "${temp_go_lib_path}" "$OUTPUT_ROOT_DIR/${output_go_lib_name}"
}

# Function to build the C bridge shared library for Linux
# Args:
# $1: target_arch (e.g., "amd64", "arm64")
# $2: c_source_file_base (e.g., "bridge_linux_arm64.c")
# $3: go_lib_temp_path (full path to the compiled Go shared library in temp dir)
# $4: final_output_filename_base (e.g., "bridge")
build_bridge() {
  local target_arch=$1
  local c_source_file_base=$2
  local go_lib_temp_path=$3 # Path to the Go lib in the temp dir
  local final_output_filename_base=$4
  
  echo "==> Building C bridge for linux/$target_arch"
  
  # Unset previous environment variables for clean build context
  unset GOOS
  unset GOARCH
  unset CGO_ENABLED
  
  local compiler_package=""
  local compiler_exe=""
  local java_arch_suffix="" # Suffix for Java home directory
  
  local output_extension="so"
  local lib_prefix="lib"
  
  # Determine Docker platform and compiler for multi-arch builds
  case "$target_arch" in
  "amd64")
    DOCKER_PLATFORM_ARG="--platform linux/amd64"
    compiler_package="build-essential" # Provides gcc
    compiler_exe="gcc"
    java_arch_suffix="amd64"
    ;;
  "arm64")
    DOCKER_PLATFORM_ARG="--platform linux/arm64"
    compiler_package="build-essential gcc-aarch64-linux-gnu" # Provides aarch64-linux-gnu-gcc
    compiler_exe="aarch64-linux-gnu-gcc"
    java_arch_suffix="arm64"
    ;;
  *)
  echo "Unsupported architecture for Linux C bridge: $target_arch"
  exit 1
  ;;
  esac
  
  # Calculate variables to be passed into the Docker command
  local docker_cc_cmd="$compiler_exe"
  local docker_cxx_cmd="${compiler_exe/gcc/g++}" # Not strictly used but good for consistency
  local docker_java_home="/usr/lib/jvm/java-17-openjdk-${java_arch_suffix}"
  local docker_jni_include_linux_path="$docker_java_home/include/linux"
  
  local go_lib_name_for_linking_base=$(basename "$go_lib_temp_path")
  local go_lib_name_for_linking_stripped="${go_lib_name_for_linking_base%.*}" # Remove .so
  if [[ "$go_lib_name_for_linking_stripped" == lib* ]]; then
    go_lib_name_for_linking_stripped="${go_lib_name_for_linking_stripped#lib}" # Remove 'lib' prefix for -l flag
  fi
  local docker_go_lib_temp_dir=$(dirname "$go_lib_temp_path")
  
  # Construct the full C bridge library name including OS and arch suffix
  local output_bridge_lib_name="${lib_prefix}${final_output_filename_base}_linux_${target_arch}.${output_extension}"
  
  
  echo " (Using Docker $DOCKER_PLATFORM_ARG for Linux C bridge compilation)"
  docker run --rm $DOCKER_PLATFORM_ARG -v "$(pwd)":/app -v "$(pwd)/$OUTPUT_ROOT_DIR":/resource-lib -w /app golang:1.21-bullseye bash -c "\
    apt-get update && \
    apt-get install -y $compiler_package openjdk-17-jdk && \
    \
    export JAVA_HOME=\"$docker_java_home\" && \
    export PATH=\"\$JAVA_HOME/bin:\$PATH\" && \
    \
    CC_CMD=\"$docker_cc_cmd\" && \
    CXX_CMD=\"$docker_cxx_cmd\" && \
    JNI_INCLUDE_LINUX_PATH=\"$docker_jni_include_linux_path\" && \
    GO_LIB_TEMP_DIR=\"$docker_go_lib_temp_dir\" && \
    GO_LIB_NAME_FOR_LINKING=\"$go_lib_name_for_linking_stripped\" && \
    FINAL_BRIDGE_OUTPUT_NAME=\"$output_bridge_lib_name\" && \
    TARGET_ARCH_INNER=\"$target_arch\" && \
    \
    cd bridge && \
    \"\$CC_CMD\" -c -fPIC \"$c_source_file_base\" -o bridge_linux_\"\$TARGET_ARCH_INNER\".o \
    -I\"\$GO_LIB_TEMP_DIR\" -I. \
    -I\"\$JAVA_HOME/include\" \
    -I\"\$JNI_INCLUDE_LINUX_PATH\" && \
    \"\$CC_CMD\" -shared -o \"\$FINAL_BRIDGE_OUTPUT_NAME\" bridge_linux_\"\$TARGET_ARCH_INNER\".o \
    -L. -L\"\$GO_LIB_TEMP_DIR\" -l\"\$GO_LIB_NAME_FOR_LINKING\" && \
    echo \"C bridge compiled successfully: \$FINAL_BRIDGE_OUTPUT_NAME\" && \
    mv \"\$FINAL_BRIDGE_OUTPUT_NAME\" \"/resource-lib\" \
    "
}

# Cleanup function
cleanup() {
  echo "==> Cleaning up previous build artifacts..."
  rm -f "$OUTPUT_ROOT_DIR/*.so"
  rm -rf "$TMP_BUILD_DIR/linux*"
  rm -f ./bridge/*.h # Remove Go-generated headers that might be left in bridge/
  rm -f ./bridge/*.o # Remove object files from bridge/
  echo "Cleanup complete."
}

# --- Main Build Process ---

# Check and install dependencies
check_dependencies

# Clean up previous builds to ensure a fresh start
cleanup
# Ensure the root output directory exists for the final artifacts
mkdir -p "$OUTPUT_ROOT_DIR"

# --- Build Combinations ---

CURRENT_UNIX_TIMESTAMP=$(date +%s)

# Linux ARM64
LINUX_ARM64_TMP_DIR="$TMP_BUILD_DIR/linux-arm64"
build_go "arm64" "main_linux.go" "$LINUX_ARM64_TMP_DIR" "native_hook"
build_bridge "arm64" "bridge_linux_arm64.c" "$LINUX_ARM64_TMP_DIR/libnative_hook_linux_arm64.so" "bridge"



# Linux AMD64
LINUX_AMD64_TMP_DIR="$TMP_BUILD_DIR/linux-amd64"
build_go "amd64" "main_linux.go" "$LINUX_AMD64_TMP_DIR" "native_hook"
build_bridge "amd64" "bridge_linux_amd64.c" "$LINUX_AMD64_TMP_DIR/libnative_hook_linux_amd64.so" "bridge"

NOW_UNIX_TIMESTAMP=$(date +%s)

echo "==> All Linux builds completed. Final libraries are in: $OUTPUT_ROOT_DIR"
echo "==> Build duration: $(( (NOW_UNIX_TIMESTAMP - CURRENT_UNIX_TIMESTAMP) / 60 ))m $(( (NOW_UNIX_TIMESTAMP - CURRENT_UNIX_TIMESTAMP) % 60 ))s"