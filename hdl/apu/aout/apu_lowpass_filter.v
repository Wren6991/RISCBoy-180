/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// 33-tap FIR filter with a cutoff of 22 kHz, assuming an 8 * 48 kHz sample rate
// rate. Doesn't overflow if fed with seven stuffed zeroes between each input
// sample. Intended to be used in upsampling 48 kSa/s up to 8 * 48 kSa/s.
//
// This filter was "designed" (and I use the term very loosely) using filter.py

`default_nettype wire

module apu_lowpass_filter (
	input  wire        clk,
	input  wire        rst_n,
	input  wire        en,   // very high fanout, try to drive from flop
	input  wire [15:0] d,
	output wire [15:0] q
);

reg [15:0] s [0:32];

always @ (posedge clk) if (en) begin: shift
	integer i;
	s[0] <= d;
	for (i = 1; i < 33; i = i + 1) begin
		s[i] <= s[i - 1];
	end
end

reg [22:0] t [0:32];
always @ (*) begin: zero_extend
	integer i;
	for (i = 0; i < 33; i = i + 1) begin
		t[i] = {7'd0, s[i]};
	end
end

wire [22:0] u0_nxt = 23'd0
// 0  : -7'b0000001
	- (t[0]  << 0)
// 1  : -7'b0000001
	- (t[1]  << 0)
// 2  : -7'b0000010
	- (t[2]  << 1)
// 3  : -7'b0000011
	- (t[3]  << 1)
	- (t[3]  << 0)
// 4  : -7'b0000101
	- (t[4]  << 2)
	- (t[4]  << 0)
// 5  : -7'b0000101
	- (t[5]  << 2)
	- (t[5]  << 0)
// 6  : -7'b0000100
	- (t[6]  << 2)
// 7  : -7'b0000001
	- (t[7]  << 0)
;
wire [22:0] u1_nxt = 23'd0
// 8  : +7'b0000101
	+ (t[8]  << 2)
	+ (t[8]  << 0)
// 9  : +7'b0001110
	+ (t[9]  << 4)
	- (t[9]  << 1)
// 10 : +7'b0011011
	+ (t[10] << 5)
	- (t[10] << 2)
	- (t[10] << 0)
// 11 : +7'b0101010
	+ (t[11] << 5)
	+ (t[11] << 3)
	+ (t[11] << 1)
// 12 : +7'b0111011
	+ (t[12] << 6)
	- (t[12] << 2)
	- (t[12] << 0)
// 13 : +7'b1001010
	+ (t[13] << 6)
	+ (t[13] << 3)
	+ (t[13] << 1)
// 14 : +7'b1010111
	+ (t[14] << 6)
	+ (t[14] << 4)
	+ (t[14] << 3)
	- (t[14] << 0)
// 15 : +7'b1011111
	+ (t[15] << 6)
	+ (t[15] << 5)
	- (t[15] << 0)
// 16 : +7'b1100010
	+ (t[16] << 6)
	+ (t[16] << 5)
	+ (t[16] << 1)
;
wire [22:0] u2_nxt = 23'd0
// 17 : +7'b1011111
	+ (t[17] << 6)
	+ (t[17] << 5)
	- (t[17] << 0)
// 18 : +7'b1010111
	+ (t[18] << 6)
	+ (t[18] << 4)
	+ (t[18] << 3)
	- (t[18] << 0)
// 19 : +7'b1001010
	+ (t[19] << 6)
	+ (t[19] << 3)
	+ (t[19] << 1)
// 20 : +7'b0111011
	+ (t[20] << 6)
	- (t[20] << 2)
	- (t[20] << 0)
// 21 : +7'b0101010
	+ (t[21] << 5)
	+ (t[21] << 3)
	+ (t[21] << 1)
// 22 : +7'b0011011
	+ (t[22] << 5)
	- (t[22] << 2)
	- (t[22] << 0)
// 23 : +7'b0001110
	+ (t[23] << 4)
	- (t[23] << 1)
// 24 : +7'b0000101
	+ (t[24] << 2)
	+ (t[24] << 0)
;
wire [22:0] u3_nxt = 23'd0
// 25 : -7'b0000001
	- (t[25] << 0)
// 26 : -7'b0000100
	- (t[26] << 2)
// 27 : -7'b0000101
	- (t[27] << 2)
	- (t[27] << 0)
// 28 : -7'b0000101
	- (t[28] << 2)
	- (t[28] << 0)
// 29 : -7'b0000011
	- (t[29] << 1)
	- (t[29] << 0)
// 30 : -7'b0000010
	- (t[30] << 1)
// 31 : -7'b0000001
	- (t[31] << 0)
// 32 : -7'b0000001
	- (t[32] << 0)
;

reg[22:0] u0;
reg[22:0] u1;
reg[22:0] u2;
reg[22:0] u3;

always @ (posedge clk) if (en) begin
	u0 <= u0_nxt;
	u1 <= u1_nxt;
	u2 <= u2_nxt;
	u3 <= u3_nxt;
end

wire [22:0] u_sum = u0 + u1 + u2 + u3;
reg  [15:0] q_r;
reg  [5:0] blank_ctr;

always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		blank_ctr <= 6'd35;
		q_r <= 16'd0;
	end else if (en) begin
		blank_ctr <= blank_ctr - |blank_ctr;
		if (~|blank_ctr) begin
			q_r <= u_sum[7 +: 16];
		end
	end
end

assign q = q_r;

endmodule

`ifndef YOSYS
`default_nettype none
`endif


