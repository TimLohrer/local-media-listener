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
  
  echo "==> All Linux dependencies checked."
}


# --- Helper Functions ---

# Function to build the Go static archive library for Linux.
# This function uses Docker to ensure the correct Go environment and CGO dependencies
# (like libdbus-1-dev) are available for cross-compilation.
# Args:
# $1: target_arch (e.g., "amd64", "arm64") - The target architecture for the Go library.
# $2: go_source_file (e.g., "main_linux.go") - The Go source file to compile.
# $3: temp_output_dir (where to place the compiled Go lib and its header temporarily) -
#     This is a path within the host filesystem that will be mounted into the Docker container.
# $4: final_output_filename_base (e.g., "native_hook") - The base name for the output library.
build_go() {
  local target_arch=$1
  local go_source_file=$2
  local temp_output_dir=$3
  local final_output_filename_base=$4
  
  echo "==> Building Go project for linux/$target_arch (source: $go_source_file)"
  
  # Unset previous environment variables to ensure a clean build context within the script.
  unset GOOS
  unset GOARCH
  unset CGO_ENABLED
  unset CC
  unset CXX
  unset DOCKER_PLATFORM_ARG # Clear any previous platform argument for Docker.
  
  local output_extension="a" # Static archive extension for Go.
  local lib_prefix="lib"     # Standard prefix for libraries.
  
  # Construct the full Go library name including OS and architecture suffix.
  local output_go_lib_name="${lib_prefix}${final_output_filename_base}_linux_${target_arch}.${output_extension}"
  # This is the full path to the Go archive within the temporary directory on the host.
  local temp_go_lib_path="${temp_output_dir}/${output_go_lib_name}"
  
  # Ensure the temporary output directory exists on the host filesystem.
  mkdir -p "$temp_output_dir"
  
  # Set Go environment variables for the host script, although the Docker command will
  # re-export them within the container for the actual build.
  export GOOS=linux
  export GOARCH="$target_arch"
  export CGO_ENABLED=1 # Enable CGO for static archive compilation.
  
  # Determine the Docker platform argument for multi-architecture builds.
  # This ensures the correct base image architecture is used within Docker.
  case "$target_arch" in
    "amd64") DOCKER_PLATFORM_ARG="--platform linux/amd64" ;;
    "arm64") DOCKER_PLATFORM_ARG="--platform linux/arm64" ;;
    *) DOCKER_PLATFORM_ARG="" ;; # Fallback, though cases above should cover supported architectures.
  esac
  
  echo " (Using Docker $DOCKER_PLATFORM_ARG for Linux Go cross-compilation to provide libdbus-1-dev)"
  
  # Run Docker to perform the Go build.
  # - --rm: Automatically remove the container when it exits.
  # - $DOCKER_PLATFORM_ARG: Specifies the target platform for the Docker image.
  # - -v "$(pwd)":/app: Mounts the current host directory into the container at /app.
  # - -w /app: Sets the working directory inside the container to /app.
  # - golang:1.21-bullseye: Uses a specific Go version image based on Debian Bullseye.
  # - bash -c "...": Executes a series of commands inside the container.
  docker run --rm $DOCKER_PLATFORM_ARG -v "$(pwd)":/app -w /app golang:1.21-bullseye bash -c "\
    apt-get update && \
    apt-get install -y libdbus-1-dev && \
    export GOOS=linux && \
    export GOARCH=$target_arch && \
    export CGO_ENABLED=1 && \
    # Build Go as a static archive (.a) instead of a shared library (.so).
    go build -buildmode=c-archive -o \"$temp_go_lib_path\" \"$GO_PACKAGE_BASE_PATH/$go_source_file\" \
    "
  
  # After the Go build in Docker, the .a and .h files are generated in the mounted
  # temporary directory on the host. We then copy the header to the 'bridge' directory.
  
  # Copy the generated header file (e.g., libnative_hook_linux_amd64.h) to the 'bridge' directory.
  # This header is needed by the C bridge to link with the Go functions.
  cp "${temp_go_lib_path%.a}.h" "./bridge/${lib_prefix}${final_output_filename_base}_linux_${target_arch}.h"
  
  # The Go static archive (.a) is an intermediate artifact and is not copied to the final
  # output directory or the 'bridge' directory as a standalone file. It will be linked
  # directly into the C bridge shared library.
  cp "${temp_go_lib_path}" "./bridge/${temp_go_lib_path#./*/*/}" # Copy to bridge directory.
}

