/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

// useless:
/* verilator lint_off PINCONNECTEMPTY */

module chip_core #(
    parameter N_SRAM_DQ = 16,
    parameter N_SRAM_A  = 18,
    parameter N_GPIO    = 6
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
    output wire                 padoe_audio_l,
    output wire                 padoe_audio_r,
    output wire                 padin_audio_l,
    output wire                 padin_audio_r,

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

    output wire                 audio_schmitt,
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

    output wire [N_GPIO-1:0]    gpio_pu,
    output wire [N_GPIO-1:0]    gpio_pd,
    output wire                 audio_l_pu,
    output wire                 audio_l_pd,
    output wire                 audio_r_pu,
    output wire                 audio_r_pd
);

// ------------------------------------------------------------------------

// External clock used directly as system clock (for now).
wire clk_sys;
clkroot_anchor clkroot_sys_u (
    .i (padin_clk),
    .z (clk_sys)
);

// External clock used directly as LCD serial clock (for now).
wire clk_lcd;
clkroot_anchor clkroot_lcd_u (
    .i (padin_clk),
    .z (clk_lcd)
);

// External clock used directly as audio clock (for now).
wire clk_audio;
clkroot_anchor clkroot_audio_u (
    .i (padin_clk),
    .z (clk_audio)
);

// ------------------------------------------------------------------------
// Debug Transport Module

// DTM reset is synchronised to DTM clock. The spec allows for this by
// allowing the DTM to ignore the leading zeroes on the Connect sequence (they
// are just there to sync the LFSR).
wire        drst_n;
reset_sync sync_drst_n_u (
    .clk       (padin_dck),
    .rst_n_in  (padin_rst_n),
    .rst_n_out (drst_n)
);

// DTM downstream bus (DCK domain). Note the address from the DTM is a word
// address, not a byte address.
wire [9:0]  dtm_dst_paddr;
wire        dtm_dst_psel;
wire        dtm_dst_penable;
wire        dtm_dst_pwrite;
wire        dtm_dst_pready;
wire        dtm_dst_pslverr;
wire [31:0] dtm_dst_pwdata;
wire [31:0] dtm_dst_prdata;

wire        dtm_connected;

wire        ndtmresetreq;
wire        ndtmresetack;

assign dtm_dst_paddr[1:0] = 2'b00;

