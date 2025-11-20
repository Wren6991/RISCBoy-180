/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// The output is asserted asynchronously when the input is asserted,
// but deasserted synchronously when clocked with the input deasserted.
// Input and output are both active-low.

// This is based on the libfpga version, but with a falsepath anchor (target
// for constraints) added to the reset input. OpenSTA gives some really messed
// up recovery paths when reset synchronisers are chained together and we
// waive this based on knowledge of the flop cell circuit: it's insensitive to
// RN when CLK rises with Q = D = 0, so this is only a problem for the first
// flop in the chain (which ultimately either goes low or doesn't).

module reset_sync #(
	parameter N_CYCLES = 3 // must be >= 2
) (
	input  wire clk,
	input  wire rst_n_in,
	output wire rst_n_out
);

wire rst_n_in_fp;
falsepath_anchor fp_rst_n_in_u (
	.i (rst_n_in),
	.z (rst_n_in_fp)
);

(* keep = 1'b1 *) reg [N_CYCLES-1:0] delay;

always @ (posedge clk or negedge rst_n_in_fp) begin
	if (!rst_n_in_fp) begin
		delay <= {N_CYCLES{1'b0}};
	end else begin
		delay <= {delay[N_CYCLES-2:0], 1'b1};
	end
end

assign rst_n_out = delay[N_CYCLES-1];

endmodule
