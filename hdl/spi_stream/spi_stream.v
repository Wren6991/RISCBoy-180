/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

module spi_stream (
	input wire         clk,
	input wire         rst_n,
	
	output wire        irq,

	// AHB-Lite Port
	input  wire [15:0] ahbls_haddr,
	input  wire [1:0]  ahbls_htrans,
	input  wire        ahbls_hwrite,
	input  wire [2:0]  ahbls_hsize,
	input  wire        ahbls_hready,
	output wire        ahbls_hready_resp,
	input  wire [31:0] ahbls_hwdata,
	output wire [31:0] ahbls_hrdata,
	output wire        ahbls_hresp,

	// Dual SPI is not supported because this is a 5V chip and SPI flash
	// generally only goes up to 3.3V, so we'll be using level shifters.
	// Bidirectional level shifters are cursed.
	output wire        spi_cs_n,
	output wire        spi_sck,
	output wire        spi_mosi,
	input  wire        spi_miso
);

// ----------------------------------------------------------------------------
// Register block instantiation

wire        csr_start;
wire        csr_busy;
wire [1:0]  csr_flevel;
wire [1:0]  csr_irqlevel;
wire        csr_finished_i;
wire        csr_finished_o;
wire        csr_flush;
wire [7:0]  csr_opcode;
wire        csr_fvalid;

wire [2:0]  clkdiv;

reg  [21:0] addr;
wire [21:0] addr_o;
wire        addr_wen;

reg  [15:0] count;
wire [15:0] count_o;
wire        count_wen;

wire [31:0] fifo_i;
wire        fifo_ren;

wire        pause_req;
wire        pause_ack;

spi_stream_regs regs_u (
	.clk               (clk),
	.rst_n             (rst_n),

	.ahbls_haddr       (ahbls_haddr),
	.ahbls_htrans      (ahbls_htrans),
	.ahbls_hwrite      (ahbls_hwrite),
	.ahbls_hsize       (ahbls_hsize),
	.ahbls_hready      (ahbls_hready),
	.ahbls_hready_resp (ahbls_hready_resp),
	.ahbls_hwdata      (ahbls_hwdata),
	.ahbls_hrdata      (ahbls_hrdata),
	.ahbls_hresp       (ahbls_hresp),

	.csr_start_o       (csr_start),
	.csr_busy_i        (csr_busy),
	.csr_flevel_i      (csr_flevel),
	.csr_irqlevel_o    (csr_irqlevel),
	.csr_finished_i    (csr_finished_i),
	.csr_finished_o    (csr_finished_o),
	.csr_flush_o       (csr_flush),
	.csr_opcode_o      (csr_opcode),
	.csr_fvalid_i      (csr_fvalid),

	.clkdiv_o          (clkdiv),

	.addr_i            (addr),
	.addr_o            (addr_o),
	.addr_wen          (addr_wen),

	.count_i           (count),
	.count_o           (count_o),
	.count_wen         (count_wen),

	.fifo_i            (fifo_i),
	.fifo_ren          (fifo_ren),

	.pause_req_o       (pause_req),
	.pause_ack_i       (pause_ack)
);

// ----------------------------------------------------------------------------
// Main state machine

localparam W_STATE = 4;
localparam [3:0] S_IDLE        = 4'd0;
localparam [3:0] S_PAUSED_IDLE = 4'd1;
localparam [3:0] S_PAUSED_BUSY = 4'd2;
localparam [3:0] S_FRONTPORCH  = 4'd3;
localparam [3:0] S_CMD         = 4'd4;
localparam [3:0] S_ADDR        = 4'd5;
localparam [3:0] S_SHIFT_DATA  = 4'd6;
localparam [3:0] S_FIFO_WAIT   = 4'd7;
localparam [3:0] S_TO_PAUSE    = 4'd8;
localparam [3:0] S_TO_IDLE     = 4'd9;

localparam W_ADDR = 24;
localparam W_WORD_CTR = 12;
localparam W_BIT_CTR = 5;
localparam FIFO_DEPTH = 2;

// Current state
reg [W_STATE-1:0]   state;
reg                 sck;
reg                 mosi;
reg                 cs_n;
reg [W_BIT_CTR-1:0] bit_ctr;
reg [31:0]          sreg;

// Next state
reg [W_STATE-1:0]   state_nxt;
reg                 sck_nxt;
reg                 mosi_nxt;
reg                 cs_n_nxt;
reg [W_BIT_CTR-1:0] bit_ctr_nxt;
reg [31:0]          sreg_nxt;
reg [21:0]          addr_nxt;
reg [11:0]          count_nxt;

// Inputs
reg                 clk_en;
wire                fifo_full;

// Outputs
reg                 fifo_push;
reg                 finish_now;

