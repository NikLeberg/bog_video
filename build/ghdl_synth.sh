#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -e

function postprocess_design () {
    case "$1" in
        *.v)
            # Verilog

            # Replace "\foo.bar[last] " with "\foo.bar(last) ".
            sed -i -E 's/\\([^[]*)\[([^]]*)\] /\\\1(\2) /g' "$1"
            ;;
        *)
            # VHDL

            # Replace "\foo.bar[last]\" with "\foo.bar(last)\".
            sed -i -E 's/\\([^\\]*)\[([^\\]*)\]\\/\\\1(\2)\\/g' "$1"

            # Remove VHDL work libraries, they are not required as all types
            # have been resolved to the primitive IEEE types.
            sed -i -E 's/^use work\..*\.all;$//g' "$1"
            ;;
    esac
}

# Transpile VHDL-2019 source to Verilog netlist that Quartus understands.
function synth () {
    cmd="ghdl --synth --std=19 --work=$2 --no-formal -Wno-binding --out=verilog -o=$3 $1"
    echo $cmd
    $cmd

    postprocess_design $3
}

synth top defaultlib top.synth.v
