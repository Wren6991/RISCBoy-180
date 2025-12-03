/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

module syscfg (
	input wire         clk,
	input wire         rst_n,
	
	// APB Port
	input  wire        apbs_psel,
	input  wire        apbs_penable,
	input  wire        apbs_pwrite,
	input  wire [19:0] apbs_paddr,
	input  wire [31:0] apbs_pwdata,
	output wire [31:0] apbs_prdata,
	output wire        apbs_pready,
	output wire        apbs_pslverr,

	output wire        mtime_tick_nrz,
	output wire        sram_chicken_cpuram,
	output wire        sram_chicken_apuram,
	output wire        sram_chicken_ppuram
);

wire [5:0] cfg_mtime_tick;
wire       cfg_sram_chicken;

syscfg_regs regs_u (
	.clk            (clk),
	.rst_n          (rst_n),

	.apbs_psel      (apbs_psel),
	.apbs_penable   (apbs_penable),
	.apbs_pwrite    (apbs_pwrite),
	.apbs_paddr     (apbs_paddr),
	.apbs_pwdata    (apbs_pwdata),
	.apbs_prdata    (apbs_prdata),
	.apbs_pready    (apbs_pready),
	.apbs_pslverr   (apbs_pslverr),

	.mtime_tick_o   (cfg_mtime_tick),
	.sram_chicken_o (cfg_sram_chicken)
);

// ----------------------------------------------------------------------------
// Generate RISC-V timer NRZ tick at a division of clk_sys

reg [5:0] mtime_tick_ctr;
reg       mtime_tick_nrz_q;
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		mtime_tick_ctr <= 6'd0;
		mtime_tick_nrz_q <= 1'b0;
	end else if (mtime_tick_ctr == 6'd1) begin
		mtime_tick_ctr <= cfg_mtime_tick;
		mtime_tick_nrz_q <= !mtime_tick_nrz_q;
	end else begin
		mtime_tick_ctr <= mtime_tick_ctr - 6'd1;
	end
end

assign mtime_tick_nrz = mtime_tick_nrz_q;

// ----------------------------------------------------------------------------
// SRAM CEN force

// Not forced at reset. Forced by default after reset. No longer forced after
// software clears this bit.

// Manually cloned flops to give the tools less opportunity to be dumb

reg [1:0] sram_chicken_cpuram_q;
reg [1:0] sram_chicken_apuram_q;
reg [1:0] sram_chicken_ppuram_q;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		sram_chicken_cpuram_q <= 2'b00;
		sram_chicken_apuram_q <= 2'b00;
		sram_chicken_ppuram_q <= 2'b00;
	end else begin
		// Stagger the enables to avoid slamming on all RAMs on the same cycle
		sram_chicken_cpuram_q <= {sram_chicken_cpuram_q[0], cfg_sram_chicken};
		sram_chicken_apuram_q <= {sram_chicken_apuram_q[0], sram_chicken_cpuram_q[0]};
		sram_chicken_ppuram_q <= {sram_chicken_ppuram_q[0], sram_chicken_apuram_q[0]};
	end
end

assign sram_chicken_cpuram = sram_chicken_cpuram_q[1];
assign sram_chicken_apuram = sram_chicken_apuram_q[1];
assign sram_chicken_ppuram = sram_chicken_ppuram_q[1];

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
