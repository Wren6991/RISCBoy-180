/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Every posedge of clk, dp and dn are registered.
//
// dp appears on q for the next half-period (ending at the negedge).Then dn
// appears for the following half-period (starting with the negedge and ending
// at the next posedge).

`default_nettype none

module cell_ddr_out #(
	parameter RESET_VALUE = 0
) (
	input  wire clk,
	input  wire rst_n,
	input  wire dp,
	input  wire dn,
	output wire q
);

reg q1p;
reg q0p;

// Transition encoded.
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		q0p <= |RESET_VALUE;
		q1p <= 1'b0;
	end else begin
		q0p <= q0p ^ q1p ^ dp;
		q1p <= q0p ^ q1p ^ dp ^ dn;
	end
end

reg q1n;
always @ (negedge clk or negedge rst_n) begin
	if (!rst_n) begin
		q1n <= 1'b0;
	end else begin
		q1n <= q1p;
	end
end

cell_clkxor xor_out_u (
	.a0 (q0p),
	.a1 (q1n),
	.z  (q)
);

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
