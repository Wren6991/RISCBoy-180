/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// 63-tap FIR filter with a cutoff of 22 kHz, assuming a 16 * 48 kHz sample rate
// rate (768 kHz).
//
// This filter was "designed" (and I use the term very loosely) using filter.py
//
// It is equivalent to stuffing each sample with 15 zeroes and then running
// through a 63-element delay line. However because most of the samples are
// zero, we only need to store 64/16 = 4 of them, and rotate 16 coefficients
// past the nonzero samples while they remain in position.

`default_nettype wire

module apu_lowpass_filter (
	input  wire        clk,
	input  wire        rst_n,
	input  wire        en_shift,
	input  wire        en,
	input  wire [15:0] d,
	output wire [15:0] q
);

localparam W_SAMPLE = 16;
localparam W_COEFF = 9;
localparam TAPS = 64; // last one is zero
localparam [W_COEFF * TAPS -1:0] COEFF = {
	9'h000, 9'h1fe, 9'h1fe, 9'h1fd, 9'h1fc, 9'h1fb, 9'h1fa, 9'h1f9,
	9'h1f8, 9'h1f7, 9'h1f6, 9'h1f6, 9'h1f8, 9'h1fa, 9'h1fd, 9'h003,
	9'h009, 9'h012, 9'h01d, 9'h029, 9'h037, 9'h046, 9'h056, 9'h067,
	9'h078, 9'h089, 9'h099, 9'h0a7, 9'h0b4, 9'h0be, 9'h0c6, 9'h0ca,
	9'h0cc, 9'h0ca, 9'h0c6, 9'h0be, 9'h0b4, 9'h0a7, 9'h099, 9'h089,
	9'h078, 9'h067, 9'h056, 9'h046, 9'h037, 9'h029, 9'h01d, 9'h012,
	9'h009, 9'h003, 9'h1fd, 9'h1fa, 9'h1f8, 9'h1f6, 9'h1f6, 9'h1f7,
	9'h1f8, 9'h1f9, 9'h1fa, 9'h1fb, 9'h1fc, 9'h1fd, 9'h1fe, 9'h1fe
};

reg [3:0] offset;
reg [15:0] s [0:3];

always @ (posedge clk) if (en_shift) begin: shift
	integer i;
	s[0] <= d;
	for (i = 1; i < 33; i = i + 1) begin
		s[i] <= s[i - 1];
	end
end

always @ (posedge clk) begin
	if (en_shift) begin
		offset <= 4'd0;
	end else if (en) begin
		offset <= offset + 4'd1;
	end
end

wire [W_COEFF-1:0] c0 = COEFF[{2'd0, offset} * W_COEFF +: W_COEFF];
wire [W_COEFF-1:0] c1 = COEFF[{2'd1, offset} * W_COEFF +: W_COEFF];
wire [W_COEFF-1:0] c2 = COEFF[{2'd2, offset} * W_COEFF +: W_COEFF];
wire [W_COEFF-1:0] c3 = COEFF[{2'd3, offset} * W_COEFF +: W_COEFF];

reg  [W_COEFF+W_SAMPLE-1:0] mul0;
reg  [W_COEFF+W_SAMPLE-1:0] mul1;
reg  [W_COEFF+W_SAMPLE-1:0] mul2;
reg  [W_COEFF+W_SAMPLE-1:0] mul3;

always @ (posedge clk) if (en) begin
	mul0 <= {{W_COEFF{s[0][W_SAMPLE-1]}}, s[0]} * c0;
	mul1 <= {{W_COEFF{s[1][W_SAMPLE-1]}}, s[1]} * c1;
	mul2 <= {{W_COEFF{s[2][W_SAMPLE-1]}}, s[2]} * c2;
	mul3 <= {{W_COEFF{s[3][W_SAMPLE-1]}}, s[3]} * c3;
end

wire [W_COEFF+W_SAMPLE-1:0] sum = mul0 + mul1 + mul2 + mul3;

reg  [15:0] q_r;
reg  [2:0] blank_ctr;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		blank_ctr <= 3'd5;
		q_r <= 16'h8000;
	end else if (en) begin
		if (en_shift) begin
			blank_ctr <= blank_ctr - {2'd0, |blank_ctr};
		end
		if (~|blank_ctr) begin
			q_r <= sum[W_COEFF - 1 +: W_SAMPLE];
		end
	end
end

assign q = q_r;

endmodule

`ifndef YOSYS
`default_nettype none
`endif


