#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -e

# VHDL testbenches.
SRC_PREFIX=../src
mapfile SIM_TESTS < $SRC_PREFIX/sim_tests.lst

WAVE_PREFIX=wave
mkdir -p $WAVE_PREFIX

function test () {
    if [[ "$1" == \#* ]]; then
        echo "Skipped testbench ${1#\#}."
        return
    fi
    cmd="nvc --std=19 -L. --ieee-warnings=off --work=$2 -e $1 -r --wave=$WAVE_PREFIX/$1.vcd --format=vcd"
    echo $cmd
    $cmd
}

for t in "${SIM_TESTS[@]}"; do
    test $t defaultlib
done
