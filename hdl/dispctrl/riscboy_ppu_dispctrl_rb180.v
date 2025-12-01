/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Simple serial display "controller" for PPU. Two jobs:
//
// - Shift out a continously-clocked stream of pixel data from the scanbuf,
//   for screen update
// - Shift out individual bytes from the APB interface, for control purposes
//
// Modified a bit for RISCBoy 180. It now also does "octal serial".

`default_nettype none

module riscboy_ppu_dispctrl_rb180 #(
	parameter PXFIFO_DEPTH = 4,
	parameter W_COORD_SX = 9,
	parameter W_DATA  = 16
) (
	input  wire                  clk_sys,
	input  wire                  rst_n_sys,
	input  wire                  clk_tx,
	input  wire                  rst_n_tx,

	// APB slave port
	input  wire                  apbs_psel,
	input  wire                  apbs_penable,
	input  wire                  apbs_pwrite,
	input  wire [15:0]           apbs_paddr,
	input  wire [31:0]           apbs_pwdata,
	output wire [31:0]           apbs_prdata,
	output wire                  apbs_pready,
	output wire                  apbs_pslverr,

	// Scanbuf read port signals
	output reg  [W_COORD_SX-1:0] scanout_raddr,
	output wire                  scanout_ren,
	input  wire [W_DATA-1:0]     scanout_rdata,
	input  wire                  scanout_buf_rdy,
	output wire                  scanout_buf_release,

	input  wire [5:0]            spare_dat7_to_2,
	output reg                   lcd_bl,

	// Outputs to display
	output wire                  lcd_dc,
	output wire                  lcd_sck,
	output wire [7:0]            lcd_dat
);

localparam W_PXFIFO_LEVEL  = $clog2(PXFIFO_DEPTH + 1);

// ----------------------------------------------------------------------------
// Scanbuf interface and APB slave interface (system clock domain)

wire        csr_scan_en;
wire        csr_pxfifo_empty;
wire        csr_pxfifo_full;
wire        csr_lcd_cs;
wire        csr_lcd_dc;
wire        csr_tx_busy;
wire        csr_lcd_shiftcnt;
wire        csr_lcd_buswidth;
wire        csr_lcd_halfrate;
wire        csr_xdouble;
wire        csr_ydouble;
wire [8:0]  scanbuf_size;
wire [15:0] pxfifo_direct_wdata;
wire        pxfifo_direct_wen;
wire [7:0]  bl_pwm_div;
wire [7:0]  bl_pwm_level;

dispctrl_rb180_regs regs_u (
	.clk                (clk_sys),
	.rst_n              (rst_n_sys),

	.apbs_psel          (apbs_psel),
	.apbs_penable       (apbs_penable),
	.apbs_pwrite        (apbs_pwrite),
	.apbs_paddr         (apbs_paddr),
	.apbs_pwdata        (apbs_pwdata),
	.apbs_prdata        (apbs_prdata),
	.apbs_pready        (apbs_pready),
	.apbs_pslverr       (apbs_pslverr),

	.csr_scan_en_o      (csr_scan_en),
	.csr_pxfifo_empty_i (csr_pxfifo_empty),
	.csr_pxfifo_full_i  (csr_pxfifo_full),
	.csr_lcd_cs_o       (csr_lcd_cs),
	.csr_lcd_dc_o       (csr_lcd_dc),
	.csr_tx_busy_i      (csr_tx_busy),
	.csr_lcd_shiftcnt_o (csr_lcd_shiftcnt),
	.csr_lcd_buswidth_o (csr_lcd_buswidth),
	.csr_lcd_halfrate_o (csr_lcd_halfrate),
	.csr_xdouble_o      (csr_xdouble),
	.csr_ydouble_o      (csr_ydouble),

	.scanbuf_size_o     (scanbuf_size),

	.pxfifo_o           (pxfifo_direct_wdata),
	.pxfifo_wen         (pxfifo_direct_wen),

	.bl_pwm_div_o       (bl_pwm_div),
	.bl_pwm_level_o     (bl_pwm_level)
);

// Scan out to pixel FIFO

wire [W_PXFIFO_LEVEL-1:0] pxfifo_wlevel;
reg  pxfifo_scan_wen;
reg  scanout_y_first_of_two;
reg  scanout_x_first_of_two;

wire pxfifo_wready = pxfifo_wlevel < PXFIFO_DEPTH - 2 ||
	!(csr_pxfifo_full || pxfifo_scan_wen);

wire scanout_wen_nxt = csr_scan_en && scanout_buf_rdy && pxfifo_wready;
assign scanout_ren = scanout_wen_nxt && (!csr_xdouble || scanout_x_first_of_two);

wire end_of_line =
	scanout_wen_nxt &&
	!scanout_x_first_of_two &&
	scanout_raddr == scanbuf_size;

assign scanout_buf_release = end_of_line && !scanout_y_first_of_two;

always @ (posedge clk_sys or negedge rst_n_sys) begin
	if (!rst_n_sys) begin
		scanout_raddr <= {W_COORD_SX{1'b0}};
		pxfifo_scan_wen <= 1'b0;
		scanout_y_first_of_two <= 1'b0;
		scanout_x_first_of_two <= 1'b0;
	end else if (!csr_scan_en || !scanout_buf_rdy) begin
		scanout_raddr <= {W_COORD_SX{1'b0}};
		pxfifo_scan_wen <= 1'b0;		
		scanout_y_first_of_two <= csr_ydouble;
		scanout_x_first_of_two <= csr_xdouble;
	end else if (scanout_wen_nxt) begin
		// Write is delayed by 1 due to read latency of scanbuf ram.
		pxfifo_scan_wen <= 1'b1;
		scanout_x_first_of_two <= !scanout_x_first_of_two && csr_xdouble;
		if (!scanout_x_first_of_two) begin
			scanout_raddr <= end_of_line ? {W_COORD_SX{1'b0}} : scanout_raddr + 1'b1;
			scanout_y_first_of_two <= !scanout_y_first_of_two && csr_ydouble;
		end
	end else begin
		pxfifo_scan_wen <= 1'b0;
	end
end

// ----------------------------------------------------------------------------
// Backlight PWM

reg [7:0] div_ctr;
reg [7:0] level_ctr;

always @ (posedge clk_sys or negedge rst_n_sys) begin
	if (!rst_n_sys) begin
		div_ctr <= 8'd1;
		level_ctr <= 8'd0;
		lcd_bl <= 1'b0;
	end else if (div_ctr == 8'd1) begin
		div_ctr <= bl_pwm_div;
		level_ctr <= (level_ctr + 8'd1) & ~{8{&level_ctr[7:1]}};
		lcd_bl <= level_ctr < bl_pwm_level;
	end else begin
		div_ctr <= div_ctr - 8'd1;
	end
end

// ----------------------------------------------------------------------------
// Clock domain crossing

wire              csr_tx_busy_clklcd;
wire              csr_lcd_buswidth_clklcd;
wire              csr_lcd_shiftcnt_clklcd;
wire              csr_lcd_halfrate_clklcd;
wire              csr_lcd_cs_clklcd;
wire              csr_lcd_dc_clklcd;

wire [W_DATA-1:0] pxfifo_wdata = pxfifo_direct_wen ? pxfifo_direct_wdata : scanout_rdata;
wire              pxfifo_wen = pxfifo_direct_wen || pxfifo_scan_wen;

wire [W_DATA-1:0] pxfifo_rdata;
wire              pxfifo_rempty;
wire              pxfifo_rdy;
wire              pxfifo_pop = pxfifo_rdy && !pxfifo_rempty;

async_fifo #(
	.W_DATA (W_DATA),
	.W_ADDR (W_PXFIFO_LEVEL - 1)
) pixel_fifo (
	.wclk   (clk_sys),
	.wrst_n (rst_n_sys),

	.wdata  (pxfifo_wdata),
	.wpush  (pxfifo_wen),
	.wfull  (csr_pxfifo_full),
	.wempty (csr_pxfifo_empty),
	.wlevel (pxfifo_wlevel),

	.rclk   (clk_tx),
	.rrst_n (rst_n_tx),

	.rdata  (pxfifo_rdata),
	.rpop   (pxfifo_pop),
	.rfull  (/* unused */),
	.rempty (pxfifo_rempty),
	.rlevel (/* unused */)
);

sync_1bit sync_lcd_busy (
	.clk   (clk_sys),
	.rst_n (rst_n_sys),
	.i     (csr_tx_busy_clklcd),
	.o     (csr_tx_busy)
);

// It should be ok to use simple 2FF sync here because software maintains
// guarantee that this only changes when PPU + shifter are idle

sync_1bit sync_ctrl_u [4:0] (
	.clk   (clk_tx),
	.rst_n (rst_n_tx),
	.i     ({
		csr_lcd_shiftcnt,
		csr_lcd_buswidth,
		csr_lcd_halfrate,
		csr_lcd_cs,
		csr_lcd_dc
	}),
	.o     ({
		csr_lcd_shiftcnt_clklcd,
		csr_lcd_buswidth_clklcd,
		csr_lcd_halfrate_clklcd,
		csr_lcd_cs_clklcd,
		csr_lcd_dc_clklcd
	})
);

// ----------------------------------------------------------------------------
// Shifter logic (TX clock domain)

// Optional divide by two:
reg shift_clken;
always @ (posedge clk_tx or negedge rst_n_tx) begin
	if (!rst_n_tx) begin
		shift_clken <= 1'b0;
	end else begin
		shift_clken <= !shift_clken || !csr_lcd_halfrate_clklcd;
	end
end

localparam W_SHAMT = $clog2(W_DATA + 1);

reg [W_DATA-1:0]  shift;
reg [W_SHAMT-1:0] shift_ctr;

assign pxfifo_rdy = shift_clken && ~|(shift_ctr[W_SHAMT-1:1]);
assign csr_tx_busy_clklcd = |shift_ctr || !pxfifo_rempty;

always @ (posedge clk_tx or negedge rst_n_tx) begin
	if (!rst_n_tx) begin
		shift <= {W_DATA{1'b0}};
		shift_ctr <= {W_SHAMT{1'b0}};
	end else if (shift_clken) begin
		if (pxfifo_pop) begin
			shift <= pxfifo_rdata;
			shift_ctr <=
				{csr_lcd_shiftcnt_clklcd, !csr_lcd_shiftcnt_clklcd, 3'd0}
				>> {2{csr_lcd_buswidth_clklcd}};
		end else if (|shift_ctr) begin
			shift_ctr <= shift_ctr - 5'd1;
			shift <= csr_lcd_buswidth_clklcd ? shift << 8 : shift << 1;
		end
	end
end

reg [7:0] lcd_dat_q;
reg       lcd_clk_en;
always @ (posedge clk_tx) begin
	lcd_dat_q <= csr_lcd_buswidth_clklcd ? shift[15:8] : {spare_dat7_to_2, csr_lcd_cs_clklcd, shift[15]};
	lcd_clk_en <= shift_clken && |shift_ctr;
end

wire sck_n;
gf180mcu_fd_sc_mcu9t5v0__icgtn_4 clkgate_sck_u (
	.TE   (1'b0),
	.E    (lcd_clk_en),
	.CLKN (clk_tx),
	.Q    (sck_n)
);
assign lcd_sck = !sck_n;
assign lcd_dat = lcd_dat_q;

assign lcd_dc = csr_lcd_dc_clklcd;

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
