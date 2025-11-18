// SPDX-FileCopyrightText: © 2025 XXX Authors
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

module chip_core #(
    parameter NUM_INPUT_PADS,
    parameter NUM_BIDIR_PADS,
    parameter NUM_ANALOG_PADS
    )(
    `ifdef USE_POWER_PINS
    inout  wire VDD,
    inout  wire VSS,
    `endif

    input  wire clk,       // clock
    input  wire rst_n,     // reset (active low)

    input  wire [NUM_INPUT_PADS-1:0] input_in,   // Input value
    output wire [NUM_INPUT_PADS-1:0] input_pu,   // Pull-up
    output wire [NUM_INPUT_PADS-1:0] input_pd,   // Pull-down

    input  wire [NUM_BIDIR_PADS-1:0] bidir_in,   // Input value
    output wire [NUM_BIDIR_PADS-1:0] bidir_out,  // Output value
    output wire [NUM_BIDIR_PADS-1:0] bidir_oe,   // Output enable
    output wire [NUM_BIDIR_PADS-1:0] bidir_cs,   // Input type (0=CMOS Buffer, 1=Schmitt Trigger)
    output wire [NUM_BIDIR_PADS-1:0] bidir_sl,   // Slew rate (0=fast, 1=slow)
    output wire [NUM_BIDIR_PADS-1:0] bidir_ie,   // Input enable
    output wire [NUM_BIDIR_PADS-1:0] bidir_pu,   // Pull-up
    output wire [NUM_BIDIR_PADS-1:0] bidir_pd,   // Pull-down

    inout  wire [NUM_ANALOG_PADS-1:0] analog  // Analog
);

    // See here for usage: https://gf180mcu-pdk.readthedocs.io/en/latest/IPs/IO/gf180mcu_fd_io/digital.html

    // Disable pull-up and pull-down for input
    assign input_pu = '0;
    assign input_pd = '0;

    // Set the bidir as output
    assign bidir_oe = '1;
    assign bidir_cs = '0;
    assign bidir_sl = '0;
    assign bidir_ie = ~bidir_oe;
    assign bidir_pu = '0;
    assign bidir_pd = '0;

    logic _unused;
    assign _unused = &bidir_in;

    // ------------------------------------------------------------------------
    // Clock and reset manipulation

    wire rst_n_sync;
    reset_sync #(
        .N_CYCLES (3)
    ) sync_root_rst_n_u (
        .clk       (clk),
        .rst_n_in  (rst_n),
        .rst_n_out (rst_n_sync)
    );

    // JTAG DTM

    wire        dmi_psel;
    wire        dmi_penable;
    wire        dmi_pwrite;
    wire [8:0]  dmi_paddr;
    wire [31:0] dmi_pwdata;
    wire [31:0] dmi_prdata;
    wire        dmi_pready;
    wire        dmi_pslverr;

    wire        dmihardreset_req; // FIXME unused

    hazard3_jtag_dtm #(
        .IDCODE (32'hdeadbeef) // FIXME this is a real company
    ) inst_hazard3_jtag_dtm (
        .tck              (clk), // FIXME wrong but I don't feel like fighting this yet
        .trst_n           (rst_n_sync),
        .tms              (input_in[0]),
        .tdi              (input_in[1]),
        .tdo              (bidir_out[0]),
    
        .dmihardreset_req (dmihardreset_req),

        .clk_dmi          (clk),
        .rst_n_dmi        (rst_n_sync),
    
        .dmi_psel         (dmi_psel),
        .dmi_penable      (dmi_penable),
        .dmi_pwrite       (dmi_pwrite),
        .dmi_paddr        (dmi_paddr),
        .dmi_pwdata       (dmi_pwdata),
        .dmi_prdata       (dmi_prdata),
        .dmi_pready       (dmi_pready),
        .dmi_pslverr      (dmi_pslverr)
    );

    // ------------------------------------------------------------------------
    // Debug Module and processor reset control

    wire        sys_reset_req;
    wire        hart_reset_req;
    wire        rst_n_cpu;
    wire        rst_n_cpu_unsync = rst_n_sync && !(sys_reset_req || hart_reset_req);

    reset_sync #(
        .N_CYCLES (3)
    ) sync_rst_n_cpu (
        .clk       (clk),
        .rst_n_in  (rst_n_cpu_unsync),
        .rst_n_out (rst_n_cpu)
    );

    wire sys_reset_done = rst_n_cpu;
    wire hart_reset_done = rst_n_cpu;

    // Yes we do want SBA. Segger RTT is too nice to ignore!

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

    wire [31:0] dbg_sbus_addr;
    wire        dbg_sbus_write;
    wire [1:0]  dbg_sbus_size;
    wire        dbg_sbus_vld;
    wire        dbg_sbus_rdy;
    wire        dbg_sbus_err;
    wire [31:0] dbg_sbus_wdata;
    wire [31:0] dbg_sbus_rdata;

    hazard3_dm #(
        .N_HARTS  (1),
        .HAVE_SBA (1)
    ) dm_u (
        .clk                         (clk),
        .rst_n                       (rst_n_sync),

        .dmi_psel                    (dmi_psel),
        .dmi_penable                 (dmi_penable),
        .dmi_pwrite                  (dmi_pwrite),
        .dmi_paddr                   (dmi_paddr),
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

        .sbus_addr                   (dbg_sbus_addr),
        .sbus_write                  (dbg_sbus_write),
        .sbus_size                   (dbg_sbus_size),
        .sbus_vld                    (dbg_sbus_vld),
        .sbus_rdy                    (dbg_sbus_rdy),
        .sbus_err                    (dbg_sbus_err),
        .sbus_wdata                  (dbg_sbus_wdata),
        .sbus_rdata                  (dbg_sbus_rdata)
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

        .EXTENSION_A         (1),
        .EXTENSION_C         (1),
        .EXTENSION_E         (0),
        .EXTENSION_M         (1),

        .EXTENSION_ZBA       (0),
        .EXTENSION_ZBB       (0),
        .EXTENSION_ZBC       (0),
        .EXTENSION_ZBKB      (0),
        .EXTENSION_ZBKX      (0),
        .EXTENSION_ZBS       (0),
        .EXTENSION_ZCB       (0),
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
        .MUL_FAST            (0),
        .MUL_FASTER          (0),
        .MULH_FAST           (0),
        .FAST_BRANCHCMP      (1),
        .RESET_REGFILE       (0),
        .BRANCH_PREDICTOR    (0),
        .MTVEC_WMASK         (32'h000ffffd)
    ) cpu_u (
        .clk                        (clk),
        .clk_always_on              (clk), // FIXME clock gating
        .rst_n                      (rst_n_sync),

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

        .dbg_sbus_addr              (dbg_sbus_addr),
        .dbg_sbus_write             (dbg_sbus_write),
        .dbg_sbus_size              (dbg_sbus_size),
        .dbg_sbus_vld               (dbg_sbus_vld),
        .dbg_sbus_rdy               (dbg_sbus_rdy),
        .dbg_sbus_err               (dbg_sbus_err),
        .dbg_sbus_wdata             (dbg_sbus_wdata),
        .dbg_sbus_rdata             (dbg_sbus_rdata),

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
        .DEPTH (1024)
    ) iwram_u (
        .clk               (clk),
        .rst_n             (rst_n_sync),

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


endmodule

`default_nettype wire
