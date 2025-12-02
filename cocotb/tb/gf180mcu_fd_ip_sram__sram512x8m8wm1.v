/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Simple model for GF SRAM

// Doesn't feel good to replace a vendor model but their RAM model is...
// seriously broken. See:
//
//   https://github.com/wafer-space/gf180mcu-project-template/issues/38

`default_nettype none

module gf180mcu_fd_ip_sram__sram512x8m8wm1 (
	input  wire       CLK,
	input  wire       CEN,
	input  wire       GWEN,
	input  wire [7:0] WEN,
	input  wire [8:0] A,
	input  wire [7:0] D,
	output reg  [7:0] Q,
	inout  wire       VDD,
	inout  wire       VSS
);

reg [7:0] mem [0:511];

always @ (posedge CLK) begin: update
	integer i;
	if (!CEN && GWEN) begin
		Q <= mem[A];
	end else if (!CEN && !GWEN) begin
		for (i = 0; i < 8; i = i + 1) begin
			if (!WEN[i]) begin
				mem[A][i] <= D[i];
			end
		end
	end
end

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
