#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -e

# VHDL sourcefiles.
SRC_PREFIX=../src

mapfile SYNTH_FILES < $SRC_PREFIX/synth_files.lst
SYNTH_FILES=(${SYNTH_FILES[@]/#/$SRC_PREFIX/})

mapfile SIM_FILES < $SRC_PREFIX/sim_files.lst
SIM_FILES=(${SIM_FILES[@]/#/$SRC_PREFIX/})

function analyze () {
    cmd="nvc --std=19 -L. --work=$2 -a $1"
    echo $cmd
    $cmd
}

for f in "${SYNTH_FILES[@]}"; do
    analyze $f defaultlib
done

for f in "${SIM_FILES[@]}"; do
    analyze $f defaultlib
done
