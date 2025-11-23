/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Input: 16-bit sample every 16 cycles (assumed to be repeated samples from a
// much slower stream)

// Output: 4-bit PWM at 1/16th the frequency of clk (e.g. 24 MHz audio clk ->
// 1.5 MHz PWM output)

`default_nettype none

module apu_sdm #(
	parameter W_SAMPLE = 16,
	parameter W_PWM = 4
) (
	input  wire                clk,
	input  wire                rst_n,
	input  wire [W_SAMPLE-1:0] d,
	output reg                 q 
);

reg  [W_PWM-1:0] pwm_ctr;
wire pwm_wrap = &pwm_ctr;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		pwm_ctr <= {W_PWM{1'b0}};
	end else begin
		pwm_ctr <= pwm_ctr + 1'b1;
	end
end

reg  [W_SAMPLE:0] accum;
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		accum <= {W_SAMPLE+1{1'b0}};
	end else if (pwm_wrap) begin
		accum <= {{W_PWM+1{1'b0}}, accum[W_SAMPLE-W_PWM-1:0]} + {1'b0, d};
	end
end

wire [W_PWM:0] pwm_level = accum[W_SAMPLE + 1 -: W_PWM + 1];

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		q <= pwm_level > {1'b0, pwm_ctr};
	end
end

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
