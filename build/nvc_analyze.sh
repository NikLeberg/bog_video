#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -e

# VHDL sourcefiles.
SRC_PREFIX=../src
mapfile SRC_FILES < $SRC_PREFIX/files.lst
SRC_FILES=(${SRC_FILES[@]/#/$SRC_PREFIX/})

function analyze () {
    cmd="nvc --std=19 -L. -a $1"
    echo $cmd
    $cmd
}

for f in "${SRC_FILES[@]}"; do
    analyze $f
done
