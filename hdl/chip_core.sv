/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

// useless:
/* verilator lint_off PINCONNECTEMPTY */

module chip_core #(
    parameter N_SRAM_DQ = 16,
    parameter N_SRAM_A  = 17,
    parameter N_GPIO    = 7
) (
    inout  wire                 VDD,
    inout  wire                 VSS,

    // Global signal from core to enable outputs on output-only pins
    output wire                 enable_fixed_outputs,

    // Root clock/reset
    input  wire                 padin_clk,
    input  wire                 padin_rst_n,

    // Debug
    input  wire                 padin_dck,
    input  wire                 padin_dio,
    output wire                 padoe_dio,
    output wire                 padout_dio,

    // SRAM signals
    input  wire [N_SRAM_DQ-1:0] padin_sram_dq,
    output wire [N_SRAM_DQ-1:0] padoe_sram_dq,
    output wire [N_SRAM_DQ-1:0] padout_sram_dq,
    output wire [N_SRAM_A-1:0]  padout_sram_a,
    output wire                 padout_sram_oe_n,
    output wire                 padout_sram_cs_n,
    output wire                 padout_sram_we_n,
    output wire                 padout_sram_ub_n,
    output wire                 padout_sram_lb_n,

    // Audio PWM signals (output only)
    output wire                 padout_audio_l,
    output wire                 padout_audio_r,

    // LCD signals (output only)
    output wire                 padout_lcd_clk,
    output wire                 padout_lcd_dat,
    output wire                 padout_lcd_cs_n,
    output wire                 padout_lcd_dc,
    output wire                 padout_lcd_bl,

    // GPIO signals (bidirectional)
    input  wire [N_GPIO-1:0]    padin_gpio,
    output wire [N_GPIO-1:0]    padoe_gpio,
    output wire [N_GPIO-1:0]    padout_gpio,

    // Auxiliary pad controls
    // Output-only pads lack Schmitt control.
    output wire                 dio_schmitt,
    output wire                 dio_slew,
    output wire [1:0]           dio_drive,

    output wire                 sram_dq_schmitt,
    output wire                 sram_dq_slew,
    output wire [1:0]           sram_dq_drive,

    output wire                 sram_a_slew,
    output wire [1:0]           sram_a_drive,

    output wire                 sram_strobe_slew,
    output wire [1:0]           sram_strobe_drive,

    output wire                 audio_slew,
    output wire [1:0]           audio_drive,

    output wire                 lcd_clk_slew,
    output wire [1:0]           lcd_clk_drive,

    output wire                 lcd_dat_slew,
    output wire [1:0]           lcd_dat_drive,

    output wire                 lcd_dccs_slew,
    output wire [1:0]           lcd_dccs_drive,

    output wire                 lcd_bl_slew,
    output wire [1:0]           lcd_bl_drive,

    output wire                 gpio_schmitt,
    output wire                 gpio_slew,
    output wire [1:0]           gpio_drive,

    output wire [6:0]           gpio_pu,
    output wire [6:0]           gpio_pd
);

// ------------------------------------------------------------------------

// External pad is our stand-in for a PoR.
wire rst_n_por;
falsepath_anchor fp_rst_n_u (
    .i (padin_rst_n),
    .z (rst_n_por)
);

// External clock used directly as system clock (for now).
wire clk_sys;
clkroot_anchor clkroot_sys_u (
    .i (padin_clk),
    .z (clk_sys)
);

// ------------------------------------------------------------------------
// Debug Transport Module

// DTM reset is synchronised to DTM clock. The spec allows for this by
// allowing the DTM to ignore the leading zeroes on the Connect sequence (they
// are just there to sync the LFSR).
wire        drst_n;
reset_sync #(
    .N_CYCLES (3)
) sync_drst_n_u (
    .clk       (padin_dck),
    .rst_n_in  (rst_n_por),
    .rst_n_out (drst_n)
);

// DTM downstream bus (DCK domain). Note the address from the DTM is a word
// address, not a byte address.
wire [7:0]  dtm_dst_paddr;
wire        dtm_dst_psel;
wire        dtm_dst_penable;
wire        dtm_dst_pwrite;
wire        dtm_dst_pready;
wire        dtm_dst_pslverr;
wire [31:0] dtm_dst_pwdata;
wire [31:0] dtm_dst_prdata;

wire        ndtmresetreq;
wire        ndtmresetack;

