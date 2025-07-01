#!/bin/bash

set -e

# --- Configuration ---
# Root output directory for all compiled libraries (relative to script location)
# All final artifacts will be placed directly in this folder with OS/ARCH suffixes.
OUTPUT_ROOT_DIR="../src/main/resources/lib"

# Temporary build directory for intermediate Go libs and headers (relative to script location)
TMP_BUILD_DIR="./tmp_native_build"

# Go package path (relative to this script's location)
# This assumes your Go entry point files are directly in the current directory
# e.g., main_darwin.go
GO_PACKAGE_BASE_PATH="."

# --- Pre-requisite Checks and Installations (macOS only) ---
check_and_install_brew_package() {
  local package_name=$1
  if ! command -v "$package_name" &> /dev/null; then
    echo "Brew package '$package_name' not found. Attempting to install..."
    if brew install "$package_name"; then
      echo "'$package_name' installed successfully."
    else
      echo "Error: Failed to install '$package_name' using Homebrew. Please install it manually."
      exit 1
    fi
  else
    echo "'$package_name' is already installed."
  fi
}

check_dependencies() {
  echo "==> Checking build dependencies for macOS..."

  # Check for Homebrew
  if ! command -v brew &> /dev/null; then
    echo "Homebrew not found. Please install Homebrew (https://brew.sh/) to proceed with automatic dependency installation."
    exit 1
  fi

  # No need for zig for macOS native/cross-compilation with clang
  # check_and_install_brew_package "zig"

  # Check JAVA_HOME
  if [ -z "$JAVA_HOME" ]; then
    echo "Error: JAVA_HOME is not set. Please set it to your JDK installation path."
    exit 1
  else
    echo "JAVA_HOME is set to: $JAVA_HOME"
  fi

  echo "==> All macOS dependencies checked."
}


# --- Helper Functions ---

# Function to build the Go shared library for macOS
# Args:
#   $1: target_arch (e.g., "amd64", "arm64")
#   $2: go_source_file (e.g., "main_darwin.go")
#   $3: temp_output_dir (where to place the compiled Go lib and its header temporarily)
#   $4: final_output_filename_base (e.g., "native_hook")
build_go() {
  local target_arch=$1
  local go_source_file=$2
  local temp_output_dir=$3
  local final_output_filename_base=$4
  
  echo "==> Building Go library for darwin/$target_arch..."
  
  export GOOS=darwin
  export GOARCH="$target_arch"
  export CGO_ENABLED=1
  
  local temp_go_lib_path="${temp_output_dir}/lib${final_output_filename_base}_darwin_${target_arch}.dylib"
  mkdir -p "$temp_output_dir"
  
  CURRENT_ARCH=$(uname -m)
  if [[ "$target_arch" == "amd64" && "$CURRENT_ARCH" == "arm64" ]]; then
    export CC="clang -target x86_64-apple-darwin"
    export CXX="clang++ -target x86_64-apple-darwin"
  elif [[ "$target_arch" == "arm64" && "$CURRENT_ARCH" == "x86_64" ]]; then
    export CC="clang -target arm64-apple-darwin"
    export CXX="clang++ -target arm64-apple-darwin"
  fi
  
  go build -buildmode=c-shared -o "$temp_go_lib_path" "$GO_PACKAGE_BASE_PATH/$go_source_file"
  
  cp "${temp_go_lib_path%.dylib}.h" "./bridge/lib${final_output_filename_base}_darwin_${target_arch}.h"
  cp "$temp_go_lib_path" "./bridge/"
  cp "$temp_go_lib_path" "$OUTPUT_ROOT_DIR/"
}

