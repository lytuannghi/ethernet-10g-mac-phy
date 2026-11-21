###############################################################################
# File: eth10g_timing.sdc
# Module: eth10g_subsystem_top
# Target Frequency: 156.25 MHz (6.400 ns Period - IEEE 802.3ae Standard Line Clock)
# Technology: TSMC 28nm HPC+ Standard Cell Library (typical 0.9V, 25C)
###############################################################################

# Primary Core Line Clock Definition
create_clock -name clk -period 6.400 -waveform {0.000 3.200} [get_ports clk]

# Clock Uncertainty & Jitter
set_clock_uncertainty -setup 0.150 [get_clocks clk]
set_clock_uncertainty -hold  0.050 [get_clocks clk]
set_clock_transition 0.080 [get_clocks clk]

# Input Delays (AXI4-Stream & SerDes interface)
set_input_delay -clock clk -max 1.800 [get_ports {tx_axis_* pause_* pcs_rx_*}]
set_input_delay -clock clk -min 0.300 [get_ports {tx_axis_* pause_* pcs_rx_*}]

# Output Delays (AXI4-Stream & SerDes interface)
set_output_delay -clock clk -max 1.800 [get_ports {tx_axis_tready rx_axis_* tx_pause_* *_fault_* pcs_tx_*}]
set_output_delay -clock clk -min 0.200 [get_ports {tx_axis_tready rx_axis_* tx_pause_* *_fault_* pcs_tx_*}]

# Driving Cell & Output Load
set_driving_cell -lib_cell INVX4 [get_ports {tx_axis_* pause_* pcs_rx_*}]
set_load -pin_load 0.025 [get_ports {rx_axis_* pcs_tx_*}]
