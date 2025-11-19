current_design $::env(DESIGN_NAME)
set_units -time ns

###############################################################################
# Clock definitions

set CLK_SYS_PERIOD 50
set DCK_PERIOD 50

# System clock: main CPU, SRAM, digital peripherals and external SRAM interface
create_clock [get_pins i_chip_core.clkroot_sys_u.magic_clkroot_anchor_u/Z] \
    -name clk_sys \
    -period $CLK_SYS_PERIOD

# Debug clock: clocks the debug transport module and one side of its bus CDC
create_clock [get_pins pad_DCK/PAD] \
    -name dck \
    -period $DCK_PERIOD

###############################################################################
# CDC constraints

proc cdc_maxdelay {clk_from clk_to period_to} {
    # Allow two cycles of propagation; really this is putting an upper bound on the skew
    set_max_delay [expr 2.0 * $period_to] -from [get_clocks $clk_from] -to [get_clocks $clk_to]
    # LibreLane doesn't support set_max_delay -datapath_only!
    # Instead, manually disable hold checks between unrelated clocks:
    set_false_path -hold -from [get_clocks $clk_from] -to [get_clocks $clk_to]
}

# All paths between clk_sys and DCK should be in the APB CDC, or reset
# controls which go into synchronisers in the destination domain. MCP of 2 is
# sufficient.
cdc_maxdelay dck clk_sys $CLK_SYS_PERIOD
cdc_maxdelay clk_sys dck $DCK_PERIOD

###############################################################################
# IO constraints

# set input_delay_value [expr $::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100]
# set output_delay_value [expr $::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100]

# Asynchronous reset, resynchronised internally
set_false_path -through [get_pins pad_RSTn/Y]

# You know what, fuck you *falses your paths*
set_false_path -through [get_pins *.magic_falsepath_anchor_u/Z]

# # Bidirectional pads
# set clk_core_inout_ports [get_ports { 
#     bidir_PAD[*]
# }] 

# set_input_delay -min 0 -clock $clocks $clk_core_inout_ports
# set_input_delay -max $input_delay_value -clock $clocks $clk_core_inout_ports
# set_output_delay $output_delay_value -clock $clocks $clk_core_inout_ports

###############################################################################
# Cargo-culted from project template :)

# Output load
set cap_load [expr $::env(OUTPUT_CAP_LOAD) / 1000.0]
puts "\[INFO] Setting load to: $cap_load"
set_load $cap_load [all_outputs]

puts "\[INFO] Setting clock uncertainty to: $::env(CLOCK_UNCERTAINTY_CONSTRAINT)"
set_clock_uncertainty $::env(CLOCK_UNCERTAINTY_CONSTRAINT) clk_sys
set_clock_uncertainty $::env(CLOCK_UNCERTAINTY_CONSTRAINT) dck

puts "\[INFO] Setting clock transition to: $::env(CLOCK_TRANSITION_CONSTRAINT)"
set_clock_transition $::env(CLOCK_TRANSITION_CONSTRAINT) clk_sys
set_clock_transition $::env(CLOCK_TRANSITION_CONSTRAINT) dck

puts "\[INFO] Setting timing derate to: $::env(TIME_DERATING_CONSTRAINT)%"
set_timing_derate -early [expr 1-[expr $::env(TIME_DERATING_CONSTRAINT) / 100]]
set_timing_derate -late [expr 1+[expr $::env(TIME_DERATING_CONSTRAINT) / 100]]

if { [info exists ::env(OPENLANE_SDC_IDEAL_CLOCKS)] && $::env(OPENLANE_SDC_IDEAL_CLOCKS) } {
    unset_propagated_clock [all_clocks]
} else {
    set_propagated_clock [all_clocks]
}

