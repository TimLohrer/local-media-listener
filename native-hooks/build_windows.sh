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
# e.g., main_windows.go
GO_PACKAGE_BASE_PATH="."

# --- Pre-requisite Checks and Installations (Windows only) ---
check_dependencies() {
  echo "==> Checking build dependencies for Windows..."

  # Check for Zig (essential for cross-compilation to Windows)
  if ! command -v zig &> /dev/null; then
    echo "Error: 'zig' command not found. Please install Zig (https://ziglang.org/download/) and ensure it's in your PATH."
    exit 1
  else
    echo "'zig' is installed."
  fi

  # Check JAVA_HOME
  if [ -z "$JAVA_HOME" ]; then
    echo "Error: JAVA_HOME is not set. Please set it to your JDK installation path."
    exit 1
  else
    echo "JAVA_HOME is set to: $JAVA_HOME"
  fi

  echo "==> All Windows dependencies checked."
}


# --- Helper Functions ---

# Function to build the Go shared library for Windows
# Args:
#   $1: target_arch (e.g., "amd64", "arm64")
#   $2: go_source_file (e.g., "main_windows.go")
#   $3: temp_output_dir (where to place the compiled Go lib and its header temporarily)
#   $4: final_output_filename_base (e.g., "native_hook")
build_go() {
  local target_arch=$1
  local go_source_file=$2
  local temp_output_dir=$3
  local final_output_filename_base=$4

  echo "==> Building Go project for windows/$target_arch (source: $go_source_file)"

  # Unset previous environment variables for clean build context
  unset GOOS
  unset GOARCH
  unset CGO_ENABLED
  unset CC
  unset CXX

  local output_extension="dll"
  local lib_prefix=""

  # Construct the full Go library name including OS and arch suffix
  local output_go_lib_name="${lib_prefix}${final_output_filename_base}_windows_${target_arch}.${output_extension}"
  # This is the path to the Go lib in the temporary directory
  local temp_go_lib_path="${temp_output_dir}/${output_go_lib_name}"

  # Ensure the temporary output directory exists
  mkdir -p "$temp_output_dir"

  local go_build_cmd="go build -buildmode=c-shared -o \"$temp_go_lib_path\" \"$GO_PACKAGE_BASE_PATH/$go_source_file\""

  export GOOS=windows
  export GOARCH="$target_arch"
  export CGO_ENABLED=1
  # Use Zig for cross-compilation to Windows
  if [ "${target_arch}" == "arm64" ]; then
    export CC="zig cc -target arm-windows-gnu"
    export CXX="zig c++ -target arm-windows-gnu"
  else
    export CC="zig cc -target x86_64-windows-gnu"
    export CXX="zig c++ -target x86_64-windows-gnu"
  fi
  eval $go_build_cmd
  # Move the generated header file to the bridge directory
  cp "${temp_go_lib_path%.dll}.h" "./bridge/${lib_prefix}${final_output_filename_base}_windows_${target_arch}.h"
  cp "${temp_go_lib_path}" "./bridge/${temp_go_lib_path#./*/*/}"
}

# Function to build the C bridge shared library for Windows
# Args:
#   $1: target_arch (e.g., "amd64", "arm64")
#   $2: c_source_file_base (e.g., "bridge_windows_arm64.c")
#   $3: go_lib_temp_path (full path to the compiled Go shared library in temp dir)
#   $4: final_output_filename_base (e.g., "bridge")
build_bridge() {
  local target_arch=$1
  local c_source_file_base=$2
  local go_lib_temp_path=$3 # Path to the Go lib in the temp dir
  local final_output_filename_base=$4

  echo "==> Building C bridge for windows/$target_arch"

  # Unset previous environment variables for clean build context
  unset GOOS
  unset GOARCH
  unset CGO_ENABLED

  local jni_os_dir="$JAVA_HOME/include/win32"
  local compiler_exe="zig cc"
  if [ "${target_arch}" == "arm64" ]; then
      local compiler_target_flag="-target arm-windows-gnu"
  else 
      local compiler_target_flag="-target x86_64-windows-gnu"
  fi 

  local output_extension="dll"
  local lib_prefix=""

  # Construct the full C bridge library name including OS and arch suffix
  local output_bridge_lib_name="${lib_prefix}${final_output_filename_base}_windows_${target_arch}.${output_extension}"

  cd bridge

  # Compile the C source file into an object file
  local compile_cmd_full="$compiler_exe $compiler_target_flag -c -fPIC \"$c_source_file_base\" -o bridge_windows_${target_arch}.o -I\"$(dirname "$go_lib_temp_path")\" -I. -I\"$JAVA_HOME/include\" -I\"$jni_os_dir\""
  echo "  Compile command: $compile_cmd_full" # Debugging
  eval "$compile_cmd_full"

  # Extract the base name of the Go library without extension or 'lib' prefix for linking
  local go_lib_name_for_linking=$(basename "$go_lib_temp_path")
  go_lib_name_for_linking="${go_lib_name_for_linking%.*}" # Remove .so/.dylib/.dll
  if [[ "$go_lib_name_for_linking" == lib* ]]; then
    go_lib_name_for_linking="${go_lib_name_for_linking#lib}" # Remove 'lib' prefix for -l flag
  fi

  # Link the object file into a shared library
  local link_cmd_full="$compiler_exe $compiler_target_flag -shared -o \"$output_bridge_lib_name\" bridge_windows_${target_arch}.o -L. -l\"$go_lib_name_for_linking\""
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

# Windows ARM64
WINDOWS_ARM64_TMP_DIR="$TMP_BUILD_DIR/windows-arm64"
build_go "arm64" "main_windows.go" "$WINDOWS_ARM64_TMP_DIR" "native_hook"
build_bridge "arm64" "bridge_windows_arm64.c" "$WINDOWS_ARM64_TMP_DIR/native_hook_windows_arm64.dll" "bridge"

# Windows AMD64
WINDOWS_AMD64_TMP_DIR="$TMP_BUILD_DIR/windows-amd64"
build_go "amd64" "main_windows.go" "$WINDOWS_AMD64_TMP_DIR" "native_hook"
build_bridge "amd64" "bridge_windows_amd64.c" "$WINDOWS_AMD64_TMP_DIR/native_hook_windows_amd64.dll" "bridge"

echo "==> All Windows builds completed. Final libraries are in: $OUTPUT_ROOT_DIR"
