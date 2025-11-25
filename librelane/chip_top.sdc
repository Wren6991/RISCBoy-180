current_design $::env(DESIGN_NAME)
set_units -time ns

###############################################################################
# Clock definitions

set CLK_SYS_MHZ 24
set DCK_MHZ 20
set CLK_LCD_MHz 36
set CLK_AUDIO_MHZ 24

set CLK_SYS_PERIOD   [expr 1000.0 / $CLK_SYS_MHZ]
set DCK_PERIOD       [expr 1000.0 / $DCK_MHZ]
set CLK_LCD_PERIOD   [expr 1000.0 / $CLK_LCD_MHz]
set CLK_AUDIO_PERIOD [expr 1000.0 / $CLK_AUDIO_MHZ]

# System clock: main CPU, SRAM, digital peripherals and external SRAM interface
create_clock [get_pins i_chip_core.clkroot_sys_u.magic_clkroot_anchor_u/Z] \
    -name clk_sys \
    -period $CLK_SYS_PERIOD

# LCD serial clock
create_clock [get_pins i_chip_core.clkroot_lcd_u.magic_clkroot_anchor_u/Z] \
    -name clk_lcd \
    -period $CLK_LCD_PERIOD

# Audio clock
create_clock [get_pins i_chip_core.clkroot_audio_u.magic_clkroot_anchor_u/Z] \
    -name clk_audio \
    -period $CLK_AUDIO_PERIOD

# Debug clock: clocks the debug transport module and one side of its bus CDC
create_clock [get_pins pad_DCK/PAD] \
    -name dck \
    -period $DCK_PERIOD

set SRAM_A_TO_Q 12

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

# Should just be an async FIFO and some 2DFF'd control signals
cdc_maxdelay clk_sys clk_lcd $CLK_LCD_PERIOD
cdc_maxdelay clk_lcd clk_sys $CLK_SYS_PERIOD

# Should just be an async FIFO and some 2DFF'd control signals
cdc_maxdelay clk_sys clk_audio $CLK_AUDIO_PERIOD
cdc_maxdelay clk_audio clk_sys $CLK_SYS_PERIOD

# Apply RTL-inserted false path constraints (setup/hold only, still constrain slew)
set_false_path -setup -hold -through [get_pins *.magic_falsepath_anchor_u/Z]

###############################################################################
# IO constraints

set_output_delay 5                            [get_ports DIO] -clock [get_clock dck]
set_input_delay -min 0                        [get_ports DIO] -clock [get_clock dck]
set_input_delay -max [expr 0.5 * $DCK_PERIOD] [get_ports DIO] -clock [get_clock dck]

set_output_delay [expr 0.50 * $CLK_SYS_PERIOD - $SRAM_A_TO_Q] -clock [get_clock clk_sys] [get_ports {
    SRAM_A[*]
    SRAM_DQ[*]
    SRAM_OEn
    SRAM_CSn
    SRAM_WEn
    SRAM_UBn
    SRAM_LBn
}]

set_input_delay [expr 0.50 * $CLK_SYS_PERIOD] -clock [get_clock clk_sys] [get_ports {
    SRAM_DQ[*]
}]

# GPIO: half period I guess? Keeping the round trip to a whole period seems good.
set_output_delay -min 0 -max [expr 0.50 * CLK_SYS_PERIOD] -clock [get_clock clk_sys] [get_ports {GPIO[*]}]
set_input_delay  -min 0 -max [expr 0.50 * CLK_SYS_PERIOD] -clock [get_clock clk_sys] [get_ports {GPIO[*]}]

# Backlight PWM: low-frequency, timing unimportant
set_false_path -setup -hold -through [get_ports LCD_BL]

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

