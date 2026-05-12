#**************************************************************
# Time Information
#**************************************************************
set_time_format -unit ns -decimal_places 3

#**************************************************************
# Create Clock
#**************************************************************
# 50 MHz
create_clock -name {clk} -period 20.000 -waveform { 0.000 10.000 } [get_ports {clk}]
# 10 MHz
create_clock -name {altera_reserved_tck} -period 100.000 -waveform { 0.000 50.000 } [get_ports {altera_reserved_tck}]

#**************************************************************
# Set Clock Uncertainty
#**************************************************************
derive_clock_uncertainty -add
