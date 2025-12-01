`timescale 1ns/1ps

`default_nettype none

module tb;

// Deliberately do not set these in the module instantiation to avoid testing
// a configuration different from the one that is taped out:
localparam N_SRAM_DQ = 16;
localparam N_SRAM_A  = 17;
localparam N_GPIO    = 4;

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
wire                 AUDIO;
wire                 LCD_CLK;
wire [7:0]           LCD_DAT;
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
	.AUDIO    (AUDIO),
	.LCD_CLK  (LCD_CLK),
	.LCD_DAT  (LCD_DAT),
	.LCD_DC   (LCD_DC),
	.LCD_BL   (LCD_BL),
	.GPIO     (GPIO)
);

spi_flash_model flash_u (
	.SCK (GPIO[1]),
	.CSn (GPIO[2]),
	.IO0 (GPIO[0]),
	.IO1 (GPIO[3])
);

sram_async #(
	.W_DATA (16),
	.DEPTH (1 << N_SRAM_A)
) eram_u (
	.addr  (SRAM_A),
	.dq    (SRAM_DQ),
	.ce_n  (SRAM_CSn),
	.oe_n  (SRAM_OEn),
	.we_n  (SRAM_WEn),
	.ben_n (2'b00)
);

// LCD capture
reg lcd_capture_enable = 1'b0;
reg lcd_bus_width = 1'b0;
integer lcd_bit_count = 0;
integer lcd_byte_count = 0;
reg [7:0] sreg;
reg [8:0] lcd_capture_buffer [0:65535];

always @ (posedge LCD_CLK or negedge lcd_capture_enable) begin
	if (!lcd_capture_enable) begin
		lcd_bit_count = 0;
		lcd_byte_count = 0;
		sreg = 0;
	end else if (lcd_bus_width) begin
		lcd_capture_buffer[lcd_byte_count] = {LCD_DC, LCD_DAT};
		lcd_byte_count = lcd_byte_count + 1;
	end else begin
		sreg = {sreg[6:0], LCD_DAT[0]};
		lcd_bit_count = lcd_bit_count + 1;
		if (lcd_bit_count == 8) begin
			lcd_capture_buffer[lcd_byte_count] = {LCD_DC, sreg};
			lcd_bit_count = 0;
			lcd_byte_count = lcd_byte_count + 1;
		end
	end
end

endmodule
