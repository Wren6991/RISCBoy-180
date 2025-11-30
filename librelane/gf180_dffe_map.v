
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
		.CLK (C),
		.SN  (R),
		.SI  (D),
		.SE  (E),
		.D   (Q),
		.Q   (Q)
	);

endmodule
