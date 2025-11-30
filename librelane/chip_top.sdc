current_design $::env(DESIGN_NAME)
set_units -time ns

###############################################################################
# Clock definitions

set CLK_SYS_MHZ 24
set DCK_MHZ 20

set CLK_SYS_PERIOD   [expr 1000.0 / $CLK_SYS_MHZ]
set DCK_PERIOD       [expr 1000.0 / $DCK_MHZ]

# System clock: clocks processors, SRAM interface, audio filters + SDM, and
# LCD interface.
create_clock [get_pins i_chip_core.clkroot_sys_u.magic_clkroot_anchor_u/Z] \
    -name clk_sys \
    -period $CLK_SYS_PERIOD

# Debug clock: clocks the debug transport module and one side of its bus CDC.
# Defined at the pad so we can constrain IO against it.
create_clock [get_pins pad_DCK/PAD] \
    -name dck \
    -period $DCK_PERIOD

###############################################################################
# CDC constraints

proc cdc_maxdelay {clk_from clk_to period_to} {
    # Allow two cycles of propagation; really this is putting an upper bound on the skew
    set_max_delay [expr 2.0 * $period_to] -from [get_clocks $clk_from] -to [get_clocks $clk_to]
    # OpenROAD doesn't support set_max_delay -datapath_only!
    # Instead, manually disable hold checks between unrelated clocks:
    set_false_path -hold -from [get_clocks $clk_from] -to [get_clocks $clk_to]
}

# All paths between clk_sys and DCK should be in the APB CDC, or reset
# controls which go into synchronisers in the destination domain. MCP of 2 is
# sufficient.
cdc_maxdelay dck clk_sys $CLK_SYS_PERIOD
cdc_maxdelay clk_sys dck $DCK_PERIOD

# Apply RTL-inserted false path constraints (setup/hold only, still constrain slew)
set_false_path -setup -hold -through [get_pins *.magic_falsepath_anchor_u/Z]

###############################################################################
# IO constraints (non-SRAM)

set_output_delay     [expr 0.5 * $DCK_PERIOD] [get_ports DIO] -clock [get_clock dck]
set_input_delay -min 0                        [get_ports DIO] -clock [get_clock dck]
set_input_delay -max [expr 0.5 * $DCK_PERIOD] [get_ports DIO] -clock [get_clock dck]

# GPIO: half period I guess? Keeping the round trip to a whole period seems good.
set_output_delay      [expr 0.50 * $CLK_SYS_PERIOD] -clock [get_clock clk_sys] [get_ports {GPIO[*]}]
set_input_delay  -max [expr 0.50 * $CLK_SYS_PERIOD] -clock [get_clock clk_sys] [get_ports {GPIO[*]}]
set_input_delay  -min 0                             -clock [get_clock clk_sys] [get_ports {GPIO[*]}]

# Reasonably tight on audio paths so we get the final flop and buffers fairly
# close to the quiet supply pins. Note this is just the audio path; the GPIO
# controls from clk_sys are false-pathed as they're not really important.
set_output_delay      [expr 0.70 * $CLK_SYS_PERIOD] -clock [get_clock clk_sys] [get_ports {AUDIO}]

# LCD_SCK has the same consideration as SRAM_WEn as it's generated using an
# ICGTN. Other than that just keep the SPI output paths rather tight as a way
# of controlling skew.
set LCD_SPI_OUTDELAY [expr 0.70 * $CLK_SYS_PERIOD]
set_output_delay $LCD_SPI_OUTDELAY -clock [get_clock clk_sys] [get_ports {
    LCD_DAT
    LCD_DC
}]

set_output_delay [expr $LCD_SPI_OUTDELAY - 0.50 * $CLK_SYS_PERIOD] -clock [get_clock clk_sys] [get_ports {
    LCD_CLK
}]

# Backlight PWM: low-frequency, timing unimportant
set_false_path -setup -hold -through [get_ports LCD_BL]

###############################################################################
# SRAM constraints

