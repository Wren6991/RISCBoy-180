/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Derived from the RISCBoy UART
// Bonus feature: 38 kHz / 40 kHz modulation for IR :)

module uart_mini #(
	parameter FIFO_DEPTH = 2, // must be power of 2, >= 2
	parameter OVERSAMPLE = 8, // must be power of 2, >= 4
	parameter RTS_LEVEL  = FIFO_DEPTH - 2
) (
	input  wire        clk,
	input  wire        rst_n,

	// APB Port
	input  wire        apbs_psel,
	input  wire        apbs_penable,
	input  wire        apbs_pwrite,
	input  wire [15:0] apbs_paddr,
	input  wire [31:0] apbs_pwdata,
	output wire [31:0] apbs_prdata,
	output wire        apbs_pready,
	output wire        apbs_pslverr,

	input  wire        rx,
	output wire        tx,
	input  wire        cts,
	output reg         rts,

	output wire        irq
);

localparam W_FLEVEL = $clog2(FIFO_DEPTH + 1);
localparam W_OVER = $clog2(OVERSAMPLE);

localparam W_DIV_INT = 12;
localparam W_DIV_FRAC = 4;

wire rst_n_sync;

reset_sync inst_reset_sync (
	.clk       (clk),
	.rst_n_in  (rst_n),
	.rst_n_out (rst_n_sync)
);

wire [7:0]          txfifo_wdata;
wire                txfifo_wen;
wire [7:0]          txfifo_rdata;
wire                txfifo_ren;
wire                txfifo_full;
wire                txfifo_empty;
wire [W_FLEVEL-1:0] txfifo_level;

reg                 rxfifo_wen;
wire [7:0]          rxfifo_rdata;
wire                rxfifo_ren;
wire                rxfifo_full;
wire                rxfifo_empty;
wire [W_FLEVEL-1:0] rxfifo_level;

wire                csr_en;
wire                csr_txie;
wire                csr_rxie;
wire                csr_loopback;
wire                csr_txflush;
wire                csr_rxflush;

assign irq = (csr_txie && !txfifo_full) || (csr_rxie && !rxfifo_empty);

wire [11:0] ir_div;
wire        ir_en;
wire        ir_preinvert_tx;
wire        ir_postinvert_tx;
wire        ir_invert_rx;

reg         ir_local_osc;

wire clk_en;

wire rx_fp;
falsepath_anchor fp_rx_u (
	.i (rx),
	.z (rx_fp)
);

wire rx_sync;
reg  tx_q;
wire din_comb = (csr_loopback ? tx_q : rx_sync) ^ ir_invert_rx;

sync_1bit rx_synchroniser (
	.clk   (clk),
	.rst_n (rst_n_sync),
	.i     (rx),
	.o     (rx_sync)
);

// ----------------------------------------------------------------------------
// TX State Machine

reg [W_OVER-1:0] tx_over_ctr;
reg [3:0] tx_state;
reg [7:0] tx_shifter;

localparam TX_IDLE = 0;
localparam TX_START = 1;
// 2...9 are data states
localparam TX_STOP = 10;

wire cts_en;
wire tx_busy = tx_state != TX_IDLE || !txfifo_empty;
wire cts_with_loop = csr_loopback ? rts : cts;
wire hold_tx = txfifo_empty || (cts_en && cts_with_loop);
assign txfifo_ren = clk_en && !hold_tx && !tx_over_ctr &&
	(tx_state == TX_IDLE || tx_state == TX_STOP);

