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
	input  wire        clk_sys,
	input  wire        rst_n_sys,
    input  wire        rst_n_cpu,

    input  wire        clk_audio,
    input  wire        rst_n_audio,

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

    output wire        irq_cpu_softirq,
    output wire        irq_apu_timer_to_cpu,
    output wire        irq_apu_aout_to_cpu,

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

// Control-path signals have resets
always @ (posedge clk_sys or negedge rst_n_sys) begin
	if (!rst_n_sys) begin
		sbus_vld <= 1'b0;
		sbus_err_q <= 1'b0;
		sbus_rdy_q <= 1'b1;
	end else if (ahbls_hready) begin
		sbus_vld <= ahbls_htrans[1];
		sbus_rdy_q <= !ahbls_htrans[1];
		sbus_err_q  <= 1'b0;
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
		sbus_vld <= 1'b0;
	end
end

// Data-path signals do not require reset (but do have CG terms)
always @ (posedge clk_sys) if (ahbls_hready && ahbls_htrans[1]) begin
	sbus_addr <= ahbls_haddr;
	sbus_size <= ahbls_hsize[1:0];
	sbus_write <= ahbls_hwrite;
end

always @ (posedge clk_sys) if (sbus_vld && sbus_rdy && !sbus_write) begin
	sbus_rdata_q <= sbus_rdata;
end

// It might be surprising but if you put a 1-cycle delay on HWDATA then
// everything just works out. SBUS doesn't actually need WDATA until after the
// downstream address is issued. Not a public API detail but :)
always @ (posedge clk_sys) if (sbus_vld && sbus_write) begin
	sbus_wdata <= ahbls_hwdata;
end

// ------------------------------------------------------------------------
// Processor instantiation

wire                irq;        // mip.meip: from AOUT
wire                soft_irq;   // mip.msip: from IPC
wire                timer_irq;  // mip.mtip: from APU timer

// Also make these IRQs available to main CPU
assign irq_apu_aout_to_cpu = irq;
assign irq_apu_timer_to_cpu = timer_irq;

wire                start_apu;

wire                cpu_pwrup_req;
wire                cpu_pwrup_ack = cpu_pwrup_req || start_apu;
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
wire                cpu_hexokay;
wire [31:0]         cpu_hwdata;
wire [31:0]         cpu_hrdata;

wire                fence_i_vld;
wire                fence_d_vld;
wire                fence_rdy = 1'b1;

wire                clk_gated_cpu;

cell_clkgate_low clkgate_cpu_u (
    .clk_in  (clk_sys),
    .enable  (cpu_clk_en),
    .clk_out (clk_gated_cpu)
);

