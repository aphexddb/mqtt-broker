#!/bin/bash

set -e

zig build
valgrind --leak-check=full --track-origins=yes --show-leak-kinds=all --num-callers=15 -s ./zig-out/bin/mqtt-broker