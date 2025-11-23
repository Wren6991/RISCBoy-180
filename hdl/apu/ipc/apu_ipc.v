/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

module apu_ipc (
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

	output wire        start_apu,
	
	output wire [1:0]  riscv_softirq

);

wire [1:0]  softirq_set_i;
wire [1:0]  softirq_set_o;
wire        softirq_set_wen;
wire [1:0]  softirq_clr_i;
wire [1:0]  softirq_clr_o;
wire        softirq_clr_wen;

apu_ipc_regs regs_u (
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

	.softirq_set_i     (softirq_set_i),
	.softirq_set_o     (softirq_set_o),
	.softirq_set_wen   (softirq_set_wen),
	.softirq_clr_i     (softirq_clr_i),
	.softirq_clr_o     (softirq_clr_o),
	.softirq_clr_wen   (softirq_clr_wen)
);

reg [1:0] softirq_status;
assign softirq_clr_i = softirq_status;
assign softirq_set_i = softirq_status;
assign riscv_softirq = softirq_status;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		softirq_status <= 2'b00;
	end else begin
		softirq_status <= (softirq_status
			& ~({2{softirq_clr_wen}} & softirq_clr_o)
		) | ({2{softirq_set_wen}} & softirq_set_o);
	end
end

endmodule

`ifndef YOSYS
`default_nettype wire
`endif