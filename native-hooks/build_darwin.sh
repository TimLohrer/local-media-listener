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

  echo "==> Building Go project for darwin/$target_arch (source: $go_source_file)"

  # Unset previous environment variables for clean build context
  unset GOOS
  unset GOARCH
  unset CGO_ENABLED
  unset CC
  unset CXX

  local output_extension="dylib"
  local lib_prefix="lib"

  # Construct the full Go library name including OS and arch suffix
  local output_go_lib_name="${lib_prefix}${final_output_filename_base}_darwin_${target_arch}.${output_extension}"
  # This is the path to the Go lib in the temporary directory
  local temp_go_lib_path="${temp_output_dir}/${output_go_lib_name}"

  # Ensure the temporary output directory exists
  mkdir -p "$temp_output_dir"

  local go_build_cmd="go build -buildmode=c-shared -o \"$temp_go_lib_path\" \"$GO_PACKAGE_BASE_PATH/$go_source_file\""

  export GOOS=darwin
  export GOARCH="$target_arch"
  export CGO_ENABLED=1
  
  CURRENT_ARCH=$(uname -m)
  if [[ "$target_arch" == "amd64" && "$CURRENT_ARCH" == "arm64" ]]; then
    # Cross-compiling from arm64 to amd64 using clang
    export CC="clang -target x86_64-apple-darwin"
    export CXX="clang++ -target x86_64-apple-darwin"
  elif [[ "$target_arch" == "arm64" && "$CURRENT_ARCH" == "x86_64" ]]; then
    # Cross-compiling from x86_64 to arm64 using clang
    export CC="clang -target arm64-apple-darwin"
    export CXX="clang++ -target arm64-apple-darwin"
  else
    # Native compilation (e.g., arm64 on arm64, or amd64 on amd64)
    # Use default clang for native builds
    unset CC
    unset CXX
  fi
  eval $go_build_cmd
  # Move the generated header file to the bridge directory
  cp "${temp_go_lib_path%.dylib}.h" "./bridge/${lib_prefix}${final_output_filename_base}_darwin_${target_arch}.h"
  cp "${temp_go_lib_path}" "./bridge/${temp_go_lib_path#./*/*/}"
  cp "${temp_go_lib_path}" "$OUTPUT_ROOT_DIR/${output_go_lib_name}"
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
  local go_lib_temp_path=$3 # Path to the Go lib in the temp dir
  local final_output_filename_base=$4

  echo "==> Building C bridge for darwin/$target_arch"

  # Unset previous environment variables for clean build context
  unset GOOS
  unset GOARCH
  unset CGO_ENABLED

  local jni_os_dir="$JAVA_HOME/include/darwin"
  local compiler_exe="clang" # Always use clang for macOS
  local compiler_target_flag="" # The -target flag for clang

  local output_extension="dylib"
  local lib_prefix="lib"
  
  # Determine if we are cross-compiling or native compiling on macOS
  CURRENT_ARCH=$(uname -m)

  if [[ "$target_arch" == "amd64" && "$CURRENT_ARCH" == "arm64" ]]; then
    # Cross-compiling from arm64 to amd64
    compiler_target_flag="-target x86_64-apple-darwin"
  elif [[ "$target_arch" == "arm64" && "$CURRENT_ARCH" == "x86_64" ]]; then
    # Cross-compiling from x86_64 to arm64
    compiler_target_flag="-target arm64-apple-darwin"
  else
    # Native compilation (e.g., arm64 on arm64, or amd64 on amd64)
    # Use -arch for native builds with clang
    if [ "$target_arch" == "amd64" ]; then
      compiler_target_flag="-arch x86_64"
    else
      compiler_target_flag="-arch arm64"
    fi
  fi

  # Construct the full C bridge library name including OS and arch suffix
  local output_bridge_lib_name="${lib_prefix}${final_output_filename_base}_darwin_${target_arch}.${output_extension}"

  cd bridge

  # Compile the C source file into an object file
  local compile_cmd_full="$compiler_exe $compiler_target_flag -c -fPIC \"$c_source_file_base\" -o bridge_darwin_${target_arch}.o -I\"$(dirname "$go_lib_temp_path")\" -I. -I\"$JAVA_HOME/include\" -I\"$jni_os_dir\""
  echo "  Compile command: $compile_cmd_full" # Debugging
  eval "$compile_cmd_full"

  # Extract the base name of the Go library without extension or 'lib' prefix for linking
  local go_lib_name_for_linking=$(basename "$go_lib_temp_path")
  go_lib_name_for_linking="${go_lib_name_for_linking%.*}" # Remove .so/.dylib/.dll
  if [[ "$go_lib_name_for_linking" == lib* ]]; then
    go_lib_name_for_linking="${go_lib_name_for_linking#lib}" # Remove 'lib' prefix for -l flag
  fi

  # Link the object file into a shared library
  local link_cmd_full="$compiler_exe $compiler_target_flag -shared -o \"$output_bridge_lib_name\" bridge_darwin_${target_arch}.o -L. -l\"$go_lib_name_for_linking\""
  echo "  Link command: $link_cmd_full" # Debugging
  eval "$link_cmd_full"

  # Move the compiled C bridge library to the final output directory
  mkdir -p "../$OUTPUT_ROOT_DIR" # Ensure target directory exists
  mv "$output_bridge_lib_name" "../$OUTPUT_ROOT_DIR/"

  cd .. # Go back to original script directory
}

# Cleanup function
cleanup() {
  echo "==> Cleaning up previous build artifacts..."
  rm -rf "$OUTPUT_ROOT_DIR"
  rm -rf "$TMP_BUILD_DIR" # Remove temporary build directory
  rm -f ./bridge/*.h # Remove Go-generated headers that might be left in bridge/
  rm -f  ./bridge/*.o # Remove object files from bridge/
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

# macOS ARM64 (Apple Silicon)
MACOS_ARM64_TMP_DIR="$TMP_BUILD_DIR/darwin-arm64"
build_go "arm64" "main_darwin.go" "$MACOS_ARM64_TMP_DIR" "native_hook"
build_bridge "arm64" "bridge_darwin_arm64.c" "$MACOS_ARM64_TMP_DIR/libnative_hook_darwin_arm64.dylib" "bridge"

# macOS AMD64 (Intel Mac)
MACOS_AMD64_TMP_DIR="$TMP_BUILD_DIR/darwin-amd64"
build_go "amd64" "main_darwin.go" "$MACOS_AMD64_TMP_DIR" "native_hook"
build_bridge "amd64" "bridge_darwin_amd64.c" "$MACOS_AMD64_TMP_DIR/libnative_hook_darwin_amd64.dylib" "bridge"

echo "==> All macOS builds completed. Final libraries are in: $OUTPUT_ROOT_DIR"
