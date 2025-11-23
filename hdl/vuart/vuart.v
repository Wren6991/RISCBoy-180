/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Virtual UART for use with TWD debug transport module

`default_nettype none

module vuart #(
	parameter DEV_TX_DEPTH = 16,
	parameter DEV_RX_DEPTH = 8
) (
	input  wire        dck,
	input  wire        drst_n,
	input  wire        clk,
	input  wire        rst_n,
	
	// Device TX/RX interrupt, synchronous to clk
	output wire        irq,

	// Host port, synchronous to dck
	input  wire        host_psel,
	input  wire        host_penable,
	input  wire        host_pwrite,
	input  wire [9:0]  host_paddr,
	input  wire [31:0] host_pwdata,
	output wire [31:0] host_prdata,
	output wire        host_pready,
	output wire        host_pslverr,

	// Device port, synchronous to clk
	input  wire        dev_psel,
	input  wire        dev_penable,
	input  wire        dev_pwrite,
	input  wire [15:0] dev_paddr,
	input  wire [31:0] dev_pwdata,
	output wire [31:0] dev_prdata,
	output wire        dev_pready,
	output wire        dev_pslverr
);

// ----------------------------------------------------------------------------
// FIFO signals

// dck domain:
wire [7:0]                        host2dev_wdata;
wire                              host2dev_wpush;
wire                              host2dev_wfull;
wire                              host2dev_wempty;
wire [$clog2(DEV_RX_DEPTH+1)-1:0] host2dev_wlevel;

// clk domain:
wire [7:0]                        host2dev_rdata;
wire                              host2dev_rpop;
wire                              host2dev_rfull;
wire                              host2dev_rempty;
wire [$clog2(DEV_RX_DEPTH+1)-1:0] host2dev_rlevel;

// clk domain:
wire [7:0]                        dev2host_wdata;
wire                              dev2host_wpush;
wire                              dev2host_wfull;
wire                              dev2host_wempty;
wire [$clog2(DEV_TX_DEPTH+1)-1:0] dev2host_wlevel;

// dck_domain:
wire [7:0]                        dev2host_rdata;
wire                              dev2host_rpop;
wire                              dev2host_rfull;
wire                              dev2host_rempty;
wire [$clog2(DEV_TX_DEPTH+1)-1:0] dev2host_rlevel;

wire                              irqctrl_rx_enable;
wire                              irqctrl_tx_enable;
wire [1:0]                        irqctrl_tx_level;

// ----------------------------------------------------------------------------
// Register interfaces

vuart_dev_regs dev_regs_u (
	.clk                 (clk),
	.rst_n               (rst_n),

	.apbs_psel           (dev_psel),
	.apbs_penable        (dev_penable),
	.apbs_pwrite         (dev_pwrite),
	.apbs_paddr          (dev_paddr),
	.apbs_pwdata         (dev_pwdata),
	.apbs_prdata         (dev_prdata),
	.apbs_pready         (dev_pready),
	.apbs_pslverr        (dev_pslverr),

	.stat_rxvld_i        (!host2dev_rempty),
	.stat_txrdy_i        (!dev2host_wfull),
	.stat_rxlevel_i      ({{8-$clog2(DEV_RX_DEPTH+1){1'b0}}, host2dev_rlevel}),
	.stat_txlevel_i      ({{8-$clog2(DEV_TX_DEPTH+1){1'b0}}, dev2host_wlevel}),

	.info_rxsize_i       (DEV_RX_DEPTH[7:0]),
	.info_txsize_i       (DEV_TX_DEPTH[7:0]),

	.fifo_rxvld_i        (!host2dev_rempty),
	.fifo_txrdy_i        (!dev2host_wfull),

	.fifo_txrx_i         (host2dev_rdata),
	.fifo_txrx_o         (dev2host_wdata),
	.fifo_txrx_wen       (dev2host_wpush),
	.fifo_txrx_ren       (host2dev_rpop),

	.irqctrl_rx_enable_o (irqctrl_rx_enable),
	.irqctrl_tx_enable_o (irqctrl_tx_enable),
	.irqctrl_tx_level_o  (irqctrl_tx_level)
);

vuart_host_regs vuart_host_regs_u (
	.clk            (dck),
	.rst_n          (drst_n),

	.apbs_psel      (host_psel),
	.apbs_penable   (host_penable),
	.apbs_pwrite    (host_pwrite),
	.apbs_paddr     (host_paddr),
	.apbs_pwdata    (host_pwdata),
	.apbs_prdata    (host_prdata),
	.apbs_pready    (host_pready),
	.apbs_pslverr   (host_pslverr),

	.stat_rxvld_i   (!dev2host_rempty),
	.stat_txrdy_i   (!host2dev_wfull),
	.stat_rxlevel_i ({{8-$clog2(DEV_TX_DEPTH+1){1'b0}}, dev2host_rlevel}),
	.stat_txlevel_i ({{8-$clog2(DEV_RX_DEPTH+1){1'b0}}, host2dev_wlevel}),

	.info_rxsize_i  (DEV_TX_DEPTH[7:0]),
	.info_txsize_i  (DEV_RX_DEPTH[7:0]),

	.fifo_rxvld_i   (!dev2host_rempty),
	.fifo_txrdy_i   (!host2dev_wfull),

	.fifo_txrx_i    (dev2host_rdata),
	.fifo_txrx_o    (host2dev_wdata),
	.fifo_txrx_wen  (host2dev_wpush),
	.fifo_txrx_ren  (dev2host_rpop)
);

// ----------------------------------------------------------------------------
// FIFO instances

async_fifo #(
	.W_DATA (8),
	.W_ADDR ($clog2(DEV_RX_DEPTH))
) fifo_host2dev_u (
	.wrst_n (drst_n),
	.wclk   (dck),
	.rrst_n (rst_n),
	.rclk   (clk),

	.wdata  (host2dev_wdata),
	.wpush  (host2dev_wpush),
	.wfull  (host2dev_wfull),
	.wempty (host2dev_wempty),
	.wlevel (host2dev_wlevel),

	.rdata  (host2dev_rdata),
	.rpop   (host2dev_rpop),
	.rfull  (host2dev_rfull),
	.rempty (host2dev_rempty),
	.rlevel (host2dev_rlevel)
);

async_fifo #(
	.W_DATA (8),
	.W_ADDR ($clog2(DEV_TX_DEPTH))
) fifo_dev2host_u (
	.wrst_n (rst_n),
	.wclk   (clk),
	.rrst_n (drst_n),
	.rclk   (dck),

	.wdata  (dev2host_wdata),
	.wpush  (dev2host_wpush),
	.wfull  (dev2host_wfull),
	.wempty (dev2host_wempty),
	.wlevel (dev2host_wlevel),

	.rdata  (dev2host_rdata),
	.rpop   (dev2host_rpop),
	.rfull  (dev2host_rfull),
	.rempty (dev2host_rempty),
	.rlevel (dev2host_rlevel)
);

// ----------------------------------------------------------------------------
// IRQ logic

localparam W_TXLEVEL = $clog2(DEV_TX_DEPTH + 1);

wire tx_half_full = dev2host_wlevel[W_TXLEVEL - 1];
wire tx_threeq_full = tx_half_full && dev2host_wlevel[W_TXLEVEL - 2];

wire rx_irq = irqctrl_rx_enable && !host2dev_rempty;
wire [3:0] tx_irq_cond = {
	!dev2host_wfull,
	!tx_threeq_full,
	!tx_half_full,
	dev2host_wempty
};
wire tx_irq = irqctrl_tx_enable && tx_irq_cond[irqctrl_tx_level];

reg irq_q;
assign irq = irq_q;
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		irq_q <= 1'b0;
	end else begin
		irq_q <= rx_irq || tx_irq;
	end
end

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
