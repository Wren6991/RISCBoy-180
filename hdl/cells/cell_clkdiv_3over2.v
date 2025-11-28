/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// It's surprising that this works, but it does. Duty cycle is 33%. A NAND
// gate instead of the NOR would achieve the same division with a duty cycle
// of 67%. 33% is better for our WEn timing.

// For VDD/VSS:
/* verilator lint_off PINMISSING */

`default_nettype none

module cell_clkdiv_3over2 (
	input  wire clk_in,
	input  wire rst_n,
	output wire clk_out
);

wire rst_n_sync;
reset_sync reset_sync_u (
	.rst_n_in  (rst_n),
	.clk       (clk_in),
	.rst_n_out (rst_n_sync)
);

wire qp;
(*keep*)
gf180mcu_fd_sc_mcu9t5v0__dffrnq_4 posedge_flop_u (
	.CLK (clk_in),
	.D   (clk_out),
	.RN  (rst_n_sync),
	.Q   (qp)
);

wire qn;
(*keep*)
gf180mcu_fd_sc_mcu9t5v0__dffnrnq_4 negedge_flop_u (
	.CLKN (clk_in),
	.D    (clk_out),
	.RN   (rst_n_sync),
	.Q    (qn)
);

(*keep*)
gf180mcu_fd_sc_mcu9t5v0__nor2_4 nor_u (
	.A1 (qp),
	.A2 (qn),
	.ZN (clk_out)
);

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
