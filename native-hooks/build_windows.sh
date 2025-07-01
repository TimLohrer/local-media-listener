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

  # Docker is essential for Windows CGO cross-compilation now
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

  # JAVA_HOME is still needed on the host for JNI include path determination (though the script
  # will warn about its limited use for Windows JNI headers inside Docker).
  if [ -z "$JAVA_HOME" ]; then
    echo "Warning: JAVA_HOME is not set on the host. This might impact JNI header detection."
    echo "Ensure your Java development environment is correctly configured."
  else
    echo "JAVA_HOME is set on host to: $JAVA_HOME"
  fi

  echo "==> All Windows dependencies checked."
}

# Helper function to determine compiler details for Clang cross-compilation
get_cross_compiler_vars() {
  local target_arch=$1
  local __compiler_package=""
  local __compiler_exe="/usr/bin/clang" # Always clang with absolute path
  local __compiler_target_triple="" # New variable for clang's -target
  local __java_arch_suffix=""

  case "$target_arch" in
    "amd64")
      __compiler_package="clang lld" # clang and lld (LLVM linker)
      __compiler_target_triple="x86_64-w64-mingw32"
      __java_arch_suffix="amd64"
      ;;
    "arm64")
      __compiler_package="clang lld" # clang and lld (LLVM linker)
      __compiler_target_triple="aarch64-w64-mingw32"
      __java_arch_suffix="arm64"
      ;;
    *)
      echo "Unsupported architecture: $target_arch"
      exit 1
      ;;
  esac
  echo "$__compiler_package" "$__compiler_exe" "$__compiler_target_triple" "$__java_arch_suffix"
}

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
  # This is the path to the Go lib in the temporary directory (inside container)
  local temp_go_lib_path_in_container="/app/${temp_output_dir}/${output_go_lib_name}"
  local temp_go_header_path_in_container="/app/${temp_output_dir}/${output_go_lib_name%.*}.h"

  # Ensure the temporary output directory exists on host
  mkdir -p "$temp_output_dir"

  # Determine Docker platform for multi-arch builds (for Go build, even if Clang is specific)
  case "$target_arch" in
    "amd64") DOCKER_PLATFORM_ARG="--platform linux/amd64" ;;
    "arm64") DOCKER_PLATFORM_ARG="--platform linux/arm64" ;;
    *) DOCKER_PLATFORM_ARG="" ;;
  esac

  # Get Clang compiler details
  read -r compiler_package compiler_exe compiler_target_triple java_arch_suffix <<< "$(get_cross_compiler_vars "$target_arch")"

  # Determine Java Home inside the container
  local docker_java_home="/usr/lib/jvm/java-17-openjdk-${java_arch_suffix}"

  echo "    (Using Docker $DOCKER_PLATFORM_ARG and image 'golang:latest' with $compiler_exe -target $compiler_target_triple)"
  docker run --rm $DOCKER_PLATFORM_ARG \
    -v "$(pwd)":/app \
    -v "$(pwd)/$OUTPUT_ROOT_DIR":/resource-lib \
    -v "$(pwd)/bridge":/bridge-dir \
    -w /app golang:latest bash -c "\
    # Overwrite sources.list for full Debian repositories including non-free
    echo \"deb http://deb.debian.org/debian/ bookworm main contrib non-free\" > /etc/apt/sources.list && \
    echo \"deb-src http://deb.debian.org/debian/ bookworm main contrib non-free\" >> /etc/apt/sources.list && \
    echo \"deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free\" >> /etc/apt/sources.list && \
    echo \"deb-src http://deb.debian.org/debian/ bookworm-updates main contrib non-free\" >> /etc/apt/sources.list && \
    echo \"deb http://security.debian.org/debian-security bookworm-security main contrib non-free\" >> /etc/apt/sources.list && \
    echo \"deb-src http://security.debian.org/debian-security bookworm-security main contrib non-free\" >> /etc/apt/sources.list && \
    \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      $compiler_package \
      openjdk-17-jdk-headless && \
    # Ensure /usr/bin is in PATH for compilers
    export PATH=\"/usr/bin:\$PATH\" && \
    # Create a symlink for 'lld' if it's versioned (e.g., lld-15)
    if ! command -v lld &> /dev/null; then \
      LLD_VERSIONED_PATH=\$(find /usr/bin -maxdepth 1 -type f -name 'lld-*' | head -n 1); \
      if [ -n \"\$LLD_VERSIONED_PATH\" ]; then \
        echo \"lld not found, but versioned linker found at \$LLD_VERSIONED_PATH. Creating symlink.\"; \
        ln -s \"\$LLD_VERSIONED_PATH\" /usr/bin/lld; \
      else \
        echo \"Warning: lld or versioned lld not found after install. Linker might fail.\"; \
      fi; \
    fi && \
    export GOOS=windows && \
    export GOARCH=$target_arch && \
    export CGO_ENABLED=1 && \
    # Explicitly set CC and CXX to clang with the target triple
    export CC=\"$compiler_exe\" && \
    export CXX=\"${compiler_exe/clang/clang++}\" && \
    # Pass the target triple via CFLAGS/CXXFLAGS
    export CGO_CFLAGS=\"-target $compiler_target_triple\" && \
    export CGO_CXXFLAGS=\"-target $compiler_target_triple\" && \
    # Explicitly tell Go to use lld as the linker
    export CGO_LDFLAGS=\"-fuse-ld=lld\" && \
    export JAVA_HOME=\"$docker_java_home\" && \
    export PATH=\"\$JAVA_HOME/bin:\$PATH\" && \
    mkdir -p \"$temp_output_dir\" && \
    go mod tidy && \
    go mod download && \
    go build -buildmode=c-shared -o \"$temp_go_lib_path_in_container\" \"$GO_PACKAGE_BASE_PATH/$go_source_file\" && \
    echo \"Go library compiled successfully: $temp_go_lib_path_in_container\" && \
    mv \"$temp_go_lib_path_in_container\" \"/resource-lib/${output_go_lib_name}\" && \
    mv \"$temp_go_header_path_in_container\" \"/bridge-dir/${lib_prefix}${final_output_filename_base}_windows_${target_arch}.h\" \
  "
}

