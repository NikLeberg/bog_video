#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -e

# Transpile VHDL-2008 source to Verilog netlist that Quartus understands.
function synth () {
    cmd="ghdl --synth --std=19 --no-formal --keep-hierarchy=no --out=verilog -o=$2 $1"
    echo $cmd
    $cmd
}

synth top top.synth.v
