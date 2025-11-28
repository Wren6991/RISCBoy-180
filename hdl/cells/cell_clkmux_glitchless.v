/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Clock gate (ICG) which latches enable on posedge and holds the clock low
// when the enable is low.

// For VDD/VSS:
/* verilator lint_off PINMISSING */

`default_nettype none

module cell_clkmux_glitchless #(
	parameter N_CLOCKS = 3
) (
	input  wire [N_CLOCKS-1:0]         clk_in,
	input  wire                        rst_n,
	input  wire [$clog2(N_CLOCKS)-1:0] sel,
	output wire [N_CLOCKS-1:0]         selected,
	output wire                        clk_out
);

// Sync removal of async reset to each clock, to reset local state.
wire [N_CLOCKS-1:0] rst_n_sync;
reset_sync reset_sync_u [N_CLOCKS-1:0] (
	.clk       (clk_in),
	.rst_n_in  (rst_n),
	.rst_n_out (rst_n_sync)
);

wire [$clog2(N_CLOCKS)-1:0] sel_fp;
falsepath_anchor fp_sel_u [$clog2(N_CLOCKS)-1:0] (
	.i (sel),
	.z (sel_fp)
);
wire [N_CLOCKS-1:0] sel_mask = {{N_CLOCKS-1{1'b0}}, 1'b1} << sel_fp;

// Enable the selected clock only once other clocks have stopped 
wire [N_CLOCKS-1:0] enable_nofp = sel_mask &
	{N_CLOCKS{~|(selected & ~sel_mask)}};

wire [N_CLOCKS-1:0] enable;
falsepath_anchor fp_enable_u [N_CLOCKS-1:0] (
	.i (enable_nofp),
	.z (enable)
);

// Synchronise enables to each respective clock for use in gating. When rst_n
// is applied, all clocks are gated, so the output is stopped.
wire [N_CLOCKS-1:0] enable_sync;
sync_1bit sync_enable_u [N_CLOCKS-1:0] (
	.clk   (clk_in),
	.rst_n (rst_n_sync),
	.i     (enable),
	.o     (enable_sync)
);

// Gate each clock with its one-hot-0 enable bit
wire [N_CLOCKS-1:0] clk_gated;

genvar g;
generate
for (g = 0; g < N_CLOCKS; g = g + 1) begin: loop_g

	reg selected_q;
	always @ (posedge clk_in[g] or negedge rst_n_sync[g]) begin
		if (!rst_n_sync[g]) begin
			selected_q <= 1'b0;
		end else begin
			selected_q <= enable_sync[g];
		end
	end
	assign selected[g] = selected_q;

	cell_clkgate_low gate_u (
		.clk_in (clk_in[g]),
		.enable (enable_sync[g]),
		.clk_out (clk_gated[g])
	);

end
endgenerate

// OR gated clocks together to get final output
generate
if (N_CLOCKS == 2) begin: ckor_2_g
	// Best we can do is a 2-input OR gate
	(*keep*)
	gf180mcu_fd_sc_mcu9t5v0__or2_4 or_u (
		.A1 (clk_gated[0]),
		.A2 (clk_gated[1]),
		.Z  (clk_out)
	);
end
// Don't use else if because yosys does genblk1.genblk1. ...
if (N_CLOCKS == 3) begin: ckor_3_g
	// Best we can do is a 3-input OR gate
	(*keep*)
	gf180mcu_fd_sc_mcu9t5v0__or3_4 or_u (
		.A1 (clk_gated[0]),
		.A2 (clk_gated[1]),
		.A3 (clk_gated[2]),
		.Z  (clk_out)
	);
end
if (N_CLOCKS == 4) begin: ckor_4_g
	// Use NOR-NAND combo to try to reduce pulse distortion (equivalent to
	// 4-input OR)
	wire z1, z0;
	(*keep*)
	gf180mcu_fd_sc_mcu9t5v0__nor2_4 nor0_u (
		.A1 (clk_gated[0]),
		.A2 (clk_gated[1]),
		.ZN (z0)
	);
	(*keep*)
	gf180mcu_fd_sc_mcu9t5v0__nor2_4 nor1_u (
		.A1 (clk_gated[2]),
		.A2 (clk_gated[3]),
		.ZN (z1)
	);
	(*keep*)
	gf180mcu_fd_sc_mcu9t5v0__nand2_4 nand_u (
		.A1 (z0),
		.A2 (z1),
		.ZN (clk_out)
	);
end
if (N_CLOCKS < 2 || N_CLOCKS > 4) begin: fatal_n_clocks_g
	$fatal("Unsupported value for N_CLOCKS");
end
endgenerate

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
