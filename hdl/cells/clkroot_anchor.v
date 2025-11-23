/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Clock root anchor buffer. No particular meaning in synthesis, but helps
// constraints to find a clock net in the netlist.

// For VDD/VSS:
/* verilator lint_off PINMISSING */

`default_nettype none

module clkroot_anchor (
	input  wire i,
	output wire z
);

`ifdef GF180MCU

// This gets resized, but use a 16 anyway to make the pre-repair STAs less
// shockingly wrong
(* keep *)
gf180mcu_fd_sc_mcu9t5v0__clkbuf_16 magic_clkroot_anchor_u (
	.I (i),
	.Z (z)
);

`else

assign z = i;

`endif

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
