#!/bin/bash

set -e

# Detect JAVA_HOME
JAVA_HOME=$(/usr/libexec/java_home 2>/dev/null || echo $JAVA_HOME)

# Output path
OUTPUT_DIR="../src/main/resources/lib"
mkdir -p "$OUTPUT_DIR"

#===============================
# GO SHARED LIBRARIES
#===============================
build_go() {
  echo "==> Building Go project ($1)"
  if [ "$1" == "windows" ]; then
        export GOOS=windows
        export GOARCH=amd64
        export CGO_ENABLED=1
        export CC="zig cc -target x86_64-windows-gnu"
        export CXX="zig c++ -target x86_64-windows-gnu"
    elif [ "$1" == "darwin" ]; then
        export GOOS=darwin
        export GOARCH=arm64 # Or amd64 if targeting Intel Mac
        export CGO_ENABLED=1
        unset CC # Use default clang for native macOS build
        unset CXX
    elif [ "$1" == "linux" ]; then
        export GOOS=linux
        export GOARCH=amd64
        export CGO_ENABLED=1
        export CC="zig cc -target x86_64-linux-gnu" # Use Zig for Linux cross-compilation
        export CXX="zig c++ -target x86_64-linux-gnu"
    else
        echo "Unsupported OS: $1"
        exit 1
    fi
  go build -buildmode=c-shared -o "$2" ./main_"$1".go
  mv "$2" "./bridge/"
  if [ "$1" == "windows" ]; then
    mv native_hook.h "./bridge/"
  else
    mv libnative_hook.h "./bridge/"
  fi
  cp "./bridge/$2" "$OUTPUT_DIR/"
}

#===============================
# C BRIDGES
#===============================
build_bridge() {
  local os=$1
  local out=$2
  local src=$3
  local jni_dir="$JAVA_HOME/include"
  local jni_os_dir="$JAVA_HOME/include/$os"

  echo "==> Building C bridge for $os"

  cd bridge
  gcc -c -fPIC "$src" -o bridge.o -I. -I"$jni_dir" -I"$jni_os_dir"
  gcc -shared -o "$out" bridge.o -L. -lnative_hook
  cp "$out" ../$OUTPUT_DIR/
  rm -f bridge.o
  cd ..
}

cleanup() {
  echo "==> Cleaning up"
  rm -f ./bridge/*.dll
  rm -f ./bridge/*.h
  rm -f ./bridge/*.so
  rm -f ./bridge/*.dylib
}

build_go darwin libnative_hook.dylib
build_bridge darwin libbridge.dylib bridge_unix.c

build_go linux libnative_hook.so
build_bridge linux libbridge.so bridge_unix.c

build_go windows native_hook.dll
build_bridge win32 bridge.dll bridge_win.c

#cleanup

echo "==> Build completed. Output in: $OUTPUT_DIR"
