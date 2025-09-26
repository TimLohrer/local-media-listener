#!/bin/bash

set -e

# colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # clear color

echo -e "${BLUE}==> Building Local Media Listener (C++ Implementation)${NC}"

# check if cmake is installed
if ! command -v cmake &> /dev/null; then
    echo -e "${RED}Error: CMake is not installed. Please install CMake to continue.${NC}"
    exit 1
fi

# create build directory (can override with BUILD_DIR env var)
BUILD_DIR="${BUILD_DIR:-build}"
if [ -d "$BUILD_DIR" ]; then
    echo -e "${YELLOW}==> Cleaning previous build...${NC}"
    rm -rf "$BUILD_DIR"
fi

echo -e "${BLUE}==> Creating build directory...${NC}"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# platform-specific configuration
if [[ "$OSTYPE" == "darwin"* ]]; then
    PLATFORM="macOS"
    echo -e "${GREEN}==> Detected platform: macOS${NC}"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    PLATFORM="Linux"
    echo -e "${GREEN}==> Detected platform: Linux${NC}"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    PLATFORM="Windows"
    echo -e "${GREEN}==> Detected platform: Windows${NC}"
else
    echo -e "${RED}==> Unknown platform: $OSTYPE${NC}"
    exit 1
fi

# check deps
echo -e "${BLUE}==> Checking dependencies...${NC}"

if [[ "$PLATFORM" == "macOS" ]]; then
    # check for xcode command line tools
    if ! xcode-select -p &> /dev/null; then
        echo -e "${RED}Error: Xcode command line tools not found. Please install them with:${NC}"
        echo "xcode-select --install"
        exit 1
    fi
    
    # check JAVA_HOME
    if [ -z "$JAVA_HOME" ]; then
        # try to detect java automatically
        if /usr/libexec/java_home &> /dev/null; then
            export JAVA_HOME=$(/usr/libexec/java_home)
            echo -e "${YELLOW}==> Auto-detected JAVA_HOME: $JAVA_HOME${NC}"
        else
            echo -e "${RED}Error: JAVA_HOME is not set and could not be auto-detected.${NC}"
            echo "Please install Java and set JAVA_HOME or run:"
            echo "export JAVA_HOME=\$(/usr/libexec/java_home)"
            exit 1
        fi
    fi
    
elif [[ "$PLATFORM" == "Linux" ]]; then
    # check for required packages
    if ! pkg-config --exists dbus-1; then
        echo -e "${RED}Error: libdbus-1-dev is not installed.${NC}"
        echo "Please install it with: sudo apt-get install libdbus-1-dev"
        exit 1
    fi
    
    # check JAVA_HOME
    if [ -z "$JAVA_HOME" ]; then
        # try to find java
        if command -v java &> /dev/null; then
            JAVA_PATH=$(readlink -f $(which java))
            export JAVA_HOME=$(dirname $(dirname "$JAVA_PATH"))
            echo -e "${YELLOW}==> Auto-detected JAVA_HOME: $JAVA_HOME${NC}"
        else
            echo -e "${RED}Error: JAVA_HOME is not set and Java not found.${NC}"
            echo "Please install OpenJDK and set JAVA_HOME"
            exit 1
        fi
    fi
    
elif [[ "$PLATFORM" == "Windows" ]]; then
    # TODO windows build support
    echo -e "${YELLOW}==> Windows build support is experimental${NC}"
fi

echo -e "${GREEN}==> Dependencies OK${NC}"

# configure with cmake
echo -e "${BLUE}==> Configuring build with CMake...${NC}"
# base cmake args
CMAKE_ARGS=""

CMAKE_ARGS_1=""
# add platform-specific cmake arguments
if [[ "$PLATFORM" == "macOS" ]]; then
    CMAKE_ARGS_1="-DCMAKE_OSX_DEPLOYMENT_TARGET=10.15"
    # append any extra macos architecture args
    if [ -n "${EXTRA_CMAKE_ARGS:-}" ]; then
        CMAKE_ARGS_1="$CMAKE_ARGS_1 $EXTRA_CMAKE_ARGS"
    fi
fi
CMAKE_ARGS="$CMAKE_ARGS_1"

cmake .. $CMAKE_ARGS

# build
echo -e "${BLUE}==> Building...${NC}"
cmake --build . --parallel $(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# check if build was successful
if [ $? -eq 0 ]; then
    echo -e "${GREEN}==> Build completed successfully!${NC}"
    echo -e "${GREEN}==> Libraries have been copied to ../src/main/resources/lib/${NC}"
else
    echo -e "${RED}==> Build failed!${NC}"
    exit 1
fi

echo -e "${GREEN}==> Done!${NC}" 