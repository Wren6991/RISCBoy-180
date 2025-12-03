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

module reset_sync (
	input  wire clk,
	input  wire rst_n_in,
	output wire rst_n_out
);

wire rst_n_in_fp;
falsepath_anchor fp_rst_n_in_u (
	.i (rst_n_in),
	.z (rst_n_in_fp)
);

localparam N_CYCLES = 3;

`ifdef GF180MCU

wire [2:0] delay;

// Named instances just for convenience
/* verilator lint_off PINMISSING */
// waiver: VDD/VSS not connected on cell instance (handled in backend)
/* verilator lint_off SYNCASYNCNET */
// waiver: it's expected that the first flop in a synchroniser has potential async violations.
gf180mcu_fd_sc_mcu9t5v0__dffrnq_1 flop0 (.CLK (clk), .RN (rst_n_in_fp), .D (1'b1),     .Q (delay[0]));
gf180mcu_fd_sc_mcu9t5v0__dffrnq_1 flop1 (.CLK (clk), .RN (rst_n_in_fp), .D (delay[0]), .Q (delay[1]));
gf180mcu_fd_sc_mcu9t5v0__dffrnq_1 flop2 (.CLK (clk), .RN (rst_n_in_fp), .D (delay[1]), .Q (delay[2]));
/* verilator lint_on SYNCASYNCNET */
/* verilator lint_on PINMISSING */

`else

reg [N_CYCLES-1:0] delay;

always @ (posedge clk or negedge rst_n_in_fp) begin
	if (!rst_n_in_fp) begin
		delay <= {N_CYCLES{1'b0}};
	end else begin
		delay <= {delay[N_CYCLES-2:0], 1'b1};
	end
end

`endif

assign rst_n_out = delay[N_CYCLES-1];

endmodule
