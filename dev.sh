#!/bin/bash
set -e

cd native-hooks
./build.sh
cd ..

gradle shadowJar
java -jar build/libs/LocalMediaListener-1.0.0.jar