always @ (*) begin
	state_nxt   = state;
	sck_nxt     = sck;
	mosi_nxt    = mosi;
	cs_n_nxt    = cs_n;
	bit_ctr_nxt = bit_ctr;
	sreg_nxt    = sreg;
	addr_nxt    = addr;
	count_nxt   = count;
	fifo_push   = 1'b0;
	finish_now  = 1'b0;
	if (clk_en) case (state)
	S_IDLE: begin
		if (pause_req) begin
			state_nxt = S_PAUSED_IDLE;
		end else if (csr_start) begin
			state_nxt = S_FRONTPORCH;
			cs_n_nxt = 1'b0;
		end
	end
	S_FRONTPORCH: begin
		bit_ctr_nxt = 5'd7;
		mosi_nxt = csr_opcode[7];
		state_nxt = S_CMD;
		sreg_nxt[31 -: 7] = csr_opcode[6:0];
	end
	S_CMD: begin
		sck_nxt = !sck;
		if (sck) begin
			if (~|bit_ctr) begin
				bit_ctr_nxt = 5'd23;
				mosi_nxt = addr[23];
				state_nxt = S_ADDR;
				sreg_nxt[31 -: 23] = {addr[20:0], 2'b00};
			end else begin
				bit_ctr_nxt = bit_ctr - 5'd1;
				mosi_nxt = sreg[31];
				sreg_nxt = sreg << 1;
			end
		end
	end
	S_ADDR: begin
		sck_nxt = !sck;
		if (sck) begin
			if (~|bit_ctr) begin
				bit_ctr_nxt = 5'd31;
				mosi_nxt = 1'b0;
				state_nxt = S_SHIFT_DATA;
			end else begin
				bit_ctr_nxt = bit_ctr - 5'd1;
				mosi_nxt = sreg[31];
				sreg_nxt = sreg << 1;
			end
		end
	end
	S_SHIFT_DATA: begin
		sck_nxt = !sck;
		if (sck) begin
			// Capture data at the point SCK *falling* edge is launched. This
			// provides one full SCK period for previous falling edge to go
			// round the loop and bring us back some data.
			sreg_nxt = {sreg[30:0], spi_miso};
			bit_ctr_nxt = bit_ctr - 5'd1;
			if (~|bit_ctr) begin
				if (fifo_full) begin
					state_nxt = S_FIFO_WAIT;
				end else if (pause_req) begin
					fifo_push = 1'b1;
					count_nxt = count - 12'd1;
					addr_nxt = addr + 22'd1;
					state_nxt = |count ? S_TO_PAUSE : S_TO_IDLE;
				end else begin
					fifo_push = 1'b1;
					count_nxt = count - 12'd1;
					addr_nxt = addr + 22'd1;
					state_nxt = |count ? S_SHIFT_DATA : S_TO_IDLE;
				end
			end
		end
	end
	S_FIFO_WAIT: begin
		if (!fifo_full) begin
			fifo_push = 1'b1;
			count_nxt = count - 12'd1;
			addr_nxt = addr + 22'd1;
			if (pause_req) begin
				state_nxt = |count ? S_TO_PAUSE : S_TO_IDLE;
			end else begin
				state_nxt = |count ? S_SHIFT_DATA : S_TO_IDLE;
				bit_ctr_nxt = 5'd31;
			end
		end
	end
	S_TO_PAUSE: begin
		cs_n_nxt = 1'b1;
		state_nxt = S_PAUSED_BUSY;
	end
	S_PAUSED_BUSY: begin
		if (!pause_req) begin
			state_nxt = S_FRONTPORCH;
		end
	end
	S_PAUSED_IDLE: begin
		if (csr_start) begin
			state_nxt = S_PAUSED_BUSY;
		end else if (!pause_req) begin
			state_nxt = S_IDLE;
		end
	end
	S_TO_IDLE: begin
		cs_n_nxt = 1'b1;
		state_nxt = S_IDLE;
		finish_now = 1'b1;
	end
	endcase
end

// Advance current to next state
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		state   <= '0;
		sck     <= '0;
		mosi    <= '0;
		cs_n    <= 1'b1;
		bit_ctr <= '0;
		sreg    <= '0;
		addr    <= '0;
		count   <= '0;
	end else begin
		state   <= state_nxt;
		sck     <= sck_nxt;
		mosi    <= mosi_nxt;
		cs_n    <= cs_n_nxt;
		bit_ctr <= bit_ctr_nxt;
		sreg    <= sreg_nxt;
		addr    <= addr_nxt;
		count   <= count_nxt;

		// Register writes override update
		if (addr_wen) begin
			addr <= addr_o;
		end
		if (count_wen) begin
			count <= count_o;
		end

	end
end

assign spi_mosi = mosi;
assign spi_cs_n = cs_n;
assign spi_sck = sck;

assign csr_busy = state != S_IDLE && state != S_PAUSED_IDLE;
assign pause_ack = state == S_PAUSED_IDLE || state == S_PAUSED_BUSY;
assign csr_finished_i = finish_now;

// ----------------------------------------------------------------------------
// Data RX FIFO

wire fifo_empty;
assign csr_fvalid = !fifo_empty;
sync_fifo #(
	.DEPTH (2),
	.WIDTH (32)
) fifo_u (
	.clk   (clk),
	.rst_n (rst_n),

	.wdata (sreg_nxt),
	.wen   (fifo_push),
	.rdata (fifo_i),
	.ren   (fifo_ren),
	.flush (csr_flush),
	.full  (fifo_full),
	.empty (fifo_empty),
	.level (csr_flevel)
);

assign irq = csr_finished_o || csr_flevel > csr_irqlevel;

// ----------------------------------------------------------------------------
// Clock divider

reg [2:0] clkdiv_ctr;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		clkdiv_ctr <= 3'd1;
		clk_en <= 1'b0;
	end else if (clkdiv_ctr == 3'd1) begin
		clkdiv_ctr <= clkdiv;
		clk_en <= 1'b1;
	end else begin
		clkdiv_ctr <= clkdiv_ctr - 3'd1;
		clk_en <= 1'b0;
	end
end

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
