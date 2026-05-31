#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -e

# VHDL sourcefiles.
SRC_PREFIX=../src

mapfile SYNTH_FILES < $SRC_PREFIX/synth_files.lst
SYNTH_FILES=(${SYNTH_FILES[@]/#/$SRC_PREFIX/})

function analyze () {
    cmd="ghdl -a --std=19 --work=$2 $1"
    echo $cmd
    $cmd
}

for f in "${SYNTH_FILES[@]}"; do
    analyze $f defaultlib
done
