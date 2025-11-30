/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Based on async_sram_phy.v from libfpga. Instantiates flops, but not pads.

`default_nettype none

module async_sram_phy_gf180mcu #(
	parameter N_SRAM_A  = 18,
	parameter N_SRAM_DQ = 16 // Must be 16
) (
	// These should be the same clock/reset used by the controller
	input wire                    clk,
	input wire                    rst_n,

	// From SRAM controller
	input  wire [N_SRAM_A-1:0]    ctrl_addr,
	input  wire [N_SRAM_DQ-1:0]   ctrl_dq_out,
	input  wire [N_SRAM_DQ-1:0]   ctrl_dq_oe,
	output wire [N_SRAM_DQ-1:0]   ctrl_dq_in,
	input  wire                   ctrl_ce_n,
	input  wire                   ctrl_we_n,
	input  wire                   ctrl_oe_n,
	input  wire [N_SRAM_DQ/8-1:0] ctrl_byte_n,

	// To external SRAM
    input  wire [N_SRAM_DQ-1:0]   padin_sram_dq,
    output wire [N_SRAM_DQ-1:0]   padoe_sram_dq,
    output wire [N_SRAM_DQ-1:0]   padout_sram_dq,
    output wire [N_SRAM_A-1:0]    padout_sram_a,
    output wire                   padout_sram_oe_n,
    output wire                   padout_sram_cs_n,
    output wire                   padout_sram_we_n,
    output wire                   padout_sram_ub_n,
    output wire                   padout_sram_lb_n
);

// Use manually instantiated flops so they have fixed instance names

// No need for reset on flops for output-only pins, because we already
// separately ensure the pads are disabled and pulled to a default state until
// after the system comes out of reset. DQs do need a reset on their output
// enables though.

(* keep *) gf180mcu_fd_sc_mcu9t5v0__dffq_4 reg_u_sram_addr [N_SRAM_A-1:0]  (
	.CLK (clk),
	.D   (ctrl_addr),
	.Q   (padout_sram_a)
);

(* keep *) gf180mcu_fd_sc_mcu9t5v0__dffrnq_4 reg_out_u_sram_dq_oe [N_SRAM_DQ-1:0] (
	.CLK (clk),
	.RN  (rst_n),
	.D   (ctrl_dq_oe),
	.Q   (padoe_sram_dq)
);

`ifdef UGH_CANT_DO_THIS
// Negedge: data valid around start of WEn pulse and holds through the end
(* keep *) gf180mcu_fd_sc_mcu9t5v0__dffnq_4 reg_out_u_sram_dq_out [N_SRAM_DQ-1:0] (
	.CLKN (clk),
	.D    (ctrl_dq_out),
	.Q    (padout_sram_dq)
);
`else
// The above is functionally correct but is difficult to constrain in OpenSTA
// because it only lets you specify output delays *to* a pad, not *from*
// specific sources. So, behold:
assign padout_sram_dq = ctrl_dq_out;
`endif

(* keep *) gf180mcu_fd_sc_mcu9t5v0__dffq_4 reg_in_u_sram_dq_in [N_SRAM_DQ-1:0] (
	.CLK (clk),
	.D   (padin_sram_dq),
	.Q   (ctrl_dq_in)
);

(* keep *) gf180mcu_fd_sc_mcu9t5v0__dffq_4 reg_out_u_sram_strobe [3:0] (
	.CLK  (clk),
	.D    ({
		ctrl_ce_n,
		ctrl_oe_n,
		ctrl_byte_n
	}),
	.Q    ({
		padout_sram_cs_n,
		padout_sram_oe_n,
		padout_sram_ub_n,
		padout_sram_lb_n
	})
);

reg ctrl_we_n_1t;
always @ (posedge clk) begin
	ctrl_we_n_1t <= ctrl_we_n;
end

gf180mcu_fd_sc_mcu9t5v0__icgtn_4 clkgate_we_u (
	.TE   (1'b0),
	.E    (!ctrl_we_n_1t),
	.CLKN (clk),
	.Q    (padout_sram_we_n)
);

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