# Function to build the C bridge shared library for Linux.
# This function now links the Go static archive directly into the C bridge.
# Args:
# $1: target_arch (e.g., "amd64", "arm64") - The target architecture for the C bridge.
# $2: c_source_file_base (e.g., "bridge_linux_arm64.c") - The C source file to compile.
# $3: go_lib_temp_path (full path to the compiled Go static archive in temp dir) -
#     This path is used for linking the C bridge against the Go library.
# $4: final_output_filename_base (e.g., "bridge") - The base name for the output C bridge library.
build_bridge() {
  local target_arch=$1
  local c_source_file_base=$2
  local go_lib_temp_path=$3 # Path to the Go static archive in the temp dir (on host, mounted to Docker).
  local final_output_filename_base=$4
  
  echo "==> Building C bridge for linux/$target_arch"
  
  # Unset previous environment variables for a clean build context.
  unset GOOS
  unset GOARCH
  unset CGO_ENABLED
  
  local compiler_package="" # Package name for the C compiler.
  local compiler_exe=""     # Executable name for the C compiler.
  local java_arch_suffix="" # Suffix used in Java home directory paths for different architectures.
  
  local output_extension="so" # Shared object extension for Linux.
  local lib_prefix="lib"     # Standard prefix for shared libraries.
  
  # Determine Docker platform, compiler, and Java architecture suffix based on target_arch.
  case "$target_arch" in
  "amd64")
    DOCKER_PLATFORM_ARG="--platform linux/amd64"
    compiler_package="build-essential" # Provides gcc for AMD64.
    compiler_exe="gcc"
    java_arch_suffix="amd64"
    ;;
  "arm64")
    DOCKER_PLATFORM_ARG="--platform linux/arm64"
    compiler_package="build-essential gcc-aarch64-linux-gnu" # Provides aarch64-linux-gnu-gcc for ARM64.
    compiler_exe="aarch64-linux-gnu-gcc"
    java_arch_suffix="arm64"
    ;;
  *)
  echo "Unsupported architecture for Linux C bridge: $target_arch"
  exit 1
  ;;
  esac
  
  # Calculate variables that will be passed into the Docker command.
  # These are used within the container's build process.
  local docker_cc_cmd="$compiler_exe"
  local docker_cxx_cmd="${compiler_exe/gcc/g++}" # Derive C++ compiler from C compiler.
  local docker_java_home="/usr/lib/jvm/java-17-openjdk-${java_arch_suffix}" # Path to Java home in Docker.
  local docker_jni_include_linux_path="$docker_java_home/include/linux" # Path to JNI Linux-specific headers.
  
  # Extract the base name of the Go static archive for linking (e.g., "native_hook_linux_amd64").
  local go_lib_name_for_linking_base=$(basename "$go_lib_temp_path")
  local go_lib_name_for_linking_stripped="${go_lib_name_for_linking_base%.*}" # Remove .a extension.
  if [[ "$go_lib_name_for_linking_stripped" == lib* ]]; then
    go_lib_name_for_linking_stripped="${go_lib_name_for_linking_stripped#lib}" # Remove 'lib' prefix for -l flag.
  fi
  # Get the directory of the Go static archive within the mounted Docker volume.
  local docker_go_lib_temp_dir=$(dirname "$go_lib_temp_path")
  
  # Construct the full C bridge library name including OS and architecture suffix.
  local output_bridge_lib_name="${lib_prefix}${final_output_filename_base}_linux_${target_arch}.${output_extension}"
  
  echo " (Using Docker $DOCKER_PLATFORM_ARG for Linux C bridge compilation)"
  
  # Run Docker to perform the C bridge build.
  # -v "$(pwd)":/app: Mounts the current host directory into the container at /app.
  # -v "$(pwd)/$OUTPUT_ROOT_DIR":/resource-lib: Mounts the final output directory for artifacts.
  # The C bridge compilation involves:
  # 1. Installing necessary build tools (compiler, OpenJDK for JNI headers).
  # 2. Setting JAVA_HOME and PATH.
  # 3. Compiling the C source file into an object file (.o).
  #    - -c: Compile only, do not link.
  #    - -fPIC: Generate position-independent code (required for shared libraries).
  #    - -I: Include directories for headers (Go-generated, current, JNI).
  # 4. Linking the object file into a shared library (.so).
  #    - -shared: Create a shared library.
  #    - -L: Library search paths (current, Go lib temp dir).
  #    - -l: Link against the Go static archive (stripped name).
  # 5. Moving the final compiled C bridge library to the designated output directory.
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

# Cleanup function to remove previously built artifacts and temporary files.
cleanup() {
  echo "==> Cleaning up previous build artifacts..."
  # Remove all .so files from the final output directory (these will now only be the consolidated bridge .so).
  rm -f "$OUTPUT_ROOT_DIR/*.so"
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

# --- Build Combinations ---

# Build for Linux ARM64
LINUX_ARM64_TMP_DIR="$TMP_BUILD_DIR/linux-arm64"
# Build the Go static archive (.a)
build_go "arm64" "main_linux.go" "$LINUX_ARM64_TMP_DIR" "native_hook"
# Build the C bridge shared library (.so), linking the Go static archive into it.
build_bridge "arm64" "bridge_linux_arm64.c" "$LINUX_ARM64_TMP_DIR/libnative_hook_linux_arm64.a" "bridge"

# Build for Linux AMD64
LINUX_AMD64_TMP_DIR="$TMP_BUILD_DIR/linux-amd64"
# Build the Go static archive (.a)
build_go "amd64" "main_linux.go" "$LINUX_AMD64_TMP_DIR" "native_hook"
# Build the C bridge shared library (.so), linking the Go static archive into it.
build_bridge "amd64" "bridge_linux_amd64.c" "$LINUX_AMD64_TMP_DIR/libnative_hook_linux_amd64.a" "bridge"

# Record the end time and calculate build duration.
NOW_UNIX_TIMESTAMP=$(date +%s)

echo "==> All Linux builds completed. Final consolidated libraries are in: $OUTPUT_ROOT_DIR"
echo "==> Build duration: $(( (NOW_UNIX_TIMESTAMP - CURRENT_UNIX_TIMESTAMP) / 60 ))m $(( (NOW_UNIX_TIMESTAMP - CURRENT_UNIX_TIMESTAMP) % 60 ))s"
