/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Falsepath anchor buffer.
//
// * Preserves a net through synthesis.
// * Creates a predictable cell name that can easily be found for constraints.
//   You can even wildcard *.magic_falsepath_anchor_u.Z if you want to.

`default_nettype none

module falsepath_anchor (
	input  wire i,
	output wire z
);

`ifdef GF180MCU

(* keep *)
gf180mcu_fd_sc_mcu7t5v0__clkbuf_1 magic_falsepath_anchor_u (
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