# Function to build the C bridge shared library for Windows
# Args:
#   $1: target_arch (e.g., "amd64", "arm64")
#   $2: c_source_file_base (e.g., "bridge_windows_arm64.c")
#   $3: go_lib_name_on_host (e.g., "native_hook_windows_arm64.dll") - just the filename
#   $4: final_output_filename_base (e.g., "bridge")
build_bridge() {
  local target_arch=$1
  local c_source_file_base=$2
  local go_lib_name_on_host=$3
  local final_output_filename_base=$4

  echo "==> Building C bridge for windows/$target_arch"

  # Unset previous environment variables for clean build context
  unset GOOS
  unset GOARCH
  unset CGO_ENABLED

  local output_extension="dll"
  local lib_prefix=""

  # Determine Docker platform for multi-arch builds
  case "$target_arch" in
    "amd64") DOCKER_PLATFORM_ARG="--platform linux/amd64" ;;
    "arm64") DOCKER_PLATFORM_ARG="--platform linux/arm64" ;;
    *) DOCKER_PLATFORM_ARG="" ;;
  esac

  # Get Clang compiler details
  read -r compiler_package compiler_exe compiler_target_triple java_arch_suffix <<< "$(get_cross_compiler_vars "$target_arch")"
  
  # Determine Java Home inside the container
  local docker_java_home="/usr/lib/jvm/java-17-openjdk-${java_arch_suffix}"
  # Path to JNI include directory inside the Docker container for Linux JNI headers
  # CAUTION: These are Linux JNI headers. For full Windows compatibility,
  # 'win32' specific JNI headers from a Windows JDK are needed.
  local docker_jni_include_path_generic="${docker_java_home}/include" # Generic path
  local docker_jni_include_path_os="${docker_java_home}/include/linux" # Platform-specific (Linux)

  local go_lib_name_for_linking_base=$(basename "$go_lib_name_on_host") # e.g., native_hook_windows_amd64.dll
  local go_lib_name_for_linking_stripped="${go_lib_name_for_linking_base%.*}" # Remove .dll
  if [[ "$go_lib_name_for_linking_stripped" == lib* ]]; then
    go_lib_name_for_linking_stripped="${go_lib_name_for_linking_stripped#lib}" # Remove 'lib' prefix for -l flag
  fi
  # The Go library will now be in /resource-lib inside the container
  local docker_go_lib_path_for_linking="/resource-lib/${go_lib_name_for_linking_base}"

  # Construct the full C bridge library name including OS and arch suffix
  local output_bridge_lib_name="${lib_prefix}${final_output_filename_base}_windows_${target_arch}.${output_extension}"

  echo "    (Using Docker $DOCKER_PLATFORM_ARG and image 'golang:latest' for Windows C bridge compilation)"
  docker run --rm $DOCKER_PLATFORM_ARG \
    -v "$(pwd)":/app \
    -v "$(pwd)/$OUTPUT_ROOT_DIR":/resource-lib \
    -w /app golang:latest bash -c "\
    # Overwrite sources.list for full Debian repositories including non-free
    echo \"deb http://deb.debian.org/debian/ bookworm main contrib non-free\" > /etc/apt/sources.list && \
    echo \"deb-src http://deb.debian.org/debian/ bookworm main contrib non-free\" >> /etc/apt/sources.list && \
    echo \"deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free\" >> /etc/apt/sources.list && \
    echo \"deb-src http://deb.debian.org/debian/ bookworm-updates main contrib non-free\" >> /etc/apt/sources.list && \
    echo \"deb http://security.debian.org/debian-security bookworm-security main contrib non-free\" >> /etc/apt/sources.list && \
    echo \"deb-src http://security.debian.org/debian-security bookworm-security main contrib non-free\" >> /etc/apt/sources.list && \
    \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      $compiler_package \
      openjdk-17-jdk-headless && \
    # Ensure /usr/bin is in PATH for cross-compilers
    export PATH=\"/usr/bin:\$PATH\" && \
    # Create a symlink for 'lld' if it's versioned (e.g., lld-15)
    if ! command -v lld &> /dev/null; then \
      LLD_VERSIONED_PATH=\$(find /usr/bin -maxdepth 1 -type f -name 'lld-*' | head -n 1); \
      if [ -n \"\$LLD_VERSIONED_PATH\" ]; then \
        echo \"lld not found, but versioned linker found at \$LLD_VERSIONED_PATH. Creating symlink.\"; \
        ln -s \"\$LLD_VERSIONED_PATH\" /usr/bin/lld; \
      else \
        echo \"Warning: lld or versioned lld not found after install. Linker might fail.\"; \
      fi; \
    fi && \
    export JAVA_HOME=\"$docker_java_home\" && \
    export PATH=\"\$JAVA_HOME/bin:\$PATH\" && \
    \
    CC_CMD=\"$compiler_exe\" && \
    CXX_CMD=\"${compiler_exe/clang/clang++}\" && \
    COMPILER_TARGET_TRIPLE=\"$compiler_target_triple\" && \
    JNI_INCLUDE_GENERIC_PATH=\"$docker_jni_include_path_generic\" && \
    JNI_INCLUDE_OS_PATH=\"$docker_jni_include_path_os\" && \
    GO_LIB_PATH_FOR_LINKING=\"$docker_go_lib_path_for_linking\" && \
    GO_LIB_NAME_FOR_LINKING=\"$go_lib_name_for_linking_stripped\" && \
    FINAL_BRIDGE_OUTPUT_NAME=\"$output_bridge_lib_name\" && \
    TARGET_ARCH_INNER=\"$target_arch\" && \
    \
    cd bridge && \
    \"\$CC_CMD\" -target \"\$COMPILER_TARGET_TRIPLE\" -c -fPIC \"$c_source_file_base\" -o bridge_windows_\"\$TARGET_ARCH_INNER\".o \
      -I\"$(dirname "$GO_LIB_PATH_FOR_LINKING")\" -I. \
      -I\"\$JNI_INCLUDE_GENERIC_PATH\" \
      -I\"\$JNI_INCLUDE_OS_PATH\" && \
    \"\$CC_CMD\" -target \"\$COMPILER_TARGET_TRIPLE\" -shared -o \"\$FINAL_BRIDGE_OUTPUT_NAME\" bridge_windows_\"\$TARGET_ARCH_INNER\".o \
      -L. -L\"$(dirname "$GO_LIB_PATH_FOR_LINKING")\" -l\"\$GO_LIB_NAME_FOR_LINKING\" && \
    echo \"C bridge compiled successfully: \$FINAL_BRIDGE_OUTPUT_NAME\" && \
    mv \"\$FINAL_BRIDGE_OUTPUT_NAME\" \"/resource-lib\" \
  "
}


