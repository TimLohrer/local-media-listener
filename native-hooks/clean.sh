#!/usr/bin/env bash
set -euo pipefail

# clean ../src/main/resources/lib

if [ -d "../src/main/resources/lib" ]; then
    rm -rf ../src/main/resources/lib
fi

echo "Cleaned ../src/main/resources/lib"
