/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Unfortunately there is no clock (balanced) XOR cell in the GF180MCU library
// so this is just a normal XOR.

// For VDD/VSS:
/* verilator lint_off PINMISSING */

`default_nettype none

module cell_clkxor (
	input  wire a0,
	input  wire a1,
	output wire z
);

`ifdef GF180MCU

gf180mcu_fd_sc_mcu7t5v0__xor2_1 cell_u (
	.A1 (a0),
	.A2 (a1),
	.Z  (z)
);

`else

assign z = a0 ^ a1;

`endif

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