always @ (posedge clk or negedge rst_n_sync) begin
	if (!rst_n_sync) begin
		tx_q <= 1'b1;
		tx_over_ctr <= {W_OVER{1'b0}};
		tx_state <= TX_IDLE;
		tx_shifter <= 8'h0;
	end else if (!csr_en) begin
		// Put tx_q into synchronous reset when disabled.
		tx_q <= 1'b1;
		tx_over_ctr <= {W_OVER{1'b0}};
		tx_state <= TX_IDLE;
		tx_shifter <= 8'h0;
	end else begin
		if (clk_en)
			tx_over_ctr <= tx_over_ctr + 1'b1;
		if (clk_en && !tx_over_ctr) begin
			tx_state <= tx_state + 1'b1;
			case (tx_state)
			TX_IDLE: begin
				if (hold_tx) begin
					// Hold counter whilst idle, so we respond immediately
					tx_over_ctr <= {W_OVER{1'b0}};
					tx_state <= TX_IDLE;
				end else begin
					tx_shifter <= txfifo_rdata;
					tx_q <= 1'b0;
				end
			end
			TX_START: begin
				tx_shifter <= tx_shifter >> 1;
				tx_q <= tx_shifter[0];
			end
			TX_STOP: begin
				if (hold_tx) begin
					tx_state <= TX_IDLE;
					tx_over_ctr <= {W_OVER{1'b0}};
				end else begin
					tx_shifter <= txfifo_rdata;
					tx_state <= TX_START;
					tx_q <= 1'b0;
				end
			end
			default: begin
				// Data states
				tx_shifter <= tx_shifter >> 1;
				if (tx_state == TX_STOP - 1) begin
					tx_q <= 1'b1;
				end else begin
					tx_q <= tx_shifter[0];
				end
			end
			endcase
		end
	end
end

// ----------------------------------------------------------------------------
// RX State Machine

reg [W_OVER-1:0] rx_over_ctr;
reg [3:0] rx_state;
reg [7:0] rx_shifter;

// Nearly-useless glitch filter
reg [1:0] din_prev;
reg din;

always @ (posedge clk or negedge rst_n_sync) begin
	if (!rst_n_sync) begin
		din_prev <= 2'b11;
		din <= 1'b1;
	end else begin
		din_prev <= {din_prev[0], din_comb};
		if (&{din_comb, din_prev})
			din <= 1'b1;
		else if (~|{din_comb, din_prev})
			din <= 1'b0;
	end
end

localparam RX_IDLE = 0;    // followed by 1 bit period delay
localparam RX_START = 1;  // followed by 0.5 bit period delay
// 2...9 are data states
localparam RX_STOP = 10;

always @ (posedge clk or negedge rst_n_sync) begin
	if (!rst_n_sync) begin
		rx_over_ctr <= {W_OVER{1'b0}};
		rx_state <= RX_IDLE;
		rx_shifter <= 8'h0;
		rxfifo_wen <= 1'b0;
	end else if (!csr_en) begin
		rx_over_ctr <= {W_OVER{1'b0}};
		rx_state <= RX_IDLE;
		rx_shifter <= 8'h0;
		rxfifo_wen <= 1'b0;
	end else begin
		rxfifo_wen <= 1'b0;
		if (clk_en)
			rx_over_ctr <= rx_over_ctr + 1'b1;
		if (clk_en && !rx_over_ctr) begin
			rx_state <= rx_state + 1'b1;
			case (rx_state)
			RX_IDLE: begin
				if (din) begin
					// Hold oversample counter to maintain readiness
					rx_state <= RX_IDLE;
					rx_over_ctr <= {W_OVER{1'b0}};
				end
			end
			RX_START: begin
				rx_over_ctr <= OVERSAMPLE / 2;	// shorten delay to next state by 1/2
			end
			RX_STOP: begin
				// Don't push if there is no valid stop bit
				rxfifo_wen <= din;
				// No delay before idle state.
				// Half bit period of slack before next start bit edge,
				// helps to keep sync when TX clock is a little faster than ours.
				rx_state <= RX_IDLE;
				rx_over_ctr <= 0;
			end
			default: begin
				// Data states
				rx_shifter <= (rx_shifter >> 1) | (din << 7);
			end
			endcase
		end
	end
end

always @ (posedge clk or negedge rst_n_sync) begin
	if (!rst_n_sync) begin
		rts <= 1'b1;
	end else begin
		rts <= rxfifo_level > RTS_LEVEL;
	end
end

// ----------------------------------------------------------------------------
// IR modulation

reg [W_DIV_INT-1:0] ir_losc_ctr;

always @ (posedge clk or negedge rst_n_sync) begin
	if (!rst_n_sync) begin
		ir_losc_ctr <= {W_DIV_INT{1'b0}};
		ir_local_osc <= 1'b0;
	end else if (!ir_en) begin
		ir_losc_ctr <= {W_DIV_INT{1'b0}};
		ir_local_osc <= 1'b0;		
	end else if (~|ir_losc_ctr) begin
		ir_losc_ctr <= ir_div;
		ir_local_osc <= !ir_local_osc;
	end else begin
		ir_losc_ctr <= ir_losc_ctr - {{W_DIV_INT-1{1'b0}}, 1'b1};
	end
end

assign tx = ir_postinvert_tx ^ (ir_local_osc | (ir_preinvert_tx ^ tx_q));

// ----------------------------------------------------------------------------
// FIFOs, Clock Divider and Regblock

wire [W_DIV_INT-1:0]  div_int;
wire [W_DIV_FRAC-1:0] div_frac;

clkdiv_frac #(
	.W_DIV_INT(W_DIV_INT),
	.W_DIV_FRAC(W_DIV_FRAC)
) inst_clkdiv_frac (
	.clk      (clk),
	.rst_n    (rst_n_sync),
	.en       (csr_en),
	.div_int  (div_int),
	.div_frac (div_frac),
	.clk_en   (clk_en)
);

sync_fifo #(
	.DEPTH(FIFO_DEPTH),
	.WIDTH(8)
) txfifo (
	.clk    (clk),
	.rst_n  (rst_n_sync),
	.wdata  (txfifo_wdata),
	.wen    (txfifo_wen),
	.rdata  (txfifo_rdata),
	.ren    (txfifo_ren),
	.flush  (csr_txflush),
	.full   (txfifo_full),
	.empty  (txfifo_empty),
	.level  (txfifo_level)
);

sync_fifo #(
	.DEPTH(FIFO_DEPTH),
	.WIDTH(8)
) rxfifo (
	.clk    (clk),
	.rst_n  (rst_n_sync),
	.wdata  (rx_shifter),
	.wen    (rxfifo_wen),
	.rdata  (rxfifo_rdata),
	.ren    (rxfifo_ren),
	.flush  (csr_rxflush),
	.full   (rxfifo_full),
	.empty  (rxfifo_empty),
	.level  (rxfifo_level)
);

uart_regs regs (
	.clk                (clk),
	.rst_n              (rst_n_sync),

	.apbs_psel          (apbs_psel),
	.apbs_penable       (apbs_penable),
	.apbs_pwrite        (apbs_pwrite),
	.apbs_paddr         (apbs_paddr),
	.apbs_pwdata        (apbs_pwdata),
	.apbs_prdata        (apbs_prdata),
	.apbs_pready        (apbs_pready),
	.apbs_pslverr       (apbs_pslverr),

	.csr_en_o           (csr_en),
	.csr_busy_i         (tx_busy),
	.csr_txie_o         (csr_txie),
	.csr_rxie_o         (csr_rxie),
	.csr_ctsen_o        (cts_en),
	.csr_loopback_o     (csr_loopback),
	.csr_txflush_o      (csr_txflush),
	.csr_rxflush_o      (csr_rxflush),

	.div_int_o          (div_int),
	.div_frac_o         (div_frac),

	.fstat_txlevel_i    (txfifo_level | 8'h0),
	.fstat_txfull_i     (txfifo_full),
	.fstat_txempty_i    (txfifo_empty),
	.fstat_txover_i     (txfifo_full && txfifo_wen),
	.fstat_txunder_i    (txfifo_empty && txfifo_ren),
	.fstat_rxlevel_i    (rxfifo_level | 8'h0),
	.fstat_rxfull_i     (rxfifo_full),
	.fstat_rxempty_i    (rxfifo_empty),
	.fstat_rxover_i     (rxfifo_full && rxfifo_wen),
	.fstat_rxunder_i    (rxfifo_empty && rxfifo_ren),

	.tx_o               (txfifo_wdata),
	.tx_wen             (txfifo_wen),
	.rx_i               (rxfifo_rdata),
	.rx_ren             (rxfifo_ren),

	.ir_div_o           (ir_div),
	.ir_en_o            (ir_en),
	.ir_preinvert_tx_o  (ir_preinvert_tx),
	.ir_postinvert_tx_o (ir_postinvert_tx),
	.ir_invert_rx_o     (ir_invert_rx)
);

endmodule
