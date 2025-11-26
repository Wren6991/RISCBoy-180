/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Input: stream of 16-bit stereo samples, presumably from an async FIFO
//
// Output: 2x PWM with a carrier of clk / 16.
//
// One sample is consumed every 4 x (repeat_interval + 4) cycles.

`default_nettype none

module apu_aout (
	input  wire        clk,
	input  wire        rst_n,

	input  wire        en,

	input  wire [7:0]  repeat_interval,

	input  wire [31:0] sample,
	output wire        sample_rdy,

	output wire        pwm_l,
	output wire        pwm_r
);

// repeat_interval is in units of 1/4 cycle, because we're targeting upsampled
// 16 x 48 kSa/s at 24 MHz -> 31.25 cycles per upsampled sample

reg [1:0] lsb_toggle;
reg [6:0] repeat_ctr;
reg       ctr_wrap;
reg [3:0] stuff_ctr;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		lsb_toggle <= 2'd0;
		repeat_ctr <= 8'd0;
		ctr_wrap <= 1'b0;
		stuff_ctr <= 4'd0;
	end else if (!en) begin
		lsb_toggle <= 2'd0;
		repeat_ctr <= 8'd0;
		ctr_wrap <= 1'b0;
		stuff_ctr <= 4'd0;
	end else if (~|repeat_ctr) begin
		lsb_toggle <= lsb_toggle + 2'd1;
		repeat_ctr <= {1'b0, repeat_interval[7:2]} + {6'd0, repeat_interval[1:0] >= {lsb_toggle[0], lsb_toggle[1]}};
		ctr_wrap <= 1'b1;
		stuff_ctr <= stuff_ctr + 4'd1;
	end else begin
		repeat_ctr <= repeat_ctr - 8'd1;
		ctr_wrap <= 1'b0;
	end
end

assign sample_rdy = ctr_wrap && ~|stuff_ctr;

wire [31:0] sample_filtered;

apu_lowpass_filter lpf_u [1:0] (
	.clk      (clk),
	.rst_n    (rst_n),
	.en       (ctr_wrap),
	.en_shift (sample_rdy),
	.d        (sample),
	.q        (sample_filtered)
);

apu_sdm sdm_u [1:0] (
	.clk   (clk),
	.rst_n (rst_n),
	.d     (sample_filtered),
	.q     ({pwm_l, pwm_r})
);

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
