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
  go build -buildmode=c-shared -o "$2"
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
  local jni_os_dir="$JAVA_HOME/include/darwin"

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

cleanup

echo "==> Build completed. Output in: $OUTPUT_DIR"
