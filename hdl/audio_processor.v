/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

// useless:
/* verilator lint_off PINCONNECTEMPTY */

module audio_processor #(
	parameter RAM_DEPTH = 512
) (
	input  wire        clk,
	input  wire        rst_n,

	inout  wire        VDD,
	inout  wire        VSS,

	input  wire        dbg_req_halt,
	input  wire        dbg_req_halt_on_reset,
	input  wire        dbg_req_resume,
	output wire        dbg_halted,
	output wire        dbg_running,
	input  wire [31:0] dbg_data0_rdata,
	output wire [31:0] dbg_data0_wdata,
	output wire        dbg_data0_wen,
	input  wire [31:0] dbg_instr_data,
	input  wire        dbg_instr_data_vld,
	output wire        dbg_instr_data_rdy,
	output wire        dbg_instr_caught_exception,
	output wire        dbg_instr_caught_ebreak,

	input  wire [31:0] ahbls_haddr,
	input  wire        ahbls_hwrite,
	input  wire [1:0]  ahbls_htrans,
	input  wire [2:0]  ahbls_hsize,
	input  wire        ahbls_hready,
	output wire        ahbls_hready_resp,
	output wire        ahbls_hresp,
	input  wire [31:0] ahbls_hwdata,
	output wire [31:0] ahbls_hrdata,

	output wire        audio_l,
	output wire        audio_r
);

// ------------------------------------------------------------------------
// AHBL to SBUS bridge

// This also serves as a pipestage. The Hazard3 SBUS port is used for sharing
// load/store access with the Debug Module's System Bus Access feature. You
// can also just use it to access through the processor's load/store port.

// Registered to CPU
reg  [31:0] sbus_addr;
reg  [31:0] sbus_wdata;
reg         sbus_vld;
reg  [1:0]  sbus_size;
reg         sbus_write;
// Live from CPU
wire [31:0] sbus_rdata;
wire        sbus_err;
wire        sbus_rdy;
// Registered from CPU
reg  [31:0] sbus_rdata_q;
reg         sbus_err_q;
reg         sbus_rdy_q;

assign ahbls_hrdata      = sbus_rdata_q;
assign ahbls_hready_resp = sbus_rdy_q;
assign ahbls_hresp       = sbus_err_q;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		sbus_addr    <= 32'd0;
		sbus_vld     <= 1'b0;
		sbus_size    <= 1'b0;
		sbus_write   <= 1'b0;
		sbus_rdata_q <= 32'd0;
		sbus_err_q   <= 1'b0;
		sbus_rdy_q   <= 1'b1;
	end else if (ahbls_hready) begin
		sbus_vld <= ahbls_htrans[1];
		sbus_rdy_q <= !ahbls_htrans[1];
		sbus_err_q  <= 1'b0;
		// Not gating these updates on htrans[1] as currently that implies a
		// mux2 on GF180MCU:
		sbus_addr <= ahbls_haddr;
		sbus_size <= ahbls_hsize[1:0];
		sbus_write <= ahbls_hwrite;
	end else if (sbus_vld && sbus_rdy && sbus_err) begin
		// Generate phase 0 of AHB ERROR and deassert downstream
		sbus_err_q <= 1'b1;
		sbus_vld <= 1'b0;
	end else if (sbus_err_q && !sbus_rdy_q) begin
		// Generate phase 1 of AHB ERROR
		sbus_rdy_q <= 1'b1;
	end else if (sbus_vld && sbus_rdy) begin
		// Generate AHB OKAY and deassert downstream
		sbus_rdy_q <= 1'b1;
		sbus_rdata_q <= sbus_rdata;
		sbus_vld <= 1'b0;
	end
end

// It might be surprising but if you put a 1-cycle delay on HWDATA then
// everything just works out. SBUS doesn't actually need WDATA until after the
// downstream address is issued. Not a public API detail but :)

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		sbus_wdata <= 32'd0;
	end else begin
		// TODO revisit if ICG inference is implemented
		sbus_wdata <= ahbls_hwdata;
	end
end

// ------------------------------------------------------------------------
// Processor instantiation

localparam NUM_IRQS = 1;

wire                cpu_pwrup_req;
wire                cpu_pwrup_ack = cpu_pwrup_req;
wire                cpu_clk_en;

wire                unblock_out;
wire                unblock_in = unblock_out;

wire [31:0]         cpu_haddr;
wire                cpu_hwrite;
wire [1:0]          cpu_htrans;
wire [2:0]          cpu_hsize;
wire [2:0]          cpu_hburst;
wire [3:0]          cpu_hprot;
wire                cpu_hmastlock;
wire [7:0]          cpu_hmaster;
wire                cpu_hexcl;
wire                cpu_hready;
wire                cpu_hresp;
wire                cpu_hexokay = 1'b1;
wire [31:0]         cpu_hwdata;
wire [31:0]         cpu_hrdata;

wire [NUM_IRQS-1:0] irq = 1'b0;
wire                soft_irq = 1'b0;
wire                timer_irq = 1'b0;

wire                fence_i_vld;
wire                fence_d_vld;
wire                fence_rdy = 1'b1;

wire                clk_gated_cpu;

cell_clkgate_low clkgate_cpu_u (
    .clk_in  (clk),
    .enable  (cpu_clk_en),
    .clk_out (clk_gated_cpu)
);