hazard3_cpu_1port #(
    .RESET_VECTOR        (32'h00000000),
    .MTVEC_INIT          (32'h00000000),

    .EXTENSION_A         (0),
    .EXTENSION_C         (1),
    .EXTENSION_E         (0),
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
    .EXTENSION_XH3POWER  (1),

    .CSR_M_MANDATORY     (1),
    .CSR_M_TRAP          (1),
    .CSR_COUNTER         (0),

    .U_MODE              (0),
    .PMP_REGIONS         (0),

    .DEBUG_SUPPORT       (1),
    .BREAKPOINT_TRIGGERS (0),
    .NUM_IRQS            (1),
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
    .clk                        (clk_gated_cpu),
    .clk_always_on              (clk_sys),
    .rst_n                      (rst_n_cpu),

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
// Bus components

// APU nominally has a 128 kB address space, mapped at c0000 to dffff in the
// system address space. We actually just decode the 16 LSBs: RAM in the lower
// 32k and up to 8 x 4k peripherals in the upper 32k.

wire [15:0] ram_haddr;
wire        ram_hwrite;
wire [1:0]  ram_htrans;
wire [2:0]  ram_hsize;
wire [2:0]  ram_hburst;
wire [3:0]  ram_hprot;
wire        ram_hmastlock;
wire [7:0]  ram_hmaster;
wire        ram_hready;
wire        ram_hready_resp;
wire        ram_hresp;
wire [31:0] ram_hwdata;
wire [31:0] ram_hrdata;

wire [15:0] ipc_haddr;
wire        ipc_hwrite;
wire [1:0]  ipc_htrans;
wire [2:0]  ipc_hsize;
wire [2:0]  ipc_hburst;
wire [3:0]  ipc_hprot;
wire        ipc_hmastlock;
wire [7:0]  ipc_hmaster;
wire        ipc_hready;
wire        ipc_hready_resp;
wire        ipc_hresp;
wire [31:0] ipc_hwdata;
wire [31:0] ipc_hrdata;

wire [15:0] aout_haddr;
wire        aout_hwrite;
wire [1:0]  aout_htrans;
wire [2:0]  aout_hsize;
wire [2:0]  aout_hburst;
wire [3:0]  aout_hprot;
wire        aout_hmastlock;
wire [7:0]  aout_hmaster;
wire        aout_hready;
wire        aout_hready_resp;
wire        aout_hresp;
wire [31:0] aout_hwdata;
wire [31:0] aout_hrdata;

wire [15:0] timer_haddr;
wire        timer_hwrite;
wire [1:0]  timer_htrans;
wire [2:0]  timer_hsize;
wire [2:0]  timer_hburst;
wire [3:0]  timer_hprot;
wire        timer_hmastlock;
wire [7:0]  timer_hmaster;
wire        timer_hready;
wire        timer_hready_resp;
wire        timer_hresp;
wire [31:0] timer_hwdata;
wire [31:0] timer_hrdata;

ahbl_splitter #(
    .N_PORTS   (3),
    .W_ADDR    (16),
    .ADDR_MAP  ({16'ha000, 16'h9000, 16'h8000, 16'h0000}),
    .ADDR_MASK ({16'hf000, 16'hf000, 16'hf000, 16'h8000})
) splitter_u (
    .clk             (clk_sys),
    .rst_n           (rst_n_sys),

    .src_hready      (cpu_hready),
    .src_hready_resp (cpu_hready),
    .src_hresp       (cpu_hresp),
    .src_hexokay     (cpu_hexokay),
    .src_haddr       (cpu_haddr[15:0]),
    .src_hwrite      (cpu_hwrite),
    .src_htrans      (cpu_htrans),
    .src_hsize       (cpu_hsize),
    .src_hburst      (cpu_hburst),
    .src_hprot       (cpu_hprot),
    .src_hmaster     (cpu_hmaster),
    .src_hmastlock   (cpu_hmastlock),
    .src_hexcl       (cpu_hexcl),
    .src_hwdata      (cpu_hwdata),
    .src_hrdata      (cpu_hrdata),

    .dst_hexokay     ('0),
    .dst_hexcl       (/* unused */),

    .dst_hready      ({timer_hready      , aout_hready      , ipc_hready      , ram_hready     }),
    .dst_hready_resp ({timer_hready_resp , aout_hready_resp , ipc_hready_resp , ram_hready_resp}),
    .dst_hresp       ({timer_hresp       , aout_hresp       , ipc_hresp       , ram_hresp      }),
    .dst_haddr       ({timer_haddr       , aout_haddr       , ipc_haddr       , ram_haddr      }),
    .dst_hwrite      ({timer_hwrite      , aout_hwrite      , ipc_hwrite      , ram_hwrite     }),
    .dst_htrans      ({timer_htrans      , aout_htrans      , ipc_htrans      , ram_htrans     }),
    .dst_hsize       ({timer_hsize       , aout_hsize       , ipc_hsize       , ram_hsize      }),
    .dst_hburst      ({timer_hburst      , aout_hburst      , ipc_hburst      , ram_hburst     }),
    .dst_hprot       ({timer_hprot       , aout_hprot       , ipc_hprot       , ram_hprot      }),
    .dst_hmaster     ({timer_hmaster     , aout_hmaster     , ipc_hmaster     , ram_hmaster    }),
    .dst_hmastlock   ({timer_hmastlock   , aout_hmastlock   , ipc_hmastlock   , ram_hmastlock  }),
    .dst_hwdata      ({timer_hwdata      , aout_hwdata      , ipc_hwdata      , ram_hwdata     }),
    .dst_hrdata      ({timer_hrdata      , aout_hrdata      , ipc_hrdata      , ram_hrdata     })
);

// ------------------------------------------------------------------------
// Memories

ahb_sync_sram #(
    .W_DATA (32),
    .W_ADDR (16),
    .DEPTH  (RAM_DEPTH)
) ram_u (
    .VDD               (VDD),
    .VSS               (VSS),
    .clk               (clk_sys),
    .rst_n             (rst_n_sys),

    .ahbls_hready_resp (ram_hready_resp),
    .ahbls_hready      (ram_hready),
    .ahbls_hresp       (ram_hresp),
    .ahbls_haddr       (ram_haddr),
    .ahbls_hwrite      (ram_hwrite),
    .ahbls_htrans      (ram_htrans),
    .ahbls_hsize       (ram_hsize),
    .ahbls_hburst      (ram_hburst),
    .ahbls_hprot       (ram_hprot),
    .ahbls_hmastlock   (ram_hmastlock),
    .ahbls_hwdata      (ram_hwdata),
    .ahbls_hrdata      (ram_hrdata)
);

// ----------------------------------------------------------------------------
// Peripheral registers

apu_ipc ipc_u (
    .clk               (clk_sys),
    .rst_n             (rst_n_sys),

    .ahbls_haddr       (ipc_haddr),
    .ahbls_htrans      (ipc_htrans),
    .ahbls_hwrite      (ipc_hwrite),
    .ahbls_hsize       (ipc_hsize),
    .ahbls_hready      (ipc_hready),
    .ahbls_hready_resp (ipc_hready_resp),
    .ahbls_hwdata      (ipc_hwdata),
    .ahbls_hrdata      (ipc_hrdata),
    .ahbls_hresp       (ipc_hresp),

    .start_apu         (start_apu),

    .riscv_softirq     ({soft_irq, irq_cpu_softirq})
);

apu_timer timer_u (
    .clk               (clk_sys),
    .rst_n             (rst_n_sys),

    .ahbls_haddr       (timer_haddr),
    .ahbls_htrans      (timer_htrans),
    .ahbls_hwrite      (timer_hwrite),
    .ahbls_hsize       (timer_hsize),
    .ahbls_hready      (timer_hready),
    .ahbls_hready_resp (timer_hready_resp),
    .ahbls_hwdata      (timer_hwdata),
    .ahbls_hrdata      (timer_hrdata),
    .ahbls_hresp       (timer_hresp),

    .irq               (timer_irq)
);


// ----------------------------------------------------------------------------
// Sample FIFO and AOUT control interface

wire [31:0] aout_fifo_wdata;
wire        aout_fifo_wpush;
wire        aout_fifo_wfull;
wire        aout_fifo_wempty;
wire [2:0]  aout_fifo_wlevel;

wire        aout_csr_signed;
wire        aout_csr_running;
wire        aout_csr_enable;
wire [7:0]  aout_csr_interval;
wire [2:0]  aout_csr_irqlevel;

wire [15:0] aout_fifo_l_wdata;
wire        aout_fifo_l_wen;
wire [15:0] aout_fifo_r_wdata;
wire        aout_fifo_r_wen;

assign aout_fifo_wpush = aout_fifo_l_wen || aout_fifo_r_wen;
assign aout_fifo_wdata =
    {aout_csr_signed, 15'd0, aout_csr_signed, 15'd0} ^
    {     aout_fifo_l_wdata,      aout_fifo_r_wdata};

assign irq = aout_fifo_wlevel <= aout_csr_irqlevel;

apu_aout_regs aout_regs_u (
    .clk               (clk_sys),
    .rst_n             (rst_n_sys),

    .ahbls_haddr       (aout_haddr),
    .ahbls_htrans      (aout_htrans),
    .ahbls_hwrite      (aout_hwrite),
    .ahbls_hsize       (aout_hsize),
    .ahbls_hready      (aout_hready),
    .ahbls_hready_resp (aout_hready_resp),
    .ahbls_hwdata      (aout_hwdata),
    .ahbls_hrdata      (aout_hrdata),
    .ahbls_hresp       (aout_hresp),

    .csr_rdy_i         (!aout_fifo_wfull),
    .csr_signed_o      (aout_csr_signed),
    .csr_running_i     (aout_csr_running),
    .csr_enable_o      (aout_csr_enable),
    .csr_interval_o    (aout_csr_interval),
    .csr_irqlevel_o    (aout_csr_irqlevel),
    .csr_flevel_i      (aout_fifo_wlevel),

    .fifo_l_o          (aout_fifo_l_wdata),
    .fifo_l_wen        (aout_fifo_l_wen),
    .fifo_r_o          (aout_fifo_r_wdata),
    .fifo_r_wen        (aout_fifo_r_wen)
);

wire [31:0] aout_fifo_rdata;
wire        aout_fifo_rpop;
wire        aout_fifo_rfull;
wire        aout_fifo_rempty;
wire [2:0]  aout_fifo_rlevel;

async_fifo #(
    .W_DATA (32),
    .W_ADDR (2)
) aout_fifo_u (
    .wrst_n (rst_n_sys),
    .wclk   (clk_sys),

    .wdata  (aout_fifo_wdata),
    .wpush  (aout_fifo_wpush),
    .wfull  (aout_fifo_wfull),
    .wempty (aout_fifo_wempty),
    .wlevel (aout_fifo_wlevel),

    .rrst_n (rst_n_audio),
    .rclk   (clk_audio),

    .rdata  (aout_fifo_rdata),
    .rpop   (aout_fifo_rpop),
    .rfull  (aout_fifo_rfull),
    .rempty (aout_fifo_rempty),
    .rlevel (aout_fifo_rlevel)
);

