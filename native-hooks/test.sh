#!/usr/bin/env bash
set -euo pipefail

# Determine the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR"

# Create and enter build directory
mkdir -p build && cd build

# Configure CMake with tests enabled
cmake .. -DBUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Debug

# Build the unit_tests target
cmake --build . --parallel

# Run the tests and show failures with individual test names
ctest --output-on-failure 