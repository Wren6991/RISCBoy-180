/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

module gpio #(
	parameter N_GPIO = 8 // do not change without updating registers
) (
	input wire                clk,
	input wire                rst_n,
	
	// APB Port
	input  wire               apbs_psel,
	input  wire               apbs_penable,
	input  wire               apbs_pwrite,
	input  wire [15:0]        apbs_paddr,
	input  wire [31:0]        apbs_pwdata,
	output wire [31:0]        apbs_prdata,
	output wire               apbs_pready,
	output wire               apbs_pslverr,

	input  wire               audio_l,
	input  wire               audio_r,

	output wire [N_GPIO-1:0] padout_gpio,
	output wire [N_GPIO-1:0] padoe_gpio,
	input  wire [N_GPIO-1:0] padin_gpio
);

// ----------------------------------------------------------------------------
// Connect alternate functions

wire [N_GPIO-1:0] alt_out = {
	audio_l,
	audio_r,
	6'd0
};

wire [N_GPIO-1:0] alt_oen  = {
	1'b1,
	1'b1,
	6'd0
};

// ----------------------------------------------------------------------------
// Register block

wire [N_GPIO-1:0] out_i;
wire [N_GPIO-1:0] out_o;
wire              out_wen;
wire [N_GPIO-1:0] out_xor_i;
wire [N_GPIO-1:0] out_xor_o;
wire              out_xor_wen;
wire [N_GPIO-1:0] out_set_i;
wire [N_GPIO-1:0] out_set_o;
wire              out_set_wen;
wire [N_GPIO-1:0] out_clr_i;
wire [N_GPIO-1:0] out_clr_o;
wire              out_clr_wen;
wire [N_GPIO-1:0] oen_i;
wire [N_GPIO-1:0] oen_o;
wire              oen_wen;
wire [N_GPIO-1:0] oen_xor_i;
wire [N_GPIO-1:0] oen_xor_o;
wire              oen_xor_wen;
wire [N_GPIO-1:0] oen_set_i;
wire [N_GPIO-1:0] oen_set_o;
wire              oen_set_wen;
wire [N_GPIO-1:0] oen_clr_i;
wire [N_GPIO-1:0] oen_clr_o;
wire              oen_clr_wen;
wire [N_GPIO-1:0] gpio_in;
wire [N_GPIO-1:0] fsel;

// Actual registers aliased for write/XOR/set/clear:
reg  [N_GPIO-1:0] gpio_out;
reg  [N_GPIO-1:0] gpio_oen;

gpio_regs regs_u (
	.clk          (clk),
	.rst_n        (rst_n),

	.apbs_psel    (apbs_psel),
	.apbs_penable (apbs_penable),
	.apbs_pwrite  (apbs_pwrite),
	.apbs_paddr   (apbs_paddr),
	.apbs_pwdata  (apbs_pwdata),
	.apbs_prdata  (apbs_prdata),
	.apbs_pready  (apbs_pready),
	.apbs_pslverr (apbs_pslverr),

	.out_i        (gpio_out),
	.out_o        (out_o),
	.out_wen      (out_wen),
	.out_xor_i    (gpio_out),
	.out_xor_o    (out_xor_o),
	.out_xor_wen  (out_xor_wen),
	.out_set_i    (gpio_out),
	.out_set_o    (out_set_o),
	.out_set_wen  (out_set_wen),
	.out_clr_i    (gpio_out),
	.out_clr_o    (out_clr_o),
	.out_clr_wen  (out_clr_wen),

	.oen_i        (gpio_oen),
	.oen_o        (oen_o),
	.oen_wen      (oen_wen),
	.oen_xor_i    (gpio_oen),
	.oen_xor_o    (oen_xor_o),
	.oen_xor_wen  (oen_xor_wen),
	.oen_set_i    (gpio_oen),
	.oen_set_o    (oen_set_o),
	.oen_set_wen  (oen_set_wen),
	.oen_clr_i    (gpio_oen),
	.oen_clr_o    (oen_clr_o),
	.oen_clr_wen  (oen_clr_wen),

	.in_i         (gpio_in),

	.fsel_o       (fsel)
);

// ----------------------------------------------------------------------------
// Output registers and muxing

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		gpio_out <= {N_GPIO{1'b0}};
		gpio_oen <= {N_GPIO{1'b0}};
	end else begin
		if (out_wen) begin
			gpio_out <= out_o;
		end else if (out_xor_wen) begin
			gpio_out <= gpio_out ^ out_xor_o;
		end else if (out_set_wen) begin
			gpio_out <= gpio_out | out_set_o;
		end else if (out_clr_wen) begin
			gpio_out <= gpio_out & ~out_clr_o;
		end
		if (oen_wen) begin
			gpio_oen <= oen_o;
		end else if (oen_xor_wen) begin
			gpio_oen <= gpio_oen ^ oen_xor_o;
		end else if (oen_set_wen) begin
			gpio_oen <= gpio_oen | oen_set_o;
		end else if (oen_clr_wen) begin
			gpio_oen <= gpio_oen & ~oen_clr_o;
		end
	end
end

assign padout_gpio = (gpio_out & ~fsel) | (alt_out & fsel);
assign padoe_gpio  = (gpio_oen & ~fsel) | (alt_oen & fsel);

// ----------------------------------------------------------------------------
// Input synchronisers

sync_1bit gpio_in_sync_u [N_GPIO-1:0] (
	.clk   (clk),
	.rst_n (rst_n),
	.i     (padin_gpio),
	.o     (gpio_in)
);

endmodule

`ifndef YOSYS
`default_nettype wire
`endif