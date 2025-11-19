/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Every posedge of clk, d0 and d1 are registered. d0 appears on q for the
// next half-period (ending at the negedge). Then d1 appears for the following
// half-period (starting with the negedge and ending at the next posedge).

`default_nettype none

module cell_ddr_out #(
	parameter RESET_VALUE = 0
) (
	input  wire clk,
	input  wire rst_n,
	input  wire [1:0] d,
	output wire q
);

reg q1p;
reg q0p;

// Transition encoded.
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		q1p <= 1'b0;
		q0p <= |RESET_VALUE;
	end else begin
		q1p <= q0p ^ q1p ^ d[0] ^ d[1];
		q0p <= q0p ^ q1p ^ d[0];
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

cell_ckxor xor_out_u (
	.a0 (q0p),
	.a1 (q1n),
	.z  (q)
);

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