twowire_dtm #(
    .IDCODE (32'hdeadbeef), // TODO this is a real company
    .ASIZE  (0)             // TODO mark presence of debug module
) dtm_u (
    .dck            (padin_dck),
    .drst_n         (drst_n),
    .dout           (padout_dio),
    .doe            (padoe_dio),
    .di             (padin_dio),

    .host_connected (/* unused */),
    .ndtmresetreq   (ndtmresetreq),
    .ndtmresetack   (ndtmresetack),

    .ainfo_present  (1'b0),

    .dst_paddr      (dtm_dst_paddr),
    .dst_psel       (dtm_dst_psel),
    .dst_penable    (dtm_dst_penable),
    .dst_pwrite     (dtm_dst_pwrite),
    .dst_pready     (dtm_dst_pready),
    .dst_pslverr    (dtm_dst_pslverr),
    .dst_pwdata     (dtm_dst_pwdata),
    .dst_prdata     (dtm_dst_prdata)
);

// ------------------------------------------------------------------------
// Generate system reset based on PoR (pad) reset and the global reset output
// from the debug transport module.

wire ndtmresetreq_fp;
falsepath_anchor fp_ndtmresetreq_u (
    .i (ndtmresetreq),
    .z (ndtmresetreq_fp)
);

wire rst_n_sys_unsync = rst_n_por && !ndtmresetreq_fp;

wire rst_n_sys;
reset_sync #(
    .N_CYCLES (3)
) sync_root_rst_n_u (
    .clk       (clk_sys),
    .rst_n_in  (rst_n_sys_unsync),
    .rst_n_out (rst_n_sys)
);

// Fixed outputs are enabled once the system is out of reset. This is
// falsepathed because it only transitions once and has high fanout.

falsepath_anchor fp_fixed_output_enable_u (
    .i (rst_n_sys),
    .z (enable_fixed_outputs)
);

sync_1bit sync_ndtmresetac_u (
    .clk   (padin_dck),
    .rst_n (drst_n),
    .i     (rst_n_sys),
    .o     (ndtmresetack)
);

// ------------------------------------------------------------------------
// Clock crossing: DTM (DCK) to DM (clk_sys)

wire        dmi_psel;
wire        dmi_penable;
wire        dmi_pwrite;
wire [9:0]  dmi_paddr;
wire [31:0] dmi_pwdata;
wire [31:0] dmi_prdata;
wire        dmi_pready;
wire        dmi_pslverr;

// This is a Hazard3 component normally hidden inside the JTAG-DTM, but we can
// use it standalone.
hazard3_apb_async_bridge #(
    .W_ADDR        (8),
    .W_DATA        (32),
    .N_SYNC_STAGES (2)
) dtm_async_bridge_u (
    .clk_src     (padin_dck),
    .rst_n_src   (drst_n),

    .clk_dst     (clk_sys),
    .rst_n_dst   (rst_n_sys),

    .src_psel    (dtm_dst_psel),
    .src_penable (dtm_dst_penable),
    .src_pwrite  (dtm_dst_pwrite),
    .src_paddr   (dtm_dst_paddr),
    .src_pwdata  (dtm_dst_pwdata),
    .src_prdata  (dtm_dst_prdata),
    .src_pready  (dtm_dst_pready),
    .src_pslverr (dtm_dst_pslverr),

    .dst_psel    (dmi_psel),
    .dst_penable (dmi_penable),
    .dst_pwrite  (dmi_pwrite),
    .dst_paddr   (dmi_paddr[9:2]),
    .dst_pwdata  (dmi_pwdata),
    .dst_prdata  (dmi_prdata),
    .dst_pready  (dmi_pready),
    .dst_pslverr (dmi_pslverr)
);

assign dmi_paddr[1:0] = 2'b00;

// ------------------------------------------------------------------------
// Debug Module and processor reset control

wire        sys_reset_req;
wire        hart_reset_req;
wire        rst_n_cpu;
wire        rst_n_cpu_unsync = rst_n_sys && !(sys_reset_req || hart_reset_req);

reset_sync #(
    .N_CYCLES (3)
) sync_rst_n_cpu (
    .clk       (clk_sys),
    .rst_n_in  (rst_n_cpu_unsync),
    .rst_n_out (rst_n_cpu)
);

wire sys_reset_done = rst_n_cpu;
wire hart_reset_done = rst_n_cpu;

wire        dbg_req_halt;
wire        dbg_req_halt_on_reset;
wire        dbg_req_resume;
wire        dbg_halted;
wire        dbg_running;
wire [31:0] dbg_data0_rdata;
wire [31:0] dbg_data0_wdata;
wire        dbg_data0_wen;
wire [31:0] dbg_instr_data;
wire        dbg_instr_data_vld;
wire        dbg_instr_data_rdy;
wire        dbg_instr_caught_exception;
wire        dbg_instr_caught_ebreak;

