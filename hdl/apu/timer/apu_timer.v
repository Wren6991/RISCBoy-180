/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

module apu_timer (
	input wire         clk,
	input wire         rst_n,
	
	input  wire [15:0] ahbls_haddr,
	input  wire [1:0]  ahbls_htrans,
	input  wire        ahbls_hwrite,
	input  wire [2:0]  ahbls_hsize,
	input  wire        ahbls_hready,
	output wire        ahbls_hready_resp,
	input  wire [31:0] ahbls_hwdata,
	output wire [31:0] ahbls_hrdata,
	output wire        ahbls_hresp,

	output wire        irq
);

// ----------------------------------------------------------------------------
// Register interface

localparam             W_CTR    = 20;
localparam             N_TIMERS = 3;
localparam             W_TICK   = 8;
localparam [W_CTR-1:0] CTR_ONE  = {{W_CTR-1{1'b0}}, 1'b1};

wire [N_TIMERS-1:0] csr_en;
wire [N_TIMERS-1:0] csr_reload;
reg  [N_TIMERS-1:0] csr_irq_i;
wire [N_TIMERS-1:0] csr_irq_o;

wire [W_TICK-1:0]   tick_period;

wire [W_CTR-1:0]    reload   [0:N_TIMERS-1];
reg  [W_CTR-1:0]    ctr      [0:N_TIMERS-1];
wire [W_CTR-1:0]    ctr_o    [0:N_TIMERS-1];
wire [N_TIMERS-1:0] ctr_wen;

assign irq = |csr_irq_o;

apu_timer_regs regs_u (
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

	.csr_en_o          (csr_en),
	.csr_reload_o      (csr_reload),
	.csr_irq_i         (csr_irq_i),
	.csr_irq_o         (csr_irq_o),

	.tick_o            (tick_period),

	.reload0_o         (reload[0]),
	.ctr0_i            (ctr[0]),
	.ctr0_o            (ctr_o[0]),
	.ctr0_wen          (ctr_wen[0]),

	.reload1_o         (reload[1]),
	.ctr1_i            (ctr[1]),
	.ctr1_o            (ctr_o[1]),
	.ctr1_wen          (ctr_wen[1]),

	.reload2_o         (reload[2]),
	.ctr2_i            (ctr[2]),
	.ctr2_o            (ctr_o[2]),
	.ctr2_wen          (ctr_wen[2])
);

// ----------------------------------------------------------------------------
// Tick: global timebase

reg [W_TICK-1:0] tick_ctr;
reg              tick;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		tick_ctr <= {W_TICK{1'b0}};
		tick <= 1'b0;
	end else if (~|tick_ctr) begin
		tick_ctr <= tick_period;
		tick <= 1'b1;
	end else begin
		tick_ctr <= tick_ctr - {{W_TICK-1{1'b0}}, 1'b1};
		tick <= 1'b0;
	end
end

// ----------------------------------------------------------------------------
// Individual counters and IRQs

always @ (posedge clk) begin: count
	integer i;
	for (i = 0; i < N_TIMERS; i = i + 1) begin
		if (ctr_wen[i]) begin
			ctr[i] <= ctr_o[i];
		end else if (tick) begin
			if (~|ctr[i] && csr_en[i] && csr_reload[i]) begin
				ctr[i] <= reload[i];
			end else if (|ctr[i] && csr_en[i]) begin
				ctr[i] <= ctr[i] - CTR_ONE;
			end
		end
	end
end

always @ (*) begin: check_irq
	integer i;
	for (i = 0; i < N_TIMERS; i = i + 1) begin
		csr_irq_i[i] = tick && csr_en[i] && ctr[i] == CTR_ONE;
	end
end

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
