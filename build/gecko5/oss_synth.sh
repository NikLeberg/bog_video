#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -ex

WORKDIR=oss
TOP=top
PACKAGE=CABGA381
IO_CONSTRAINTS=gecko5.lpf

yosys \
    --plugin ghdl.so \
    --commands "ghdl --std=19 --work=defaultlib $TOP; synth_ecp5 -json $WORKDIR/$TOP.json"
nextpnr-ecp5 --threads 12 \
    --85k --package $PACKAGE \
    --json $WORKDIR/$TOP.json --lpf $IO_CONSTRAINTS \
    --textcfg $WORKDIR/$TOP.config
ecppack --compress --freq 62.0 \
    --input $WORKDIR/$TOP.config \
    --bit $WORKDIR/$TOP.bit
openFPGALoader $WORKDIR/$TOP.bit
