# SPDX-License-Identifier: MIT

# Compile & Synthesize with Quartus, use like:
#   quartus_sh -t quartus_synth.tcl

package require ::quartus::project

project_open "bog_video"

# Run complete design flow
load_package flow
execute_flow -compile

# Display summary of flow
load_package report
load_report "bog_video"
write_report_panel -file flowsummary.log "Flow Summary"
set fd [open "flowsummary.log" "r"]
puts [read $fd]
close $fd

project_close
