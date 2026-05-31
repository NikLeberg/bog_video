#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -e

# VHDL library files.
LIB_PREFIX=../lib

mapfile NEORV_FILES < $LIB_PREFIX/neorv32_files.lst
NEORV_FILES=(${NEORV_FILES[@]/#/$LIB_PREFIX/})

# VHDL sourcefiles.
SRC_PREFIX=../src

mapfile SYNTH_FILES < $SRC_PREFIX/synth_files.lst
SYNTH_FILES=(${SYNTH_FILES[@]/#/$SRC_PREFIX/})

function analyze () {
    cmd="ghdl -a --std=19 --work=$2 $1"
    echo $cmd
    $cmd
}

for f in "${NEORV_FILES[@]}"; do
    analyze $f neorv32
done

for f in "${SYNTH_FILES[@]}"; do
    analyze $f defaultlib
done
