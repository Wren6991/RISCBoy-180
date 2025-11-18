// Derived from ahb_sync_sram in libfpga. Removed some FPGA junk like 1R1W,
// and use project-specific SRAM wrapper.

// AHB-lite to synchronous SRAM adapter with no wait states. Uses a write
// buffer with a write-to-read forwarding path to handle SRAM address
// collisions caused by misalignment of AHBL write address and write data.
//
// Optionally, the write buffer can be removed to save a small amount of
// logic. The adapter will then insert one wait state on write->read pairs.

`default_nettype none

module ahb_sync_sram #(
	parameter W_DATA = 32,
	parameter W_ADDR = 32,
	parameter DEPTH = 1 << 11,
	parameter PRELOAD_FILE = ""
) (
	// Globals
	input  wire               clk,
	input  wire               rst_n,
`ifdef GF180MCU
	inout  wire               VDD,
	inout  wire               VSS,
`endif
	// AHB subordinate interface
	output wire               ahbls_hready_resp,
	input  wire               ahbls_hready,
	output wire               ahbls_hresp,
	input  wire [W_ADDR-1:0]  ahbls_haddr,
	input  wire               ahbls_hwrite,
	input  wire [1:0]         ahbls_htrans,
	input  wire [2:0]         ahbls_hsize,
	input  wire [2:0]         ahbls_hburst,
	input  wire [3:0]         ahbls_hprot,
	input  wire               ahbls_hmastlock,
	input  wire [W_DATA-1:0]  ahbls_hwdata,
	output wire [W_DATA-1:0]  ahbls_hrdata
);

localparam W_SRAM_ADDR = $clog2(DEPTH);
localparam W_BYTES     = W_DATA / 8;
localparam W_BYTEADDR  = $clog2(W_BYTES);

// ----------------------------------------------------------------------------
// AHBL state machine and buffering

// Need to buffer at least a write address,
// and potentially the data too:
reg [W_SRAM_ADDR-1:0] addr_saved;
reg                   write_saved;
reg [W_BYTEADDR-1:0]  align_saved;
reg [2:0]             size_saved;
reg [W_DATA-1:0]      wdata_saved;
reg                   wbuf_vld;

// Decode AHBL controls
wire ahb_read_aphase  = ahbls_htrans[1] && ahbls_hready && !ahbls_hwrite;
wire ahb_write_aphase = ahbls_htrans[1] && ahbls_hready &&  ahbls_hwrite;

// Mask calculation is deferred to data phase, to avoid address phase delay
wire [W_BYTES-1:0] wmask_noshift = ~({W_BYTES{1'b1}} << (1 << size_saved));
wire [W_BYTES-1:0] wmask_saved = {W_BYTES{write_saved}} & (wmask_noshift << align_saved);

// If we have a write buffer, we can hold onto buffered data during an
// immediately following sequence of reads, and retire the buffer at a later
// time. Otherwise, we must always retire the write immediately (directly from
// the hwdata bus).
wire write_retire = write_saved && !ahb_read_aphase;
wire wdata_capture = !wbuf_vld && |wmask_saved && ahb_read_aphase;

wire [W_SRAM_ADDR-1:0] haddr_row = ahbls_haddr[W_BYTEADDR +: W_SRAM_ADDR];

// AHBL state machine (mainly controlling write buffer)
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		addr_saved <= {W_SRAM_ADDR{1'b0}};
		wdata_saved <= {W_DATA{1'b0}};
		write_saved <= 1'b0;
		size_saved <= 3'h0;
		align_saved <= {W_BYTEADDR{1'b0}};
		wbuf_vld <= 1'b0;
	end else begin
		if (ahb_write_aphase) begin
			write_saved <= 1'b1;
			align_saved <= ahbls_haddr[W_BYTEADDR-1:0];
			size_saved  <= ahbls_hsize;
			addr_saved <= haddr_row;
		end else if (write_retire) begin
			write_saved <= 1'b0;
		end
		if (wdata_capture) begin
			wbuf_vld <= 1'b1;
			wdata_saved <= ahbls_hwdata;
		end else if (write_retire) begin
			wbuf_vld <= 1'b0;
		end
	end
end

// ----------------------------------------------------------------------------
// SRAM and SRAM controls

wire [W_BYTES-1:0] sram_wen = write_retire ? wmask_saved : {W_BYTES{1'b0}};
// Note that following a read collision, the read address is supplied during the AHBL data phase
wire [W_SRAM_ADDR-1:0] sram_addr = write_retire ? addr_saved : haddr_row;
wire [W_DATA-1:0] sram_wdata = wbuf_vld ? wdata_saved : ahbls_hwdata;
wire [W_DATA-1:0] sram_rdata;

sram_wrapper #(
	.WIDTH (W_DATA),
	.DEPTH (DEPTH)
) sram (
`ifdef GF180MCU
	.VDD    (VDD),
	.VSS    (VSS),
`endif
	.clk    (clk),
	.cs_n   (~|{ahb_read_aphase, sram_wen}),
	.we_n   (~|sram_wen),
	.be_n   (~sram_wen),
	.addr   (sram_addr),
	.wdata  (sram_wdata),
	.rdata  (sram_rdata)
);

// ----------------------------------------------------------------------------
// AHBL hookup

assign ahbls_hresp = 1'b0;
assign ahbls_hready_resp = 1'b1;

// Merge buffered write data into AHBL read bus (note that addr_saved is the
// address of a previous write, which will eventually be used to retire that
// write, potentially during the write's corresponding AHBL data phase; and
// haddr_saved is the *current* ahbl data phase, which may be that of a read
// which is preventing a previous write from retiring.)

reg [W_SRAM_ADDR-1:0] haddr_dphase;
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		haddr_dphase <= {W_SRAM_ADDR{1'b0}};
	end else if (ahbls_hready) begin
		haddr_dphase <= haddr_row;
	end
end

wire addr_match = haddr_dphase == addr_saved;
genvar b;
generate
for (b = 0; b < W_BYTES; b = b + 1) begin: write_merge
	assign ahbls_hrdata[b * 8 +: 8] = addr_match && wbuf_vld && wmask_saved[b] ?
		wdata_saved[b * 8 +: 8] : sram_rdata[b * 8 +: 8];
end
endgenerate

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
