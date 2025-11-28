/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

module spi_flash_model #(
	DEPTH = 64 * 1024
) (
	input  wire SCK,
	input  wire CSn,
	inout  wire IO0, // MOSI
	inout  wire IO1  // MISO
);

localparam [1:0] S_CMD   = 0;
localparam [1:0] S_ADDR  = 1;
localparam [1:0] S_RDATA = 2;
localparam [1:0] S_NOP   = 3;

// Doesn't use preload because cocotb doesn't run tests from time 0 :')
reg [7:0] mem [0:DEPTH-1];

reg [23:0] addr;
reg [7:0] cmd;
reg [7:0] shift;
integer bit_ctr = 0;

reg [1:0] state = S_CMD;

reg sdo_nxt;

always @ (posedge SCK or posedge CSn) begin
	if (CSn) begin
		bit_ctr = 8;
		shift = 0;
		state = S_CMD;
		sdo_nxt = 1'b1;
	end else case (state)
		S_CMD: begin
			cmd = {cmd[6:0], IO0};
			bit_ctr = bit_ctr - 1;
			if (bit_ctr == 0) begin
				if (cmd == 8'h03 || cmd == 8'h0b) begin
					state = S_ADDR;
					bit_ctr = 24;
				end else begin
					state = S_NOP;
				end
			end
		end
		S_ADDR: begin
			addr = {addr[22:0], IO0};
			bit_ctr = bit_ctr - 1;
			if (bit_ctr == 0) begin
				state = S_RDATA;
				shift = mem[addr];
				sdo_nxt = shift[7];
				shift = shift << 1;
				bit_ctr = 7;
			end
		end
		S_RDATA: begin
			if (bit_ctr == 0) begin
				addr = addr + 1;
				shift = mem[addr];
				bit_ctr = 8;
			end
			sdo_nxt = shift[7];
			shift = shift << 1;
			bit_ctr = bit_ctr - 1;
		end
		S_NOP: begin
			// pass
		end
	endcase
end

reg sdo;
always @ (negedge SCK or posedge CSn) begin
	if (CSn) begin
		sdo <= 1'b1;
	end else begin
		sdo <= sdo_nxt;
	end
end

assign IO1 = sdo;

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
