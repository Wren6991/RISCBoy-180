/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Clock gate (ICG) which latches enable on posedge and holds the clock low
// when the enable is low.

// For VDD/VSS:
/* verilator lint_off PINMISSING */

`default_nettype none

module cell_clkgate_low (
	input  wire clk_in,
	input  wire enable,
	output wire clk_out
);

`ifdef GF180MCU

gf180mcu_fd_sc_mcu7t5v0__icgtp_1 clkgate_u (
	.TE  (1'b0),
	.E   (enable),
	.CLK (clk_in),
	.Q   (clk_out)
);

`else

reg enable_q;

always @ (*) if (!clk_in) enable_q <= enable;
assign clk_out = clk_in && enable_q;

`endif

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