twowire_dtm #(
    .IDCODE (32'h00280035), // Mfr Zilog, Part 280
    .ASIZE  (0) 
) dtm_u (
    .dck            (padin_dck),
    .drst_n         (drst_n),
    .dout           (padout_dio),
    .doe            (padoe_dio),
    .di             (padin_dio),

    .host_connected (dtm_connected),
    .ndtmresetreq   (ndtmresetreq),
    .ndtmresetack   (ndtmresetack),

    .ainfo_present  (1'b0),

    .dst_paddr      (dtm_dst_paddr[9:2]),
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

wire rst_n_sys_unsync = padin_rst_n && !ndtmresetreq_fp;

wire rst_n_sys;
reset_sync sync_root_rst_n_u (
    .clk       (clk_sys),
    .rst_n_in  (rst_n_sys_unsync),
    .rst_n_out (rst_n_sys)
);

wire rst_n_lcd;
reset_sync sync_lcd_rst_n_u (
    .clk       (clk_lcd),
    .rst_n_in  (rst_n_sys_unsync),
    .rst_n_out (rst_n_lcd)
);

wire rst_n_audio;
reset_sync sync_audio_rst_n_u (
    .clk       (clk_audio),
    .rst_n_in  (rst_n_sys_unsync),
    .rst_n_out (rst_n_audio)
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
// Split VUART APB before async bridge

// (VUART is accessed directly from the DTM; everything else goes via the
// RISC-V Debug Module which is in the core clock domain)

wire [9:0]  dtm_to_bridge_paddr;
wire        dtm_to_bridge_psel;
wire        dtm_to_bridge_penable;
wire        dtm_to_bridge_pwrite;
wire        dtm_to_bridge_pready;
wire        dtm_to_bridge_pslverr;
wire [31:0] dtm_to_bridge_pwdata;
wire [31:0] dtm_to_bridge_prdata;

wire [9:0]  dtm_to_vuart_paddr;
wire        dtm_to_vuart_psel;
wire        dtm_to_vuart_penable;
wire        dtm_to_vuart_pwrite;
wire        dtm_to_vuart_pready;
wire        dtm_to_vuart_pslverr;
wire [31:0] dtm_to_vuart_pwdata;
wire [31:0] dtm_to_vuart_prdata;

apb_splitter #(
    .W_ADDR    (10),
    .W_DATA    (32),
    .N_SLAVES  (2),
    .ADDR_MAP  ({10'h200, 10'h000}),
    .ADDR_MASK ({10'h200, 10'h200})
) dtm_apb_splitter_u (
    .apbs_paddr   (dtm_dst_paddr),
    .apbs_psel    (dtm_dst_psel),
    .apbs_penable (dtm_dst_penable),
    .apbs_pwrite  (dtm_dst_pwrite),
    .apbs_pwdata  (dtm_dst_pwdata),
    .apbs_pready  (dtm_dst_pready),
    .apbs_prdata  (dtm_dst_prdata),
    .apbs_pslverr (dtm_dst_pslverr),

    .apbm_paddr   ({dtm_to_vuart_paddr   , dtm_to_bridge_paddr  }),
    .apbm_psel    ({dtm_to_vuart_psel    , dtm_to_bridge_psel   }),
    .apbm_penable ({dtm_to_vuart_penable , dtm_to_bridge_penable}),
    .apbm_pwrite  ({dtm_to_vuart_pwrite  , dtm_to_bridge_pwrite }),
    .apbm_pwdata  ({dtm_to_vuart_pwdata  , dtm_to_bridge_pwdata }),
    .apbm_pready  ({dtm_to_vuart_pready  , dtm_to_bridge_pready }),
    .apbm_prdata  ({dtm_to_vuart_prdata  , dtm_to_bridge_prdata }),
    .apbm_pslverr ({dtm_to_vuart_pslverr , dtm_to_bridge_pslverr})
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
    .W_ADDR        (10),
    .W_DATA        (32),
    .N_SYNC_STAGES (2)
) dtm_async_bridge_u (
    .clk_src     (padin_dck),
    .rst_n_src   (drst_n),

    .clk_dst     (clk_sys),
    .rst_n_dst   (rst_n_sys),

    .src_psel    (dtm_to_bridge_psel),
    .src_penable (dtm_to_bridge_penable),
    .src_pwrite  (dtm_to_bridge_pwrite),
    .src_paddr   (dtm_to_bridge_paddr),
    .src_pwdata  (dtm_to_bridge_pwdata),
    .src_prdata  (dtm_to_bridge_prdata),
    .src_pready  (dtm_to_bridge_pready),
    .src_pslverr (dtm_to_bridge_pslverr),

    .dst_psel    (dmi_psel),
    .dst_penable (dmi_penable),
    .dst_pwrite  (dmi_pwrite),
    .dst_paddr   (dmi_paddr),
    .dst_pwdata  (dmi_pwdata),
    .dst_prdata  (dmi_prdata),
    .dst_pready  (dmi_pready),
    .dst_pslverr (dmi_pslverr)
);

// ------------------------------------------------------------------------
// Debug Module and processor reset control

wire        sys_reset_req;
wire        sys_reset_done;
wire  [1:0] hart_reset_req;
wire  [1:0] hart_reset_done;
wire        rst_n_cpu;
wire        rst_n_apu;
wire        rst_n_cpu_unsync = rst_n_sys && !(sys_reset_req || hart_reset_req[0]);
wire        rst_n_apu_unsync = rst_n_sys && !(sys_reset_req || hart_reset_req[1]);

reset_sync sync_rst_n_cpu (
    .clk       (clk_sys),
    .rst_n_in  (rst_n_cpu_unsync),
    .rst_n_out (rst_n_cpu)
);

reset_sync sync_rst_n_apu (
    .clk       (clk_sys),
    .rst_n_in  (rst_n_apu_unsync),
    .rst_n_out (rst_n_apu)
);

assign sys_reset_done = rst_n_cpu && rst_n_apu; // TODO async violation (though it's all on clk_sys really)
assign hart_reset_done[0] = rst_n_cpu;
assign hart_reset_done[1] = rst_n_apu;

localparam N_HARTS = 2;

wire [N_HARTS-1:0]    dbg_req_halt;
wire [N_HARTS-1:0]    dbg_req_halt_on_reset;
wire [N_HARTS-1:0]    dbg_req_resume;
wire [N_HARTS-1:0]    dbg_halted;
wire [N_HARTS-1:0]    dbg_running;
wire [32*N_HARTS-1:0] dbg_data0_rdata;
wire [32*N_HARTS-1:0] dbg_data0_wdata;
wire [N_HARTS-1:0]    dbg_data0_wen;
wire [N_HARTS-1:0]    dbg_instr_data_vld;
wire [N_HARTS-1:0]    dbg_instr_data_rdy;
wire [32*N_HARTS-1:0] dbg_instr_data;
wire [N_HARTS-1:0]    dbg_instr_caught_exception;
wire [N_HARTS-1:0]    dbg_instr_caught_ebreak;

hazard3_dm #(
    .N_HARTS  (N_HARTS),
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

localparam IRQ_PPU       = 0;
localparam IRQ_VUART     = 1;
localparam IRQ_APU_AOUT  = 2;
localparam IRQ_APU_TIMER = 3;
localparam NUM_IRQS      = 4;

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
wire                cpu_hexokay;
wire [31:0]         cpu_hwdata;
wire [31:0]         cpu_hrdata;

wire [NUM_IRQS-1:0] irq;
wire                soft_irq;
wire                timer_irq;

wire                fence_i_vld;
wire                fence_d_vld;
wire                fence_rdy = 1'b1;

wire                clk_sys_gated_cpu;

cell_clkgate_low clkgate_cpu_u (
    .clk_in  (clk_sys),
    .enable  (cpu_clk_en),
    .clk_out (clk_sys_gated_cpu)
);

hazard3_cpu_1port #(
    .RESET_VECTOR        (32'h000a0000),
    .MTVEC_INIT          (32'h000a0000),

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
    .EXTENSION_XH3IRQ    (1),
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
    .clk                        (clk_sys_gated_cpu),
    .clk_always_on              (clk_sys),
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

    .dbg_req_halt               (dbg_req_halt[0]),
    .dbg_req_halt_on_reset      (dbg_req_halt_on_reset[0]),
    .dbg_req_resume             (dbg_req_resume[0]),
    .dbg_halted                 (dbg_halted[0]),
    .dbg_running                (dbg_running[0]),
    .dbg_data0_rdata            (dbg_data0_rdata[0 * 32 +: 32]),
    .dbg_data0_wdata            (dbg_data0_wdata[0 * 32 +: 32]),
    .dbg_data0_wen              (dbg_data0_wen[0]),
    .dbg_instr_data             (dbg_instr_data[0 * 32 +: 32]),
    .dbg_instr_data_vld         (dbg_instr_data_vld[0]),
    .dbg_instr_data_rdy         (dbg_instr_data_rdy[0]),
    .dbg_instr_caught_exception (dbg_instr_caught_exception[0]),
    .dbg_instr_caught_ebreak    (dbg_instr_caught_ebreak[0]),

    .dbg_sbus_addr              (32'd0),
    .dbg_sbus_write             (1'b0),
    .dbg_sbus_size              (2'h0),
    .dbg_sbus_vld               (1'b0),
    .dbg_sbus_rdy               (/* unused */),
    .dbg_sbus_err               (/* unused */),
    .dbg_sbus_wdata             (32'd0),
    .dbg_sbus_rdata             (/* unused */),

    .mhartid_val                (32'd0),
    .eco_version                (4'd0),

    .irq                        (irq),
    .soft_irq                   (soft_irq),
    .timer_irq                  (timer_irq)
);

// ------------------------------------------------------------------------
// Bus components

// 1 MB system address space:
//
// 00000 to 7ffff: external SRAM     (up to 512 kB)
// 80000 to 9ffff: internal SRAM     (mirrored across 128 kB)
// a0000 to bffff: boot ROM          (mirrored across 128 kB)
// c0000 to dffff: APU address space (128 kB aperture)
// e0000 to fffff: APB peripherals   (128 kB address space, ~4 kB each)

wire [19:0]         eram_haddr;
wire                eram_hwrite;
wire [1:0]          eram_htrans;
wire [2:0]          eram_hsize;
wire [2:0]          eram_hburst;
wire [3:0]          eram_hprot;
wire                eram_hmastlock;
wire [7:0]          eram_hmaster;
wire                eram_hexcl;
wire                eram_hready;
wire                eram_hready_resp;
wire                eram_hresp;
wire                eram_hexokay;
wire [31:0]         eram_hwdata;
wire [31:0]         eram_hrdata;

wire [19:0]         iram_haddr;
wire                iram_hwrite;
wire [1:0]          iram_htrans;
wire [2:0]          iram_hsize;
wire [2:0]          iram_hburst;
wire [3:0]          iram_hprot;
wire                iram_hmastlock;
wire [7:0]          iram_hmaster;
wire                iram_hexcl;
wire                iram_hready;
wire                iram_hready_resp;
wire                iram_hresp;
wire                iram_hexokay;
wire [31:0]         iram_hwdata;
wire [31:0]         iram_hrdata;

wire [19:0]         rom_haddr;
wire                rom_hwrite;
wire [1:0]          rom_htrans;
wire [2:0]          rom_hsize;
wire [2:0]          rom_hburst;
wire [3:0]          rom_hprot;
wire                rom_hmastlock;
wire [7:0]          rom_hmaster;
wire                rom_hexcl;
wire                rom_hready;
wire                rom_hready_resp;
wire                rom_hresp;
wire                rom_hexokay;
wire [31:0]         rom_hwdata;
wire [31:0]         rom_hrdata;

wire [19:0]         apu_haddr;
wire                apu_hwrite;
wire [1:0]          apu_htrans;
wire [2:0]          apu_hsize;
wire [2:0]          apu_hburst;
wire [3:0]          apu_hprot;
wire                apu_hmastlock;
wire [7:0]          apu_hmaster;
wire                apu_hexcl;
wire                apu_hready;
wire                apu_hready_resp;
wire                apu_hresp;
wire                apu_hexokay;
wire [31:0]         apu_hwdata;
wire [31:0]         apu_hrdata;

wire [19:0]         apb_haddr;
wire                apb_hwrite;
wire [1:0]          apb_htrans;
wire [2:0]          apb_hsize;
wire [2:0]          apb_hburst;
wire [3:0]          apb_hprot;
wire                apb_hmastlock;
wire [7:0]          apb_hmaster;
wire                apb_hexcl;
wire                apb_hready;
wire                apb_hready_resp;
wire                apb_hresp;
wire                apb_hexokay;
wire [31:0]         apb_hwdata;
wire [31:0]         apb_hrdata;

// Tie off exclusive responses (harmless if A extension is deselected).
// Exclusives always fail on APU memory and always pass elsewhere.
assign eram_hexokay = 1'b1;
assign iram_hexokay = 1'b1;
assign rom_hexokay  = 1'b0;
assign apu_hexokay  = 1'b0;
assign apb_hexokay  = 1'b1;

ahbl_splitter #(
    .N_PORTS   (5),
    .W_ADDR    (20),
    .W_DATA    (32),
    .ADDR_MAP  (100'he0000_c0000_a0000_80000_00000),
    .ADDR_MASK (100'he0000_e0000_e0000_e0000_80000)
) splitter_u (
    .clk             (clk_sys),
    .rst_n           (rst_n_sys),

    .src_hready      (cpu_hready),
    .src_hready_resp (cpu_hready),
    .src_hresp       (cpu_hresp),
    .src_hexokay     (cpu_hexokay),
    .src_haddr       (cpu_haddr[19:0]),
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

    .dst_hready      ({apb_hready      , apu_hready      , rom_hready      , iram_hready      , eram_hready     }),
    .dst_hready_resp ({apb_hready_resp , apu_hready_resp , rom_hready_resp , iram_hready_resp , eram_hready_resp}),
    .dst_hresp       ({apb_hresp       , apu_hresp       , rom_hresp       , iram_hresp       , eram_hresp      }),
    .dst_hexokay     ({apb_hexokay     , apu_hexokay     , rom_hexokay     , iram_hexokay     , eram_hexokay    }),
    .dst_haddr       ({apb_haddr       , apu_haddr       , rom_haddr       , iram_haddr       , eram_haddr      }),
    .dst_hwrite      ({apb_hwrite      , apu_hwrite      , rom_hwrite      , iram_hwrite      , eram_hwrite     }),
    .dst_htrans      ({apb_htrans      , apu_htrans      , rom_htrans      , iram_htrans      , eram_htrans     }),
    .dst_hsize       ({apb_hsize       , apu_hsize       , rom_hsize       , iram_hsize       , eram_hsize      }),
    .dst_hburst      ({apb_hburst      , apu_hburst      , rom_hburst      , iram_hburst      , eram_hburst     }),
    .dst_hprot       ({apb_hprot       , apu_hprot       , rom_hprot       , iram_hprot       , eram_hprot      }),
    .dst_hmaster     ({apb_hmaster     , apu_hmaster     , rom_hmaster     , iram_hmaster     , eram_hmaster    }),
    .dst_hmastlock   ({apb_hmastlock   , apu_hmastlock   , rom_hmastlock   , iram_hmastlock   , eram_hmastlock  }),
    .dst_hexcl       ({apb_hexcl       , apu_hexcl       , rom_hexcl       , iram_hexcl       , eram_hexcl      }),
    .dst_hwdata      ({apb_hwdata      , apu_hwdata      , rom_hwdata      , iram_hwdata      , eram_hwdata     }),
    .dst_hrdata      ({apb_hrdata      , apu_hrdata      , rom_hrdata      , iram_hrdata      , eram_hrdata     })
);

wire [19:0] peri_paddr;
wire        peri_psel;
wire        peri_penable;
wire        peri_pwrite;
wire [31:0] peri_pwdata;
wire        peri_pready;
wire [31:0] peri_prdata;
wire        peri_pslverr;

ahbl_to_apb #(
    .W_HADDR (20),
    .W_PADDR (20),
    .W_DATA  (32)
) inst_ahbl_to_apb (
    .clk               (clk_sys),
    .rst_n             (rst_n_sys),

    .ahbls_haddr       (apb_haddr),
    .ahbls_hwrite      (apb_hwrite),
    .ahbls_htrans      (apb_htrans),
    .ahbls_hsize       (apb_hsize),
    .ahbls_hburst      (apb_hburst),
    .ahbls_hprot       (apb_hprot),
    .ahbls_hmastlock   (apb_hmastlock),
    .ahbls_hwdata      (apb_hwdata),
    .ahbls_hready      (apb_hready),
    .ahbls_hready_resp (apb_hready_resp),
    .ahbls_hresp       (apb_hresp),
    .ahbls_hrdata      (apb_hrdata),

    .apbm_paddr        (peri_paddr),
    .apbm_psel         (peri_psel),
    .apbm_penable      (peri_penable),
    .apbm_pwrite       (peri_pwrite),
    .apbm_pwdata       (peri_pwdata),
    .apbm_pready       (peri_pready),
    .apbm_prdata       (peri_prdata),
    .apbm_pslverr      (peri_pslverr)
);

wire [19:0] timer_paddr;
wire        timer_psel;
wire        timer_penable;
wire        timer_pwrite;
wire [31:0] timer_pwdata;
wire        timer_pready;
wire [31:0] timer_prdata;
wire        timer_pslverr;

wire [19:0] padctrl_paddr;
wire        padctrl_psel;
wire        padctrl_penable;
wire        padctrl_pwrite;
wire [31:0] padctrl_pwdata;
wire        padctrl_pready;
wire [31:0] padctrl_prdata;
wire        padctrl_pslverr;

wire [19:0] ppu_paddr;
wire        ppu_psel;
wire        ppu_penable;
wire        ppu_pwrite;
wire [31:0] ppu_pwdata;
wire        ppu_pready;
wire [31:0] ppu_prdata;
wire        ppu_pslverr;

wire [19:0] dispctrl_paddr;
wire        dispctrl_psel;
wire        dispctrl_penable;
wire        dispctrl_pwrite;
wire [31:0] dispctrl_pwdata;
wire        dispctrl_pready;
wire [31:0] dispctrl_prdata;
wire        dispctrl_pslverr;

wire [19:0] lcd_pwm_paddr;
wire        lcd_pwm_psel;
wire        lcd_pwm_penable;
wire        lcd_pwm_pwrite;
wire [31:0] lcd_pwm_pwdata;
wire        lcd_pwm_pready;
wire [31:0] lcd_pwm_prdata;
wire        lcd_pwm_pslverr;

wire [19:0] vuart_dev_paddr;
wire        vuart_dev_psel;
wire        vuart_dev_penable;
wire        vuart_dev_pwrite;
wire [31:0] vuart_dev_pwdata;
wire        vuart_dev_pready;
wire [31:0] vuart_dev_prdata;
wire        vuart_dev_pslverr;

wire [19:0] gpio_paddr;
wire        gpio_psel;
wire        gpio_penable;
wire        gpio_pwrite;
wire [31:0] gpio_pwdata;
wire        gpio_pready;
wire [31:0] gpio_prdata;
wire        gpio_pslverr;

apb_splitter #(
    .W_ADDR    (20),
    .W_DATA    (32),
    .N_SLAVES  (7),
    .ADDR_MAP  ({20'h06000, 20'h05000, 20'h04000, 20'h03000, 20'h02000, 20'h01000, 20'h00000}),
    .ADDR_MASK ({20'h0f000, 20'h0f000, 20'h0f000, 20'h0f000, 20'h0f000, 20'h0f000, 20'h0f000})
) apb_splitter_u (
    .apbs_paddr   (peri_paddr),
    .apbs_psel    (peri_psel),
    .apbs_penable (peri_penable),
    .apbs_pwrite  (peri_pwrite),
    .apbs_pwdata  (peri_pwdata),
    .apbs_pready  (peri_pready),
    .apbs_prdata  (peri_prdata),
    .apbs_pslverr (peri_pslverr),

    .apbm_paddr   ({gpio_paddr   , vuart_dev_paddr   , lcd_pwm_paddr   , dispctrl_paddr   , ppu_paddr   , padctrl_paddr   , timer_paddr  }),
    .apbm_psel    ({gpio_psel    , vuart_dev_psel    , lcd_pwm_psel    , dispctrl_psel    , ppu_psel    , padctrl_psel    , timer_psel   }),
    .apbm_penable ({gpio_penable , vuart_dev_penable , lcd_pwm_penable , dispctrl_penable , ppu_penable , padctrl_penable , timer_penable}),
    .apbm_pwrite  ({gpio_pwrite  , vuart_dev_pwrite  , lcd_pwm_pwrite  , dispctrl_pwrite  , ppu_pwrite  , padctrl_pwrite  , timer_pwrite }),
    .apbm_pwdata  ({gpio_pwdata  , vuart_dev_pwdata  , lcd_pwm_pwdata  , dispctrl_pwdata  , ppu_pwdata  , padctrl_pwdata  , timer_pwdata }),
    .apbm_pready  ({gpio_pready  , vuart_dev_pready  , lcd_pwm_pready  , dispctrl_pready  , ppu_pready  , padctrl_pready  , timer_pready }),
    .apbm_prdata  ({gpio_prdata  , vuart_dev_prdata  , lcd_pwm_prdata  , dispctrl_prdata  , ppu_prdata  , padctrl_prdata  , timer_prdata }),
    .apbm_pslverr ({gpio_pslverr , vuart_dev_pslverr , lcd_pwm_pslverr , dispctrl_pslverr , ppu_pslverr , padctrl_pslverr , timer_pslverr})
);

// ------------------------------------------------------------------------
// Memories

ahb_sync_sram #(
    .W_DATA (32),
    .W_ADDR (20), // this is HADDR, not RAM address
    .DEPTH  (2048)
) iram_u (
    .VDD               (VDD),
    .VSS               (VSS),

    .clk               (clk_sys),
    .rst_n             (rst_n_sys),

    .ahbls_hready_resp (iram_hready_resp),
    .ahbls_hready      (iram_hready),
    .ahbls_hresp       (iram_hresp),
    .ahbls_haddr       (iram_haddr),
    .ahbls_hwrite      (iram_hwrite),
    .ahbls_htrans      (iram_htrans),
    .ahbls_hsize       (iram_hsize),
    .ahbls_hburst      (iram_hburst),
    .ahbls_hprot       (iram_hprot),
    .ahbls_hmastlock   (iram_hmastlock),
    .ahbls_hwdata      (iram_hwdata),
    .ahbls_hrdata      (iram_hrdata)
);

ahb_rom_boot rom_u (
    .clk               (clk_sys),
    .rst_n             (rst_n_sys),

    .ahbls_haddr       (rom_haddr),
    .ahbls_htrans      (rom_htrans),
    .ahbls_hwrite      (rom_hwrite),
    .ahbls_hsize       (rom_hsize),
    .ahbls_hready      (rom_hready),
    .ahbls_hready_resp (rom_hready_resp),
    .ahbls_hwdata      (rom_hwdata),
    .ahbls_hrdata      (rom_hrdata),
    .ahbls_hresp       (rom_hresp)
);

// ------------------------------------------------------------------------
// Audio processing unit

wire audio_l;
wire audio_r;

audio_processor #(
    .RAM_DEPTH (512)
) apu_u (
    .clk_sys                    (clk_sys),
    .rst_n_sys                  (rst_n_sys),
    .rst_n_cpu                  (rst_n_apu),

    .clk_audio                  (clk_audio),
    .rst_n_audio                (rst_n_audio),

    .VDD                        (VDD),
    .VSS                        (VSS),

    .dbg_req_halt               (dbg_req_halt[1]),
    .dbg_req_halt_on_reset      (dbg_req_halt_on_reset[1]),
    .dbg_req_resume             (dbg_req_resume[1]),
    .dbg_halted                 (dbg_halted[1]),
    .dbg_running                (dbg_running[1]),
    .dbg_data0_rdata            (dbg_data0_rdata[1 * 32 +: 32]),
    .dbg_data0_wdata            (dbg_data0_wdata[1 * 32 +: 32]),
    .dbg_data0_wen              (dbg_data0_wen[1]),
    .dbg_instr_data             (dbg_instr_data[1 * 32 +: 32]),
    .dbg_instr_data_vld         (dbg_instr_data_vld[1]),
    .dbg_instr_data_rdy         (dbg_instr_data_rdy[1]),
    .dbg_instr_caught_exception (dbg_instr_caught_exception[1]),
    .dbg_instr_caught_ebreak    (dbg_instr_caught_ebreak[1]),

    .ahbls_haddr                ({12'd0, apu_haddr}),
    .ahbls_hwrite               (apu_hwrite),
    .ahbls_htrans               (apu_htrans),
    .ahbls_hsize                (apu_hsize),
    .ahbls_hready               (apu_hready),
    .ahbls_hready_resp          (apu_hready_resp),
    .ahbls_hresp                (apu_hresp),
    .ahbls_hwdata               (apu_hwdata),
    .ahbls_hrdata               (apu_hrdata),

    .irq_cpu_softirq            (soft_irq),
    .irq_apu_aout_to_cpu        (irq[IRQ_APU_AOUT]),
    .irq_apu_timer_to_cpu       (irq[IRQ_APU_TIMER]),

    .audio_l                    (audio_l),
    .audio_r                    (audio_r)
);

// ------------------------------------------------------------------------
// Pixel processing unit

wire [N_SRAM_A-1:0] ppu_mem_addr;
wire                ppu_mem_addr_vld;
wire                ppu_mem_addr_rdy;
wire [15:0]         ppu_mem_rdata;
wire                ppu_mem_rdata_vld;

wire [8:0]          ppu_scanout_raddr;
wire                ppu_scanout_ren;
wire [15:0]         ppu_scanout_rdata;
wire                ppu_scanout_buf_rdy;
wire                ppu_scanout_buf_release;

riscboy_ppu #(
    .W_MEM_ADDR (N_SRAM_A)
) ppu_u (
    .clk                 (clk_sys),
    .rst_n               (rst_n_sys),

    .VDD                 (VDD),
    .VSS                 (VSS),

    .irq                 (irq[IRQ_PPU]),

    .mem_addr            (ppu_mem_addr),
    .mem_addr_vld        (ppu_mem_addr_vld),
    .mem_addr_rdy        (ppu_mem_addr_rdy),
    .mem_rdata           (ppu_mem_rdata),
    .mem_rdata_vld       (ppu_mem_rdata_vld),

    .apbs_psel           (ppu_psel),
    .apbs_penable        (ppu_penable),
    .apbs_pwrite         (ppu_pwrite),
    .apbs_paddr          (ppu_paddr[15:0]),
    .apbs_pwdata         (ppu_pwdata),
    .apbs_prdata         (ppu_prdata),
    .apbs_pready         (ppu_pready),
    .apbs_pslverr        (ppu_pslverr),

    .scanout_raddr       (ppu_scanout_raddr),
    .scanout_ren         (ppu_scanout_ren),
    .scanout_rdata       (ppu_scanout_rdata),
    .scanout_buf_rdy     (ppu_scanout_buf_rdy),
    .scanout_buf_release (ppu_scanout_buf_release)
);

riscboy_ppu_dispctrl_spi #(
    .PXFIFO_DEPTH (8)
) ppu_dispctrl_spi_u (
    .clk_sys             (clk_sys),
    .rst_n_sys           (rst_n_sys),

    .clk_tx              (clk_lcd),
    .rst_n_tx            (rst_n_lcd),

    .apbs_psel           (dispctrl_psel),
    .apbs_penable        (dispctrl_penable),
    .apbs_pwrite         (dispctrl_pwrite),
    .apbs_paddr          (dispctrl_paddr[15:0]),
    .apbs_pwdata         (dispctrl_pwdata),
    .apbs_prdata         (dispctrl_prdata),
    .apbs_pready         (dispctrl_pready),
    .apbs_pslverr        (dispctrl_pslverr),

    .scanout_raddr       (ppu_scanout_raddr),
    .scanout_ren         (ppu_scanout_ren),
    .scanout_rdata       (ppu_scanout_rdata),
    .scanout_buf_rdy     (ppu_scanout_buf_rdy),
    .scanout_buf_release (ppu_scanout_buf_release),

    .lcd_cs              (padout_lcd_cs_n),
    .lcd_dc              (padout_lcd_dc),
    .lcd_sck             (padout_lcd_clk),
    .lcd_mosi            (padout_lcd_dat)
);

// ------------------------------------------------------------------------
// APB peripherals and control registers

pwm_tiny lcd_bl_pwm_u (
    .clk          (clk_sys),
    .rst_n        (rst_n_sys),

    .apbs_psel    (lcd_pwm_psel),
    .apbs_penable (lcd_pwm_penable),
    .apbs_pwrite  (lcd_pwm_pwrite),
    .apbs_paddr   (lcd_pwm_paddr),
    .apbs_pwdata  (lcd_pwm_pwdata),
    .apbs_prdata  (lcd_pwm_prdata),
    .apbs_pready  (lcd_pwm_pready),
    .apbs_pslverr (lcd_pwm_pslverr),

    .padout       (padout_lcd_bl)
);

hazard3_riscv_timer #(
    .TICK_IS_NRZ (0) // TODO
) riscv_timer_u (
    .clk       (clk_sys),
    .rst_n     (rst_n_sys),
    .paddr     (timer_paddr[15:0]),
    .psel      (timer_psel),
    .penable   (timer_penable),
    .pwrite    (timer_pwrite),
    .pwdata    (timer_pwdata),
    .prdata    (timer_prdata),
    .pready    (timer_pready),
    .pslverr   (timer_pslverr),
    .dbg_halt  (dbg_halted[0]),
    .tick      (1'b1),
    .timer_irq (timer_irq)
);

vuart #(
    .DEV_TX_DEPTH (16),
    .DEV_RX_DEPTH (8)
) vuart_u (
    .dck          (padin_dck),
    .drst_n       (drst_n),

    .clk          (clk_sys),
    .rst_n        (rst_n_sys),

    .irq          (irq[IRQ_VUART]),

    .hostconn     (dtm_connected),

    .host_psel    (dtm_to_vuart_psel),
    .host_penable (dtm_to_vuart_penable),
    .host_pwrite  (dtm_to_vuart_pwrite),
    .host_paddr   (dtm_to_vuart_paddr),
    .host_pwdata  (dtm_to_vuart_pwdata),
    .host_prdata  (dtm_to_vuart_prdata),
    .host_pready  (dtm_to_vuart_pready),
    .host_pslverr (dtm_to_vuart_pslverr),

    .dev_psel     (vuart_dev_psel),
    .dev_penable  (vuart_dev_penable),
    .dev_pwrite   (vuart_dev_pwrite),
    .dev_paddr    (vuart_dev_paddr[15:0]),
    .dev_pwdata   (vuart_dev_pwdata),
    .dev_prdata   (vuart_dev_prdata),
    .dev_pready   (vuart_dev_pready),
    .dev_pslverr  (vuart_dev_pslverr)
);


padctrl #(
    .N_GPIO (N_GPIO + 2)
) padctrl_u (
    .clk               (clk_sys),
    .rst_n             (rst_n_sys),

    .apbs_psel         (padctrl_psel),
    .apbs_penable      (padctrl_penable),
    .apbs_pwrite       (padctrl_pwrite),
    .apbs_paddr        (padctrl_paddr),
    .apbs_pwdata       (padctrl_pwdata),
    .apbs_prdata       (padctrl_prdata),
    .apbs_pready       (padctrl_pready),
    .apbs_pslverr      (padctrl_pslverr),

    .dio_schmitt       (dio_schmitt),
    .dio_slew          (dio_slew),
    .dio_drive         (dio_drive),
    .sram_dq_schmitt   (sram_dq_schmitt),
    .sram_dq_slew      (sram_dq_slew),
    .sram_dq_drive     (sram_dq_drive),
    .sram_a_slew       (sram_a_slew),
    .sram_a_drive      (sram_a_drive),
    .sram_strobe_slew  (sram_strobe_slew),
    .sram_strobe_drive (sram_strobe_drive),
    .audio_schmitt     (audio_schmitt),
    .audio_slew        (audio_slew),
    .audio_drive       (audio_drive),
    .lcd_clk_slew      (lcd_clk_slew),
    .lcd_clk_drive     (lcd_clk_drive),
    .lcd_dat_slew      (lcd_dat_slew),
    .lcd_dat_drive     (lcd_dat_drive),
    .lcd_dccs_slew     (lcd_dccs_slew),
    .lcd_dccs_drive    (lcd_dccs_drive),
    .lcd_bl_slew       (lcd_bl_slew),
    .lcd_bl_drive      (lcd_bl_drive),
    .gpio_schmitt      (gpio_schmitt),
    .gpio_slew         (gpio_slew),
    .gpio_drive        (gpio_drive),
    .gpio_pu           ({audio_l_pu, audio_r_pu, gpio_pu}),
    .gpio_pd           ({audio_l_pd, audio_r_pd, gpio_pd})
);


gpio #(
    .N_GPIO (N_GPIO + 2)
) gpio_u (
    .clk          (clk_sys),
    .rst_n        (rst_n_sys),

    .apbs_psel    (gpio_psel),
    .apbs_penable (gpio_penable),
    .apbs_pwrite  (gpio_pwrite),
    .apbs_paddr   (gpio_paddr),
    .apbs_pwdata  (gpio_pwdata),
    .apbs_prdata  (gpio_prdata),
    .apbs_pready  (gpio_pready),
    .apbs_pslverr (gpio_pslverr),

    .audio_l      (audio_l),
    .audio_r      (audio_r),

    .padout_gpio  ({padout_audio_l, padout_audio_r, padout_gpio}),
    .padoe_gpio   ({padoe_audio_l,  padoe_audio_r,  padoe_gpio }),
    .padin_gpio   ({1'b0         ,  1'b0,           padin_gpio })
);



// ------------------------------------------------------------------------
// External SRAM controller and std cell "PHY"

localparam W_SRAM_ADDR = N_SRAM_A;
localparam W_SRAM_DATA =  N_SRAM_DQ;

wire [W_SRAM_ADDR-1:0]   sram_ctrl_addr;
wire [W_SRAM_DATA-1:0]   sram_ctrl_dq_out;
wire [W_SRAM_DATA-1:0]   sram_ctrl_dq_oe;
wire [W_SRAM_DATA-1:0]   sram_ctrl_dq_in;
wire                     sram_ctrl_ce_n;
wire                     sram_ctrl_we_n;
wire                     sram_ctrl_oe_n;
wire [W_SRAM_DATA/8-1:0] sram_ctrl_byte_n;

riscboy_sram_ctrl #(
    .W_HADDR     (20),
    .W_SRAM_ADDR (N_SRAM_A)
) eram_ctrl_u (
    .clk               (clk_sys),
    .rst_n             (rst_n_sys),

    .ahbls_haddr       (eram_haddr),
    .ahbls_htrans      (eram_htrans),
    .ahbls_hburst      (eram_hburst),
    .ahbls_hprot       (eram_hprot),
    .ahbls_hmastlock   (eram_hmastlock),
    .ahbls_hwrite      (eram_hwrite),
    .ahbls_hsize       (eram_hsize),
    .ahbls_hready      (eram_hready),
    .ahbls_hready_resp (eram_hready_resp),
    .ahbls_hresp       (eram_hresp),
    .ahbls_hwdata      (eram_hwdata),
    .ahbls_hrdata      (eram_hrdata),

    .dma_addr          (ppu_mem_addr),
    .dma_addr_vld      (ppu_mem_addr_vld),
    .dma_addr_rdy      (ppu_mem_addr_rdy),
    .dma_rdata         (ppu_mem_rdata),
    .dma_rdata_vld     (ppu_mem_rdata_vld),

    .sram_addr         (sram_ctrl_addr),
    .sram_dq_out       (sram_ctrl_dq_out),
    .sram_dq_oe        (sram_ctrl_dq_oe),
    .sram_dq_in        (sram_ctrl_dq_in),
    .sram_ce_n         (sram_ctrl_ce_n),
    .sram_we_n         (sram_ctrl_we_n),
    .sram_oe_n         (sram_ctrl_oe_n),
    .sram_byte_n       (sram_ctrl_byte_n)
);

async_sram_phy_gf180mcu #(
    .N_SRAM_A  (N_SRAM_A),
    .N_SRAM_DQ (N_SRAM_DQ)
) sram_phy_u (
    .clk              (clk_sys),
    .rst_n            (rst_n_sys),

    .ctrl_addr        (sram_ctrl_addr),
    .ctrl_dq_out      (sram_ctrl_dq_out),
    .ctrl_dq_oe       (sram_ctrl_dq_oe),
    .ctrl_dq_in       (sram_ctrl_dq_in),
    .ctrl_ce_n        (sram_ctrl_ce_n),
    .ctrl_we_n        (sram_ctrl_we_n),
    .ctrl_oe_n        (sram_ctrl_oe_n),
    .ctrl_byte_n      (sram_ctrl_byte_n),

    .padin_sram_dq    (padin_sram_dq),
    .padoe_sram_dq    (padoe_sram_dq),
    .padout_sram_dq   (padout_sram_dq),
    .padout_sram_a    (padout_sram_a),
    .padout_sram_oe_n (padout_sram_oe_n),
    .padout_sram_cs_n (padout_sram_cs_n),
    .padout_sram_we_n (padout_sram_we_n),
    .padout_sram_ub_n (padout_sram_ub_n),
    .padout_sram_lb_n (padout_sram_lb_n)
);

endmodule

`default_nettype wire
