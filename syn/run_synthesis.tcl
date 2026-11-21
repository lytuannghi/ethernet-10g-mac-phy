# =============================================================================
# Synthesis Script: run_synthesis.tcl
# Tool: Synopsys Design Compiler / Cadence Genus
# =============================================================================

set TOP_MODULE eth10g_subsystem_top

set RTL_FILES [list \
    ../rtl/mac/eth10g_crc32.v \
    ../rtl/flow/eth10g_pause_ctrl.v \
    ../rtl/mac/eth10g_mac_tx.v \
    ../rtl/mac/eth10g_mac_rx.v \
    ../rtl/pcs/eth10g_pcs_64b66b.v \
    ../rtl/xgmii/eth10g_xgmii_if.v \
    ../rtl/eth10g_subsystem_top.v \
]

read_verilog $RTL_FILES
current_design $TOP_MODULE
link

source eth10g_timing.sdc

compile_ultra -gate_clock -no_autoungroup

report_timing -delay max -max_paths 10 > reports/timing_report.txt
report_area -hierarchy > reports/area_report.txt
report_power > reports/power_report.txt

write -format verilog -hierarchy -output netlist/${TOP_MODULE}_syn.v
