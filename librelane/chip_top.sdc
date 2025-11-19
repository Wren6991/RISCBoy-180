current_design $::env(DESIGN_NAME)
set_units -time ns

create_clock [get_pins i_chip_core.clkroot_sys_u.magic_clkroot_anchor_u/Z] -name clk_sys -period 50

create_clock [get_pins pad_DCK/PAD] -name dck -period 50

set input_delay_value [expr $::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100]
set output_delay_value [expr $::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100]

set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]
if { [info exists ::env(MAX_TRANSITION_CONSTRAINT)] } {
    set_max_transition $::env(MAX_TRANSITION_CONSTRAINT) [current_design]
}
if { [info exists ::env(MAX_CAPACITANCE_CONSTRAINT)] } {
    set_max_capacitance $::env(MAX_CAPACITANCE_CONSTRAINT) [current_design]
}

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

