#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -e

./ghdl_analyze.sh
./ghdl_synth.sh
(cd quartus && ../quartus_synth.sh)
