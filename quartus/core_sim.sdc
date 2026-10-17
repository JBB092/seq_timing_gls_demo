# Timing constraints for the core_sim revision
# 100 MHz, the same clock the PLL gives on the board

create_clock -name clk -period 10 [get_ports clk]
derive_clock_uncertainty
