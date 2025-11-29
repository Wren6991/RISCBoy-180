/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// This is unfortunately unused because I couldn't get CTS to stop doing dumb
// shit. Seems to work functionally though.

`default_nettype none

module clocks (
	input  wire        padin_clk,
	input  wire        padin_dck,
	input  wire        rst_n_global,

	// Clock outputs
	output wire        clk_sys,
	output wire        clk_audio,
	output wire        clk_lcd,

	// Reset input for regblock
	input  wire        rst_n_sys,

	// To RISC-V platform timer
	output wire        mtime_tick_nrz,
	
	// APB Port, synchronous to clk_sys
	input  wire        apbs_psel,
	input  wire        apbs_penable,
	input  wire        apbs_pwrite,
	input  wire [19:0] apbs_paddr,
	input  wire [31:0] apbs_pwdata,
	output wire [31:0] apbs_prdata,
	output wire        apbs_pready,
	output wire        apbs_pslverr
);

// ----------------------------------------------------------------------------
// Registers

wire [1:0]  clk_sys_select;
wire [3:0]  clk_sys_selected;
wire [1:0]  clk_audio_select;
wire [3:0]  clk_audio_selected;
wire [5:0]  mtime_tick;

clocks_regs regs_u (
	.clk                  (clk_sys),
	.rst_n                (rst_n_sys),

	.apbs_psel            (apbs_psel),
	.apbs_penable         (apbs_penable),
	.apbs_pwrite          (apbs_pwrite),
	.apbs_paddr           (apbs_paddr),
	.apbs_pwdata          (apbs_pwdata),
	.apbs_prdata          (apbs_prdata),
	.apbs_pready          (apbs_pready),
	.apbs_pslverr         (apbs_pslverr),

	.clk_sys_select_o     (clk_sys_select),
	.clk_sys_selected_i   (clk_sys_selected),

	.clk_audio_select_o   (clk_audio_select),
	.clk_audio_selected_i (clk_audio_selected),

	.mtime_tick_o         (mtime_tick)
);

// ----------------------------------------------------------------------------
// Primary inputs

// Timing origin for direct use of padin_clk (should all be within this block):
wire padin_clk_rooted;
clkroot_anchor clkroot_padin_clk_u (
	.i (padin_clk),
	.z (padin_clk_rooted)
);

wire rst_n_padin_clk;
reset_sync sync_rst_n_global_u (
	.clk       (padin_clk_rooted),
	.rst_n_in  (rst_n_global),
	.rst_n_out (rst_n_padin_clk)
);

// DCK is already rooted externally (also goes into debug logic)

// ----------------------------------------------------------------------------
// Generate divisions of padin_clk_rooted

reg padin_clk_div_2_unrooted;
always @ (posedge padin_clk_rooted or negedge rst_n_padin_clk) begin
	if (!rst_n_padin_clk) begin
		padin_clk_div_2_unrooted <= 1'b0;
	end else begin
		padin_clk_div_2_unrooted <= !padin_clk_div_2_unrooted;
	end
end

wire padin_clk_div_3over2_unrooted;
cell_clkdiv_3over2 clkdiv_3over2_u (
	.clk_in (padin_clk_rooted),
	.rst_n  (rst_n_padin_clk),
	.clk_out (padin_clk_div_3over2_unrooted)
);

// Insert clock roots on generated clocks; the clock generators only need to
// be balanced internally

wire padin_clk_div_2;
clkroot_anchor clkroot_div_2_u (
	.i (padin_clk_div_2_unrooted),
	.z (padin_clk_div_2)
);


wire padin_clk_div_3over2;
clkroot_anchor clkroot_div_3over2_u (
	.i (padin_clk_div_3over2_unrooted),
	.z (padin_clk_div_3over2)
);

// ----------------------------------------------------------------------------
// Select derived clocks from their sources

wire clk_sys_unrooted;
wire clk_audio_unrooted;

wire [3:0] clk_sys_selected_async;
cell_clkmux_glitchless #(
	.N_CLOCKS (4)
) clkmux_sys_u (
	.clk_in   ({padin_dck, padin_clk_div_2, padin_clk_div_3over2, padin_clk_rooted}),
	.rst_n    (rst_n_padin_clk),
	.sel      (clk_sys_select),
	.selected (clk_sys_selected_async),
	.clk_out  (clk_sys_unrooted)
);

wire [3:0] clk_audio_selected_async;
cell_clkmux_glitchless #(
	.N_CLOCKS (4)
) clkmux_audio_u (
	.clk_in   ({padin_dck, padin_clk_div_2, padin_clk_div_3over2, padin_clk_rooted}),
	.rst_n    (rst_n_padin_clk),
	.sel      (clk_audio_select),
	.selected (clk_audio_selected_async),
	.clk_out  (clk_audio_unrooted)
);

// ----------------------------------------------------------------------------
// Roots for system-level clocks

clkroot_anchor clkroot_sys_u (
	.i (clk_sys_unrooted),
	.z (clk_sys)
);

clkroot_anchor clkroot_audio_u (
	.i (clk_audio_unrooted),
	.z (clk_audio)
);

clkroot_anchor clkroot_lcd_u (
	.i (padin_clk_rooted),
	.z (clk_lcd)
);

// ----------------------------------------------------------------------------
// Synchronise status back to regblock

sync_1bit sync_sys_selected_u [3:0] (
	.clk   (clk_sys),
	.rst_n (rst_n_sys),
	.i     (clk_sys_selected_async),
	.o     (clk_sys_selected)
);

sync_1bit sync_audio_selected_u [3:0] (
	.clk   (clk_sys),
	.rst_n (rst_n_sys),
	.i     (clk_audio_selected_async),
	.o     (clk_audio_selected)
);

// ----------------------------------------------------------------------------
// Generate RISC-V timer NRZ tick at a division of clk_sys

reg [5:0] mtime_tick_ctr;
reg       mtime_tick_nrz_q;
always @ (posedge clk_sys or negedge rst_n_sys) begin
	if (!rst_n_sys) begin
		mtime_tick_ctr <= 6'd0;
		mtime_tick_nrz_q <= 1'b0;
	end else if (mtime_tick_ctr == 6'd1) begin
		mtime_tick_ctr <= mtime_tick;
		mtime_tick_nrz_q <= !mtime_tick_nrz_q;
	end else begin
		mtime_tick_ctr <= mtime_tick_ctr - 6'd1;
	end
end

assign mtime_tick_nrz = mtime_tick_nrz_q;

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
