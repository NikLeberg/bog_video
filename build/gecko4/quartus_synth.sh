#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -e

# Start this script from wihin the /quartus subdir to keep parent dir clean.
quartus_sh -t ../quartus_synth.tcl
