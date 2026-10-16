# Timing constraints for the board revision

create_clock -name CLOCK_50 -period 20 [get_ports CLOCK_50]
derive_pll_clocks
derive_clock_uncertainty

# KEY0 goes through a synchronizer and the LEDs/HEX are slow, so no I/O timing
set_false_path -from [get_ports {KEY[*]}]
set_false_path -to   [get_ports {LEDR[*] HEX*}]