# Timings for 12 ns (slow grade) R1RP0416DI:
#
#                                                MIN MAX
#     Read cycle time..................... tRC   12  -
#     Address access time................. tAA   -   12
#     Chip select access time............. tACS  -   12
#     Output enable to output valid....... tOE   -   6
#     Byte select to output valid......... tBA   -   6
#     Output hold from address change..... tOH   3   -
#     Chip select to output in low-Z...... tCLZ  3   -
#     Output enable to output in low-Z.... tOLZ  0   -
#     Byte select to output in low-Z...... tBLZ  0   -
#     Chip deselect to output in high-Z... tCHZ  -   6
#     Output disable to output in high-Z.. tOHZ  -   6
#     Byte deselect to output in high-Z... tBHZ  -   6
#
#                                               MIN MAX
#     Write cycle time.................... tWC  12  -
#     Address valid to end of write....... tAW  8   -
#     Chip select to end of write......... tCW  8   -
#     Write pulse width................... tWP  8   -
#     Byte select to end of write......... tBW  8   -
#     Address setup time.................. tAS  0   -
#     Write recovery time................. tWR  0   -
#     Data to write time overlap.......... tDW  6   -
#     Data hold from write time........... tDH  0   -
#     Write disable to output in low-Z.... tOW  3   -
#     Output disable to output in high-Z.. tOHZ -   6

# Pad tRC/tWC so we can use faster RAMs or shorter clk_sys period:
set SRAM_A_TO_Q 20

# Input paths are less challenging, so squeeze them a bit more
set SRAM_Q_EXTRA_JUICE 5

# Put A-to-Q delay in middle of cycle:
set SRAM_IO_DELAY [expr 0.50 * ($CLK_SYS_PERIOD + $SRAM_A_TO_Q)]

set_output_delay $SRAM_IO_DELAY -clock [get_clock clk_sys] [get_ports {
    SRAM_A[*]
    SRAM_OEn
    SRAM_CSn
}]

# The SRAM D paths are longer than others as they go through (a small amount
# of) logic in the processor instead of coming straight from flops. It's also
# desirable for them to remain valid a little longer for hold time against the
# release (rise) of WEn; quite common for async RAMs to have a hold
# requirement of 0 on this edge.
#
# Cannot relax the OE paths of the same pads in this way because it would
# create drive contention with the next read cycle.
#
# OpenSTA does not support -through on set_output_delay (!) so can't specify
# different output delays through the OE (out enable) and A (out value) pins
# to the pad. Instead constrain both paths with relaxed timing and then apply
# additional delay to OEn.
set SRAM_D_DERATE 6
set_output_delay [expr $SRAM_IO_DELAY - $SRAM_D_DERATE] \
    -clock [get_clock clk_sys] [get_ports {SRAM_DQ[*]}]

# The check point is actually ahead of the clock by the output delay, so this
# *adds* delay, doesn't set it:
set_max_delay [expr $CLK_SYS_PERIOD - $SRAM_D_DERATE] -ignore_clock_latency \
    -through [get_pins {pad_SRAM_DQ*/OE} ] -to [get_ports {SRAM_DQ*} ]

# Delay on WEn is measured to negedge because it's from an ICGTN. The virtual
# start of its write cycle is still at the posedge (where the A is asserted),
# there's just no transition there. Can't figure out how to explain this to
# OpenSTA (it says the default source edge is posedge but 1. no specified way
# to change it 2. it's clearly timing from negedge) so just add a half-period
# of slack (which is a subtraction of delay).
set_output_delay [expr $SRAM_IO_DELAY - 0.50 * $CLK_SYS_PERIOD] \
    -clock [get_clock clk_sys] [get_ports {SRAM_WEn}]

set_input_delay [expr $SRAM_IO_DELAY + $SRAM_Q_EXTRA_JUICE] -clock [get_clock clk_sys] [get_ports {
    SRAM_DQ[*]
}]

###############################################################################
# The Machine Spirit is angry. Brother, get the holy oils

puts "(SCANMAP) Adding hold waivers to pseudo-DFFE scan flops:"
set scan_flops [get_cells -hier -filter "ref_name =~ gf180mcu_fd_sc_mcu9t5v0__sdffq_*"]
foreach flop $scan_flops {
    set flop_name [sta::get_full_name $flop]
    set q [sta::get_full_name [get_nets -of_object [get_pins ${flop_name}/Q]]]
    set d [sta::get_full_name [get_nets -of_object [get_pins ${flop_name}/D]]]
    set si [sta::get_full_name [get_nets -of_object [get_pins ${flop_name}/SI]]]
    if {[string equal $q $d]} {
        puts "(SCANMAP) Disabling hold checks -> D for pseudo-DFFE $flop_name (Q = ${q})"
        set_false_path -hold -to [get_pins ${flop_name}/D]
    } elseif {[string equal $q $si]} {
        puts "(SCANMAP) Disabling hold checks -> SI for pseudo-DFFE $flop_name (Q = ${q})"
        set_false_path -hold -to [get_pins ${flop_name}/SI]
    } else {
        puts "(SCANMAP) Skipping scan flop ${flop_name}: D = ${d} SI = ${si} Q = ${q}"
    }
}

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