# Function to build the C bridge shared library for macOS
# Args:
#   $1: target_arch (e.g., "amd64", "arm64")
#   $2: c_source_file_base (e.g., "bridge_darwin_arm64.c")
#   $3: go_lib_temp_path (full path to the compiled Go shared library in temp dir)
#   $4: final_output_filename_base (e.g., "bridge")
build_bridge() {
  local target_arch=$1
  local c_source_file_base=$2
  local go_lib_temp_path=$3
  local final_output_filename_base=$4
  
  echo "==> Building C bridge for darwin/$target_arch..."
  
  local jni_os_dir="$JAVA_HOME/include/darwin"
  local compiler_target_flag=""
  
  CURRENT_ARCH=$(uname -m)
  if [[ "$target_arch" == "amd64" && "$CURRENT_ARCH" == "arm64" ]]; then
    compiler_target_flag="-target x86_64-apple-darwin"
  elif [[ "$target_arch" == "arm64" && "$CURRENT_ARCH" == "x86_64" ]]; then
    compiler_target_flag="-target arm64-apple-darwin"
  else
    compiler_target_flag="-arch ${target_arch/amd64/x86_64}"
  fi
  
  local output_bridge_lib_name="lib${final_output_filename_base}_darwin_${target_arch}.dylib"
  
  cd bridge
  
  clang $compiler_target_flag -c -fPIC "$c_source_file_base" -o "bridge_darwin_${target_arch}.o" \
    -I"$(dirname "$go_lib_temp_path")" -I. -I"$JAVA_HOME/include" -I"$jni_os_dir"
    
  local go_lib_name_for_linking=$(basename "${go_lib_temp_path%.*}")
  go_lib_name_for_linking="${go_lib_name_for_linking#lib}"
    
  clang $compiler_target_flag -shared -o "$output_bridge_lib_name" "bridge_darwin_${target_arch}.o" \
    -L. -l"$go_lib_name_for_linking"
    
  mkdir -p "../$OUTPUT_ROOT_DIR"
  mv "$output_bridge_lib_name" "../$OUTPUT_ROOT_DIR/"
  
  cd ..
}

# Cleanup function
cleanup() {
  echo "==> Cleaning up..."
  rm -f "$OUTPUT_ROOT_DIR"/*.dylib
  rm -rf "$TMP_BUILD_DIR/darwin"*
  rm -f ./bridge/*.h ./bridge/*.o
}

# --- Main Build Process ---

# Check and install dependencies
check_dependencies

# Clean up previous builds to ensure a fresh start
cleanup

# Ensure the root output directory exists for the final artifacts
mkdir -p "$OUTPUT_ROOT_DIR"

# --- Parallel Build Combinations ---

CURRENT_UNIX_TIMESTAMP=$(date +%s)

# macOS ARM64 (Apple Silicon) in background
(
  MACOS_ARM64_TMP_DIR="$TMP_BUILD_DIR/darwin-arm64"
  build_go "arm64" "main_darwin.go" "$MACOS_ARM64_TMP_DIR" "native_hook"
  build_bridge "arm64" "bridge_darwin_arm64.c" "$MACOS_ARM64_TMP_DIR/libnative_hook_darwin_arm64.dylib" "bridge"
) &

# macOS AMD64 (Intel Mac) in background
(
  MACOS_AMD64_TMP_DIR="$TMP_BUILD_DIR/darwin-amd64"
  build_go "amd64" "main_darwin.go" "$MACOS_AMD64_TMP_DIR" "native_hook"
  build_bridge "amd64" "bridge_darwin_amd64.c" "$MACOS_AMD64_TMP_DIR/libnative_hook_darwin_amd64.dylib" "bridge"
) &

# Wait for all background jobs to finish
wait

NOW_UNIX_TIMESTAMP=$(date +%s)

echo "==> All macOS builds completed. Final libraries are in: $OUTPUT_ROOT_DIR"
echo "==> Build duration: $(( (NOW_UNIX_TIMESTAMP - CURRENT_UNIX_TIMESTAMP) / 60 ))m $(( (NOW_UNIX_TIMESTAMP - CURRENT_UNIX_TIMESTAMP) % 60 ))s"
