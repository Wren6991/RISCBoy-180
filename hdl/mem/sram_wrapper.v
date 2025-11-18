// Instantiate GF180MCU single-ported RAM macros so they behave as a single,
// larger synchronous RAM.
//
// Limitations:
//
// * WIDTH must be a multiple of 8.
// * DEPTH must be a power of 2, >= 128.

`default_nettype none

module sram_wrapper #(
	parameter WIDTH = 32,
	parameter DEPTH = 512
) (
`ifdef GF180MCU
	inout  wire                     VDD,
	inout  wire                     VSS,
`endif
	input  wire                     clk,
	input  wire                     cs_n, // Active-low chip select
	input  wire                     we_n, // Active-low write enable
	input  wire [WIDTH/8-1:0]       be_n, // Active-low byte enable (for writes)
	input  wire [$clog2(DEPTH)-1:0] addr,
	input  wire [WIDTH-1:0]         wdata,
	output wire [WIDTH-1:0]         rdata
);

`ifdef GF180MCU
// ----------------------------------------------------------------------------
// ASIC memory instantiation for GF180MCU process

// Note: the size options are mutually exclusive, so should be `if else if`,
// but Yosys creates an insane hierarchical path like `.genblk1.genblk1...`,
// presumably creating an unnamed block on each else. So just an if per block.

genvar x, y;
generate
if (DEPTH < 128 || (DEPTH & (DEPTH - 1))) begin: err_depth
	initial $fatal("DEPTH must be a power of two, >= 128");
end

if (WIDTH % 8 != 0) begin: err_width
	initial $fatal("WIDTH must be a multiple of eight");
end

if (DEPTH == 128) begin: g_d128

	for (x = 0; x < WIDTH / 8; x = x + 1) begin: g_width
		gf180mcu_fd_ip_sram__sram128x8m8wm1 ram_u (
			.VDD  (VDD),
			.VSS  (VSS),
			.CLK  (clk),
			.CEN  (cs_n),
			.GWEN (we_n),
			.WEN  (be_n),
			.A    (addr),
			.D    (wdata[x * 8 +: 8]),
			.Q    (rdata[x * 8 +: 8])
		);
	end

end

if (DEPTH == 256) begin: g_d256

	for (x = 0; x < WIDTH / 8; x = x + 1) begin: g_width
		gf180mcu_fd_ip_sram__sram256x8m8wm1 ram_u (
			.VDD  (VDD),
			.VSS  (VSS),
			.CLK  (clk),
			.CEN  (cs_n),
			.GWEN (we_n),
			.WEN  (be_n),
			.A    (addr),
			.D    (wdata[x * 8 +: 8]),
			.Q    (rdata[x * 8 +: 8])
		);
	end

end

if (DEPTH == 512) begin: g_d512

	for (x = 0; x < WIDTH / 8; x = x + 1) begin: g_width
		gf180mcu_fd_ip_sram__sram512x8m8wm1 ram_u (
			.VDD  (VDD),
			.VSS  (VSS),
			.CLK  (clk),
			.CEN  (cs_n),
			.GWEN (we_n),
			.WEN  (be_n),
			.A    (addr),
			.D    (wdata[x * 8 +: 8]),
			.Q    (rdata[x * 8 +: 8])
		);
	end

end

if (DEPTH > 512) begin: g_dg512

	// Decode RAM select from address
	wire [DEPTH/512-1:0] ramsel_aph = {
		{DEPTH/512-1{1'b0}},
		1'b1
	} << addr[$clog2(DEPTH)-1:9];

	// Register the select for use in rdata muxing
	reg [DEPTH/512-1:0] ramsel_dph;
	always @ (posedge clk) begin
		ramsel_dph <= ramsel_aph;
	end

	// One-hot mux of output data using registers RAM select
	wire [WIDTH-1:0] rdata_per_ram [0:DEPTH/512-1];
	reg  [WIDTH-1:0] rdata_q;
	assign rdata = rdata_q;

	always @ (*) begin: mux_rdata
		integer i;
		rdata_q = {WIDTH{1'b0}};
		for (i = 0; i < DEPTH / 512; i = i + 1) begin
			rdata_q = rdata_q | (rdata_per_ram[i] & {WIDTH{ramsel_dph}});
		end
	end

	for (y = 0; y < DEPTH / 512; y = y + 1) begin: g_depth
		for (x = 0; x < WIDTH / 8; x = x + 1) begin: g_width
			gf180mcu_fd_ip_sram__sram512x8m8wm1 ram_u (
				.VDD  (VDD),
				.VSS  (VSS),
				.CLK  (clk),
				.CEN  (cs_n || !ramsel_aph[y]),
				.GWEN (we_n),
				.WEN  (be_n),
				.A    (addr[8:0]),
				.D    (wdata[x * 8 +: 8]),
				.Q    (rdata_per_ram[y][x * 8 +: 8])
			);
		end
	end


end
endgenerate

`else
// ----------------------------------------------------------------------------
// Behavioural model

reg [WIDTH-1:0] mem [0:DEPTH-1];

reg [WIDTH-1:0] rdata_q;
assign rdata = rdata_q;
always @ (posedge clk) begin: update
	integer i;
	if (!cs_n && we_n) begin
		rdata_q <= mem[addr];
	end
	if (!cs_n && !we_n) begin
		for (i = 0; i < WIDTH / 8; i = i + 1) begin
			if (!be_n[i]) begin
				mem[addr][i * 8 +: 8] <= wdata;
			end
		end	
	end
end

`endif

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