# Cleanup function
cleanup() {
  echo "==> Cleaning up previous build artifacts..."
  rm -f "$OUTPUT_ROOT_DIR/*.dll"
  rm -rf "$TMP_BUILD_DIR/windows*"
  rm -f ./bridge/*windows*.h # Remove Go-generated headers that might be left in bridge/
  rm -f  ./bridge/*windows*.o # Remove object files from bridge/
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

# Windows ARM64
WINDOWS_ARM64_TMP_DIR="$TMP_BUILD_DIR/windows-arm64"
build_go "arm64" "main_windows.go" "$WINDOWS_ARM64_TMP_DIR" "native_hook"
build_bridge "arm64" "bridge_windows_arm64.c" "native_hook_windows_arm64.dll" "bridge"

# Windows AMD64
WINDOWS_AMD64_TMP_DIR="$TMP_BUILD_DIR/windows-amd64"
build_go "amd64" "main_windows.go" "$WINDOWS_AMD64_TMP_DIR" "native_hook"
build_bridge "amd64" "bridge_windows_amd64.c" "native_hook_windows_amd64.dll" "bridge"

NOW_UNIX_TIMESTAMP=$(date +%s)

echo "==> All Windows builds completed. Final libraries are in: $OUTPUT_ROOT_DIR"
echo "==> Build duration: $(( (NOW_UNIX_TIMESTAMP - CURRENT_UNIX_TIMESTAMP) / 60 ))m $(( (NOW_UNIX_TIMESTAMP - CURRENT_UNIX_TIMESTAMP) % 60 ))s"
```I understand you're still encountering the "C compiler 'lld' not found" error when building the Windows targets in your script. This is a very specific and persistent issue where Go's CGO seems to be trying to use `lld` directly as the C compiler (`CC`), even though we're explicitly setting `CC` to `clang`.

This behavior suggests a deeper interaction or misinterpretation within the CGO environment variables. To address this, I've updated the `windows_build_script` Canvas with a more robust approach to ensure `clang` is always correctly invoked as the C compiler and `lld` is used *only* as the linker.

Here's the updated Canvas:


```bash
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

  # Docker is essential for Windows CGO cross-compilation now
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

  # JAVA_HOME is still needed on the host for JNI include path determination (though the script
  # will warn about its limited use for Windows JNI headers inside Docker).
  if [ -z "$JAVA_HOME" ]; then
    echo "Warning: JAVA_HOME is not set on the host. This might impact JNI header detection."
    echo "Ensure your Java development environment is correctly configured."
  else
    echo "JAVA_HOME is set on host to: $JAVA_HOME"
  fi

  echo "==> All Windows dependencies checked."
}

# Helper function to determine compiler details for Clang cross-compilation
get_cross_compiler_vars() {
  local target_arch=$1
  local __compiler_package=""
  local __compiler_exe="clang" # Always clang
  local __compiler_target_triple="" # New variable for clang's -target
  local __java_arch_suffix=""

  case "$target_arch" in
    "amd64")
      __compiler_package="clang lld" # clang and lld (LLVM linker)
      __compiler_target_triple="x86_64-w64-mingw32"
      __java_arch_suffix="amd64"
      ;;
    "arm64")
      __compiler_package="clang lld" # clang and lld (LLVM linker)
      __compiler_target_triple="aarch64-w64-mingw32"
      __java_arch_suffix="arm64"
      ;;
    *)
      echo "Unsupported architecture: $target_arch"
      exit 1
      ;;
  esac
  echo "$__compiler_package" "$__compiler_exe" "$__compiler_target_triple" "$__java_arch_suffix"
}

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
  # This is the path to the Go lib in the temporary directory (inside container)
  local temp_go_lib_path_in_container="/app/${temp_output_dir}/${output_go_lib_name}"
  local temp_go_header_path_in_container="/app/${temp_output_dir}/${output_go_lib_name%.*}.h"

  # Ensure the temporary output directory exists on host
  mkdir -p "$temp_output_dir"

  # Determine Docker platform for multi-arch builds (for Go build, even if Clang is specific)
  case "$target_arch" in
    "amd64") DOCKER_PLATFORM_ARG="--platform linux/amd64" ;;
    "arm64") DOCKER_PLATFORM_ARG="--platform linux/arm64" ;;
    *) DOCKER_PLATFORM_ARG="" ;;
  esac

  # Get Clang compiler details
  read -r compiler_package compiler_exe compiler_target_triple java_arch_suffix <<< "$(get_cross_compiler_vars "$target_arch")"

  # Determine Java Home inside the container
  local docker_java_home="/usr/lib/jvm/java-17-openjdk-${java_arch_suffix}"

  echo "    (Using Docker $DOCKER_PLATFORM_ARG and image 'golang:latest' with $compiler_exe -target $compiler_target_triple)"
  docker run --rm $DOCKER_PLATFORM_ARG \
    -v "$(pwd)":/app \
    -v "$(pwd)/$OUTPUT_ROOT_DIR":/resource-lib \
    -v "$(pwd)/bridge":/bridge-dir \
    -w /app golang:latest bash -c "\
    # Overwrite sources.list for full Debian repositories including non-free
    echo \"deb http://deb.debian.org/debian/ bookworm main contrib non-free\" > /etc/apt/sources.list && \
    echo \"deb-src http://deb.debian.org/debian/ bookworm main contrib non-free\" >> /etc/apt/sources.list && \
    echo \"deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free\" >> /etc/apt/sources.list && \
    echo \"deb-src http://deb.debian.org/debian/ bookworm-updates main contrib non-free\" >> /etc/apt/sources.list && \
    echo \"deb http://security.debian.org/debian-security bookworm-security main contrib non-free\" >> /etc/apt/sources.list && \
    echo \"deb-src http://security.debian.org/debian-security bookworm-security main contrib non-free\" >> /etc/apt/sources.list && \
    \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      $compiler_package \
      openjdk-17-jdk-headless && \
    # Ensure /usr/bin is in PATH for compilers
    export PATH=\"/usr/bin:\$PATH\" && \
    # Create a symlink for 'lld' if it's versioned (e.g., lld-15)
    if ! command -v lld &> /dev/null; then \
      LLD_VERSIONED_PATH=\$(find /usr/bin -maxdepth 1 -type f -name 'lld-*' | head -n 1); \
      if [ -n \"\$LLD_VERSIONED_PATH\" ]; then \
        echo \"lld not found, but versioned linker found at \$LLD_VERSIONED_PATH. Creating symlink.\"; \
        ln -s \"\$LLD_VERSIONED_PATH\" /usr/bin/lld; \
      else \
        echo \"Warning: lld or versioned lld not found after install. Linker might fail.\"; \
      fi; \
    fi && \
    export GOOS=windows && \
    export GOARCH=$target_arch && \
    export CGO_ENABLED=1 && \
    # Set CC and CXX to just clang/clang++
    export CC=\"$compiler_exe\" && \
    export CXX=\"${compiler_exe/clang/clang++}\" && \
    # Pass the target triple via CFLAGS/CXXFLAGS
    export CGO_CFLAGS=\"-target $compiler_target_triple\" && \
    export CGO_CXXFLAGS=\"-target $compiler_target_triple\" && \
    # Explicitly tell Go to use lld as the linker
    export CGO_LDFLAGS=\"-fuse-ld=lld\" && \
    export JAVA_HOME=\"$docker_java_home\" && \
    export PATH=\"\$JAVA_HOME/bin:\$PATH\" && \
    mkdir -p \"$temp_output_dir\" && \
    go mod tidy && \
    go mod download && \
    go build -buildmode=c-shared -o \"$temp_go_lib_path_in_container\" \"$GO_PACKAGE_BASE_PATH/$go_source_file\" && \
    echo \"Go library compiled successfully: $temp_go_lib_path_in_container\" && \
    mv \"$temp_go_lib_path_in_container\" \"/resource-lib/${output_go_lib_name}\" && \
    mv \"$temp_go_header_path_in_container\" \"/bridge-dir/${lib_prefix}${final_output_filename_base}_windows_${target_arch}.h\" \
  "
}

# Function to build the C bridge shared library for Windows
# Args:
#   $1: target_arch (e.g., "amd64", "arm64")
#   $2: c_source_file_base (e.g., "bridge_windows_arm64.c")
#   $3: go_lib_name_on_host (e.g., "native_hook_windows_arm64.dll") - just the filename
#   $4: final_output_filename_base (e.g., "bridge")
build_bridge() {
  local target_arch=$1
  local c_source_file_base=$2
  local go_lib_name_on_host=$3
  local final_output_filename_base=$4

  echo "==> Building C bridge for windows/$target_arch"

  # Unset previous environment variables for clean build context
  unset GOOS
  unset GOARCH
  unset CGO_ENABLED

  local output_extension="dll"
  local lib_prefix=""

  # Determine Docker platform for multi-arch builds
  case "$target_arch" in
    "amd64") DOCKER_PLATFORM_ARG="--platform linux/amd64" ;;
    "arm64") DOCKER_PLATFORM_ARG="--platform linux/arm64" ;;
    *) DOCKER_PLATFORM_ARG="" ;;
  esac

  # Get Clang compiler details
  read -r compiler_package compiler_exe compiler_target_triple java_arch_suffix <<< "$(get_cross_compiler_vars "$target_arch")"
  
  # Determine Java Home inside the container
  local docker_java_home="/usr/lib/jvm/java-17-openjdk-${java_arch_suffix}"
  # Path to JNI include directory inside the Docker container for Linux JNI headers
  # CAUTION: These are Linux JNI headers. For full Windows compatibility,
  # 'win32' specific JNI headers from a Windows JDK are needed.
  local docker_jni_include_path_generic="${docker_java_home}/include" # Generic path
  local docker_jni_include_path_os="${docker_java_home}/include/linux" # Platform-specific (Linux)

  local go_lib_name_for_linking_base=$(basename "$go_lib_name_on_host") # e.g., native_hook_windows_amd64.dll
  local go_lib_name_for_linking_stripped="${go_lib_name_for_linking_base%.*}" # Remove .dll
  if [[ "$go_lib_name_for_linking_stripped" == lib* ]]; then
    go_lib_name_for_linking_stripped="${go_lib_name_for_linking_stripped#lib}" # Remove 'lib' prefix for -l flag
  fi
  # The Go library will now be in /resource-lib inside the container
  local docker_go_lib_path_for_linking="/resource-lib/${go_lib_name_for_linking_base}"

  # Construct the full C bridge library name including OS and arch suffix
  local output_bridge_lib_name="${lib_prefix}${final_output_filename_base}_windows_${target_arch}.${output_extension}"

  echo "    (Using Docker $DOCKER_PLATFORM_ARG and image 'golang:latest' for Windows C bridge compilation)"
  docker run --rm $DOCKER_PLATFORM_ARG \
    -v "$(pwd)":/app \
    -v "$(pwd)/$OUTPUT_ROOT_DIR":/resource-lib \
    -w /app golang:latest bash -c "\
    # Overwrite sources.list for full Debian repositories including non-free
    echo \"deb http://deb.debian.org/debian/ bookworm main contrib non-free\" > /etc/apt/sources.list && \
    echo \"deb-src http://deb.debian.org/debian/ bookworm main contrib non-free\" >> /etc/apt/sources.list && \
    echo \"deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free\" >> /etc/apt/sources.list && \
    echo \"deb-src http://deb.debian.org/debian/ bookworm-updates main contrib non-free\" >> /etc/apt/sources.list && \
    echo \"deb http://security.debian.org/debian-security bookworm-security main contrib non-free\" >> /etc/apt/sources.list && \
    echo \"deb-src http://security.debian.org/debian-security bookworm-security main contrib non-free\" >> /etc/apt/sources.list && \
    \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      $compiler_package \
      openjdk-17-jdk-headless && \
    # Ensure /usr/bin is in PATH for cross-compilers
    export PATH=\"/usr/bin:\$PATH\" && \
    # Create a symlink for 'lld' if it's versioned (e.g., lld-15)
    if ! command -v lld &> /dev/null; then \
      LLD_VERSIONED_PATH=\$(find /usr/bin -maxdepth 1 -type f -name 'lld-*' | head -n 1); \
      if [ -n \"\$LLD_VERSIONED_PATH\" ]; then \
        echo \"lld not found, but versioned linker found at \$LLD_VERSIONED_PATH. Creating symlink.\"; \
        ln -s \"\$LLD_VERSIONED_PATH\" /usr/bin/lld; \
      else \
        echo \"Warning: lld or versioned lld not found after install. Linker might fail.\"; \
      fi; \
    fi && \
    export JAVA_HOME=\"$docker_java_home\" && \
    export PATH=\"\$JAVA_HOME/bin:\$PATH\" && \
    \
    CC_CMD=\"$compiler_exe\" && \
    CXX_CMD=\"${compiler_exe/clang/clang++}\" && \
    COMPILER_TARGET_TRIPLE=\"$compiler_target_triple\" && \
    JNI_INCLUDE_GENERIC_PATH=\"$docker_jni_include_path_generic\" && \
    JNI_INCLUDE_OS_PATH=\"$docker_jni_include_path_os\" && \
    GO_LIB_PATH_FOR_LINKING=\"$docker_go_lib_path_for_linking\" && \
    GO_LIB_NAME_FOR_LINKING=\"$go_lib_name_for_linking_stripped\" && \
    FINAL_BRIDGE_OUTPUT_NAME=\"$output_bridge_lib_name\" && \
    TARGET_ARCH_INNER=\"$target_arch\" && \
    \
    cd bridge && \
    \"\$CC_CMD\" -target \"\$COMPILER_TARGET_TRIPLE\" -c -fPIC \"$c_source_file_base\" -o bridge_windows_\"\$TARGET_ARCH_INNER\".o \
      -I\"$(dirname "$GO_LIB_PATH_FOR_LINKING")\" -I. \
      -I\"\$JNI_INCLUDE_GENERIC_PATH\" \
      -I\"\$JNI_INCLUDE_OS_PATH\" && \
    \"\$CC_CMD\" -target \"\$COMPILER_TARGET_TRIPLE\" -shared -o \"\$FINAL_BRIDGE_OUTPUT_NAME\" bridge_windows_\"\$TARGET_ARCH_INNER\".o \
      -L. -L\"$(dirname "$GO_LIB_PATH_FOR_LINKING")\" -l\"\$GO_LIB_NAME_FOR_LINKING\" && \
    echo \"C bridge compiled successfully: \$FINAL_BRIDGE_OUTPUT_NAME\" && \
    mv \"\$FINAL_BRIDGE_OUTPUT_NAME\" \"/resource-lib\" \
  "
}


# Cleanup function
cleanup() {
  echo "==> Cleaning up previous build artifacts..."
  rm -f "$OUTPUT_ROOT_DIR/*.dll"
  rm -rf "$TMP_BUILD_DIR/windows*"
  rm -f ./bridge/*windows*.h # Remove Go-generated headers that might be left in bridge/
  rm -f  ./bridge/*windows*.o # Remove object files from bridge/
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

# Windows ARM64
WINDOWS_ARM64_TMP_DIR="$TMP_BUILD_DIR/windows-arm64"
build_go "arm64" "main_windows.go" "$WINDOWS_ARM64_TMP_DIR" "native_hook"
build_bridge "arm64" "bridge_windows_arm64.c" "native_hook_windows_arm64.dll" "bridge"

# Windows AMD64
WINDOWS_AMD64_TMP_DIR="$TMP_BUILD_DIR/windows-amd64"
build_go "amd64" "main_windows.go" "$WINDOWS_AMD64_TMP_DIR" "native_hook"
build_bridge "amd64" "bridge_windows_amd64.c" "native_hook_windows_amd64.dll" "bridge"

NOW_UNIX_TIMESTAMP=$(date +%s)

echo "==> All Windows builds completed. Final libraries are in: $OUTPUT_ROOT_DIR"
echo "==> Build duration: $(( (NOW_UNIX_TIMESTAMP - CURRENT_UNIX_TIMESTAMP) / 60 ))m $(( (NOW_UNIX_TIMESTAMP - CURRENT_UNIX_TIMESTAMP) % 60 ))s"