hazard3_cpu_1port #(
    .RESET_VECTOR        (32'h00000000),
    .MTVEC_INIT          (32'h00000000),

    .EXTENSION_A         (0),
    .EXTENSION_C         (1),
    .EXTENSION_E         (1),
    .EXTENSION_M         (1),

    .EXTENSION_ZBA       (1),
    .EXTENSION_ZBB       (1),
    .EXTENSION_ZBC       (0),
    .EXTENSION_ZBKB      (1),
    .EXTENSION_ZBKX      (0),
    .EXTENSION_ZBS       (1),
    .EXTENSION_ZCB       (1),
    .EXTENSION_ZCLSD     (0),
    .EXTENSION_ZCMP      (0),
    .EXTENSION_ZIFENCEI  (0),
    .EXTENSION_ZILSD     (0),

    .EXTENSION_XH3BEXTM  (0),
    .EXTENSION_XH3IRQ    (0),
    .EXTENSION_XH3PMPM   (0),
    .EXTENSION_XH3POWER  (0),

    .CSR_M_MANDATORY     (1),
    .CSR_M_TRAP          (1),
    .CSR_COUNTER         (0),

    .U_MODE              (0),
    .PMP_REGIONS         (0),

    .DEBUG_SUPPORT       (1),
    .BREAKPOINT_TRIGGERS (0),
    .NUM_IRQS            (NUM_IRQS),
    .IRQ_PRIORITY_BITS   (0),

    .MVENDORID_VAL       (32'h0),
    .MCONFIGPTR_VAL      (32'h0),

    .REDUCED_BYPASS      (0),
    .MULDIV_UNROLL       (1),
    .MUL_FAST            (1),
    .MUL_FASTER          (0),
    .MULH_FAST           (0),
    .FAST_BRANCHCMP      (1),
    .RESET_REGFILE       (0),
    .BRANCH_PREDICTOR    (0),
    .MTVEC_WMASK         (32'h000ffffd)
) cpu_u (
    .clk                        (clk),
    .clk_always_on              (clk_gated_cpu),
    .rst_n                      (rst_n),

    .pwrup_req                  (cpu_pwrup_req),
    .pwrup_ack                  (cpu_pwrup_ack),
    .clk_en                     (cpu_clk_en),

    .unblock_out                (unblock_out),
    .unblock_in                 (unblock_in),

    .haddr                      (cpu_haddr),
    .hwrite                     (cpu_hwrite),
    .htrans                     (cpu_htrans),
    .hsize                      (cpu_hsize),
    .hburst                     (cpu_hburst),
    .hprot                      (cpu_hprot),
    .hmastlock                  (cpu_hmastlock),
    .hmaster                    (cpu_hmaster),
    .hexcl                      (cpu_hexcl),
    .hready                     (cpu_hready),
    .hresp                      (cpu_hresp),
    .hexokay                    (cpu_hexokay),
    .hwdata                     (cpu_hwdata),
    .hrdata                     (cpu_hrdata),

    .fence_i_vld                (fence_i_vld),
    .fence_d_vld                (fence_d_vld),
    .fence_rdy                  (fence_rdy),

    .dbg_req_halt               (dbg_req_halt),
    .dbg_req_halt_on_reset      (dbg_req_halt_on_reset),
    .dbg_req_resume             (dbg_req_resume),
    .dbg_halted                 (dbg_halted),
    .dbg_running                (dbg_running),
    .dbg_data0_rdata            (dbg_data0_rdata),
    .dbg_data0_wdata            (dbg_data0_wdata),
    .dbg_data0_wen              (dbg_data0_wen),
    .dbg_instr_data             (dbg_instr_data),
    .dbg_instr_data_vld         (dbg_instr_data_vld),
    .dbg_instr_data_rdy         (dbg_instr_data_rdy),
    .dbg_instr_caught_exception (dbg_instr_caught_exception),
    .dbg_instr_caught_ebreak    (dbg_instr_caught_ebreak),

    .dbg_sbus_addr              (sbus_addr),
    .dbg_sbus_write             (sbus_write),
    .dbg_sbus_size              (sbus_size),
    .dbg_sbus_vld               (sbus_vld),
    .dbg_sbus_rdy               (sbus_rdy),
    .dbg_sbus_err               (sbus_err),
    .dbg_sbus_wdata             (sbus_wdata),
    .dbg_sbus_rdata             (sbus_rdata),

    .mhartid_val                (32'd1),
    .eco_version                (4'd0),

    .irq                        (irq),
    .soft_irq                   (soft_irq),
    .timer_irq                  (timer_irq)
);

// ------------------------------------------------------------------------
// Memories

ahb_sync_sram #(
    .W_DATA (32),
    .DEPTH  (RAM_DEPTH)
) ram_u (
    .VDD               (VDD),
    .VSS               (VSS),
    .clk               (clk),
    .rst_n             (rst_n),

    .ahbls_hready_resp (cpu_hready),
    .ahbls_hready      (cpu_hready),
    .ahbls_hresp       (cpu_hresp),
    .ahbls_haddr       (cpu_haddr),
    .ahbls_hwrite      (cpu_hwrite),
    .ahbls_htrans      (cpu_htrans),
    .ahbls_hsize       (cpu_hsize),
    .ahbls_hburst      (cpu_hburst),
    .ahbls_hprot       (cpu_hprot),
    .ahbls_hmastlock   (cpu_hmastlock),
    .ahbls_hwdata      (cpu_hwdata),
    .ahbls_hrdata      (cpu_hrdata)
);

// ----------------------------------------------------------------------------
// Mock PWM to avoid undriven outputs

reg [7:0] ctr;
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		ctr <= 8'd0;
	end else begin
		ctr <= ctr + 8'd1;
	end
end

assign audio_l = ctr[7];
assign audio_r = ctr[6];

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
