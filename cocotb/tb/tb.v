`timescale 1ns/1ps

`default_nettype none

module tb;

// Deliberately do not set these in the module instantiation to avoid testing
// a configuration different from the one that is taped out:
localparam N_SRAM_DQ = 16;
localparam N_SRAM_A  = 18;
localparam N_GPIO    = 6;

wire                 VDD;
wire                 VSS;
wire                 CLK;
wire                 RSTn;
wire                 DCK;
wire                 DIO;
wire [N_SRAM_DQ-1:0] SRAM_DQ;
wire [N_SRAM_A-1:0]  SRAM_A;
wire                 SRAM_OEn;
wire                 SRAM_CSn;
wire                 SRAM_WEn;
wire                 SRAM_UBn;
wire                 SRAM_LBn;
wire                 AUDIO_L;
wire                 AUDIO_R;
wire                 LCD_CLK;
wire                 LCD_DAT;
wire                 LCD_CSn;
wire                 LCD_DC;
wire                 LCD_BL;
wire [N_GPIO-1:0]    GPIO;

// Behavioural clock generator is much faster than cocotb :/
reg clk_running = 1'b0;
reg clk = 1'b0;
localparam CLK_PERIOD = 1000.0 / 24;
initial begin
	while (1) begin
		#(CLK_PERIOD * 0.5);
		clk = 1'b0;
		#(CLK_PERIOD * 0.5);
		clk = clk_running;
	end
end
assign CLK = clk;


chip_top chip_u (
	.VDD      (VDD),
	.VSS      (VSS),
	.CLK      (CLK),
	.RSTn     (RSTn),
	.DCK      (DCK),
	.DIO      (DIO),
	.SRAM_DQ  (SRAM_DQ),
	.SRAM_A   (SRAM_A),
	.SRAM_OEn (SRAM_OEn),
	.SRAM_CSn (SRAM_CSn),
	.SRAM_WEn (SRAM_WEn),
	.SRAM_UBn (SRAM_UBn),
	.SRAM_LBn (SRAM_LBn),
	.AUDIO_L  (AUDIO_L),
	.AUDIO_R  (AUDIO_R),
	.LCD_CLK  (LCD_CLK),
	.LCD_DAT  (LCD_DAT),
	.LCD_CSn  (LCD_CSn),
	.LCD_DC   (LCD_DC),
	.LCD_BL   (LCD_BL),
	.GPIO     (GPIO)
);

spi_flash_model flash_u (
	.SCK (GPIO[0]),
	.CSn (GPIO[1]),
	.IO0 (GPIO[2]),
	.IO1 (GPIO[3])
);

sram_async #(
	.W_DATA (16),
	.DEPTH (1 << 18)
) eram_u (
	.addr  (SRAM_A),
	.dq    (SRAM_DQ),
	.ce_n  (SRAM_CSn),
	.oe_n  (SRAM_OEn),
	.we_n  (SRAM_WEn),
	.ben_n ({SRAM_UBn, SRAM_LBn})
);

endmodule