// ----------------------------------------------------------------------------
// Digital audio output (AOUT)

wire        aout_csr_enable_resync;
wire [7:0]  aout_csr_interval_resync;

sync_1bit sync_aout_enable_u (
    .clk   (clk_audio),
    .rst_n (rst_n_audio),
    .i     (aout_csr_enable),
    .o     (aout_csr_enable_resync)
);

// 2DFF used on multi-bit: ok as this should only change when software has
// cleared ENABLE then polled RUNNING low.
sync_1bit sync_aout_interval_u [7:0] (
    .clk   (clk_audio),
    .rst_n (rst_n_audio),
    .i     (aout_csr_interval),
    .o     (aout_csr_interval_resync)
);

// Return synchronised ENABLE as RUNNING
sync_1bit sync_aout_running_u (
    .clk   (clk_sys),
    .rst_n (rst_n_sys),
    .i     (aout_csr_enable_resync),
    .o     (aout_csr_running)
);

apu_aout apu_aout_u (
    .clk             (clk_audio),
    .rst_n           (rst_n_audio),
    .en              (aout_csr_enable_resync),
    .repeat_interval (aout_csr_interval_resync),
    .sample          (aout_fifo_rdata),
    .sample_rdy      (aout_fifo_rpop),
    .pwm_l           (audio_l),
    .pwm_r           (audio_r)
);

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
