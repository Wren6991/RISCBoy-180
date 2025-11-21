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

`define SRAM_PHY_FLOP_P (* keep *) gf180mcu_fd_sc_mcu7t5v0__dffrnq_1
`define SRAM_PHY_FLOP_N (* keep *) gf180mcu_fd_sc_mcu7t5v0__dffnrnq_1

`SRAM_PHY_FLOP_P reg_u_sram_addr   [N_SRAM_A-1:0]  (.CLK  (clk), .RN (rst_n), .D (ctrl_addr),      .Q (padout_sram_a));

// Dirty negedge trick lets us use data-phase HWDATA on SRAM_DQ in the same
// cycle that the address-phase HADDR is valid on SRAM_A (at the cost of a
// half-cycle path on processor HWDATA; ok as that is available early):
`SRAM_PHY_FLOP_N reg_out_u_sram_dq_out  [N_SRAM_DQ-1:0] (.CLKN (clk), .RN (rst_n), .D (ctrl_dq_out),    .Q (padout_sram_dq));
`SRAM_PHY_FLOP_P reg_out_u_sram_dq_oe   [N_SRAM_DQ-1:0] (.CLK  (clk), .RN (rst_n), .D (ctrl_dq_oe),     .Q (padoe_sram_dq));
`SRAM_PHY_FLOP_P reg_in_u_sram_dq_in  [N_SRAM_DQ-1:0] (.CLK  (clk), .RN (rst_n), .D (padin_sram_dq),  .Q (ctrl_dq_in));

`SRAM_PHY_FLOP_P reg_out_u_sram_strobe [3:0] (
	.CLK  (clk),
	.RN   (rst_n),
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

// We could use a clock gate here (the DDR is very FPGA) but want to keep it
// as similar as possible to the other output paths.

cell_ddr_out #(
	.RESET_VALUE (1)
) reg_u_sram_we (
	.clk (clk),
	.rst_n (rst_n),
	.dp    (1'b1),
	.dn    (ctrl_we_n),
	.q     (padout_sram_we_n)
);

`undef SRAM_PHY_FLOP_P
`undef SRAM_PHY_FLOP_N

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
