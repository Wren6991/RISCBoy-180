/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

// Tech mapping file for gf180mcuD 9-track library. Use scan flops to make up
// for other deficiencies in the flop library.

// You should also be able to use this with 7-track, just run:
//   sed -i 's/9t5v0/7t5v0/' gf180_scanflop_map.v

// ----------------------------------------------------------------------------
// DFFEs with positive enable

// Posedge flop with positive enable
module \$_DFFE_PP_ (
	input  D,
	input  C,
	input  E,
	output Q
);
	gf180mcu_fd_sc_mcu9t5v0__sdffq_1 _TECHMAP_REPLACE_ (
		.CLK (C),
		.SI  (D),
		.SE  (E),
		.D   (Q),
		.Q   (Q)
	);

endmodule

// Posedge flop with negative async reset and positive enable
module \$_DFFE_PN0P_ (
	input  D,
	input  C,
	input  R,
	input  E,
	output Q
);
	gf180mcu_fd_sc_mcu9t5v0__sdffrnq_1 _TECHMAP_REPLACE_ (
		.CLK (C),
		.RN  (R),
		.SI  (D),
		.SE  (E),
		.D   (Q),
		.Q   (Q)
	);

endmodule

// Posedge flop with negative async preset and positive enable
module \$_DFFE_PN1P_ (
	input  D,
	input  C,
	input  R,
	input  E,
	output Q
);
	gf180mcu_fd_sc_mcu9t5v0__sdffsnq_1 _TECHMAP_REPLACE_ (
		.CLK  (C),
		.SETN (R),
		.SI   (D),
		.SE   (E),
		.D    (Q),
		.Q    (Q)
	);

endmodule

// ----------------------------------------------------------------------------
// DFFEs with negative enable

// Posedge flop with negative enable
module \$_DFFE_PN_ (
	input  D,
	input  C,
	input  E,
	output Q
);
	gf180mcu_fd_sc_mcu9t5v0__sdffq_1 _TECHMAP_REPLACE_ (
		.CLK (C),
		.SI  (Q),
		.SE  (E),
		.D   (D),
		.Q   (Q)
	);

endmodule

// Posedge flop with negative async reset and negative enable
module \$_DFFE_PN0N_ (
	input  D,
	input  C,
	input  R,
	input  E,
	output Q
);
	gf180mcu_fd_sc_mcu9t5v0__sdffrnq_1 _TECHMAP_REPLACE_ (
		.CLK (C),
		.RN  (R),
		.SI  (Q),
		.SE  (E),
		.D   (D),
		.Q   (Q)
	);

endmodule

// Posedge flop with negative async preset and negative enable
module \$_DFFE_PN1N_ (
	input  D,
	input  C,
	input  R,
	input  E,
	output Q
);
	gf180mcu_fd_sc_mcu9t5v0__sdffsnq_1 _TECHMAP_REPLACE_ (
		.CLK  (C),
		.SETN (R),
		.SI   (Q),
		.SE   (E),
		.D    (D),
		.Q    (Q)
	);

endmodule

// ----------------------------------------------------------------------------
// DFFs with synchronous set/clear

// Posedge flop with positive synchronous clear
module \$_SDFF_PP0_ (
	input  D,
	input  C,
	input  R,
	output Q
);
	gf180mcu_fd_sc_mcu9t5v0__sdffq_1 _TECHMAP_REPLACE_ (
		.CLK  (C),
		.SI   (1'b0),
		.SE   (R),
		.D    (D),
		.Q    (Q)
	);

endmodule

// Posedge flop with positive synchronous set
module \$_SDFF_PP1_ (
	input  D,
	input  C,
	input  R,
	output Q
);
	gf180mcu_fd_sc_mcu9t5v0__sdffq_1 _TECHMAP_REPLACE_ (
		.CLK  (C),
		.SI   (1'b1),
		.SE   (R),
		.D    (D),
		.Q    (Q)
	);

endmodule

// Posedge flop with negative synchronous clear
module \$_SDFF_PN0_ (
	input  D,
	input  C,
	input  R,
	output Q
);
	gf180mcu_fd_sc_mcu9t5v0__sdffq_1 _TECHMAP_REPLACE_ (
		.CLK  (C),
		.SI   (D),
		.SE   (R),
		.D    (1'b0),
		.Q    (Q)
	);

endmodule

// Posedge flop with negative synchronous set
module \$_SDFF_PN1_ (
	input  D,
	input  C,
	input  R,
	output Q
);
	gf180mcu_fd_sc_mcu9t5v0__sdffq_1 _TECHMAP_REPLACE_ (
		.CLK  (C),
		.SI   (D),
		.SE   (R),
		.D    (1'b0),
		.Q    (Q)
	);

endmodule