hazard3_dm #(
    .N_HARTS  (1),
    .HAVE_SBA (0)
) dm_u (
    .clk                         (clk_sys),
    .rst_n                       (rst_n_sys),

    .dmi_psel                    (dmi_psel),
    .dmi_penable                 (dmi_penable),
    .dmi_pwrite                  (dmi_pwrite),
    .dmi_paddr                   (dmi_paddr[8:0]),
    .dmi_pwdata                  (dmi_pwdata),
    .dmi_prdata                  (dmi_prdata),
    .dmi_pready                  (dmi_pready),
    .dmi_pslverr                 (dmi_pslverr),

    .sys_reset_req               (sys_reset_req),
    .sys_reset_done              (sys_reset_done),

    .hart_reset_req              (hart_reset_req),
    .hart_reset_done             (hart_reset_done),

    .hart_req_halt               (dbg_req_halt),
    .hart_req_halt_on_reset      (dbg_req_halt_on_reset),
    .hart_req_resume             (dbg_req_resume),
    .hart_halted                 (dbg_halted),
    .hart_running                (dbg_running),
    .hart_data0_rdata            (dbg_data0_rdata),
    .hart_data0_wdata            (dbg_data0_wdata),
    .hart_data0_wen              (dbg_data0_wen),
    .hart_instr_data             (dbg_instr_data),
    .hart_instr_data_vld         (dbg_instr_data_vld),
    .hart_instr_data_rdy         (dbg_instr_data_rdy),
    .hart_instr_caught_exception (dbg_instr_caught_exception),
    .hart_instr_caught_ebreak    (dbg_instr_caught_ebreak),

    .sbus_addr                   (/* unused */),
    .sbus_write                  (/* unused */),
    .sbus_size                   (/* unused */),
    .sbus_vld                    (/* unused */),
    .sbus_rdy                    (1'b1),
    .sbus_err                    (1'b1),
    .sbus_wdata                  (/* unused */),
    .sbus_rdata                  (32'd0)
);

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
    .clk                        (clk_sys),
    .clk_always_on              (clk_sys), // FIXME clock gating
    .rst_n                      (rst_n_sys),

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

    .dbg_sbus_addr              (32'd0),
    .dbg_sbus_write             (1'b0),
    .dbg_sbus_size              (2'h0),
    .dbg_sbus_vld               (1'b0),
    .dbg_sbus_rdy               (/* unused */),
    .dbg_sbus_err               (/* unused */),
    .dbg_sbus_wdata             (32'd0),
    .dbg_sbus_rdata             (/* unused */),

    .mhartid_val                (32'd0),
    .eco_version                (4'd0), // FIXME tie cells

    .irq                        (irq),
    .soft_irq                   (soft_irq),
    .timer_irq                  (timer_irq)
);

// ------------------------------------------------------------------------
// Memories

ahb_sync_sram #(
    .W_DATA (32),
    .DEPTH  (2048)
) iwram_u (
`ifdef USE_POWER_PINS
    .VDD               (VDD),
    .VSS               (VSS),
`endif
    .clk               (clk_sys),
    .rst_n             (rst_n_sys),

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

// ------------------------------------------------------------------------
// Tie off unused outputs

// Disable outputs
assign padoe_sram_dq     = {N_SRAM_DQ{1'b0}};
assign padout_sram_dq    = {N_SRAM_DQ{1'b0}};
assign padout_sram_a     = {N_SRAM_A{1'b0}};
assign padout_sram_oe_n  = 1'b0;
assign padout_sram_cs_n  = 1'b0;
assign padout_sram_we_n  = 1'b0;
assign padout_sram_ub_n  = 1'b0;
assign padout_sram_lb_n  = 1'b0;
assign padout_audio_l    = 1'b0;
assign padout_audio_r    = 1'b0;
assign padout_lcd_clk    = 1'b0;
assign padout_lcd_dat    = 1'b0;
assign padout_lcd_cs_n   = 1'b0;
assign padout_lcd_dc     = 1'b0;
assign padout_lcd_bl     = 1'b0;
assign padoe_gpio        = {N_GPIO{1'b0}};
assign padout_gpio       = {N_GPIO{1'b0}};

// Minimum drive
assign dio_drive         = 2'd0;
assign sram_dq_drive     = 2'd0;
assign sram_a_drive      = 2'd0;
assign sram_strobe_drive = 2'd0;
assign audio_drive       = 2'd0;
assign lcd_clk_drive     = 2'd0;
assign lcd_dat_drive     = 2'd0;
assign lcd_dccs_drive    = 2'd0;
assign lcd_bl_drive      = 2'd0;
assign gpio_drive        = 2'd0;

// Enable Schmitt
assign dio_schmitt      = 1'b1;
assign sram_dq_schmitt  = 1'b1;
assign gpio_schmitt     = 1'b1;

// Slow slew
assign dio_slew         = 1'b1;
assign sram_dq_slew     = 1'b1;
assign sram_a_slew      = 1'b1;
assign sram_strobe_slew = 1'b1;
assign audio_slew       = 1'b1;
assign lcd_clk_slew     = 1'b1;
assign lcd_dat_slew     = 1'b1;
assign lcd_dccs_slew    = 1'b1;
assign lcd_bl_slew      = 1'b1;
assign gpio_slew        = 1'b1;

assign gpio_pu = 7'h00;
assign gpio_pd = 7'h3f;

endmodule

`default_nettype wire
