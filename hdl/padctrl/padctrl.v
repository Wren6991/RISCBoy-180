/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

module padctrl #(
	parameter N_GPIO = 13
) (
	input  wire        clk,
	input  wire        rst_n,
	
	input  wire        apbs_psel,
	input  wire        apbs_penable,
	input  wire        apbs_pwrite,
	input  wire [19:0] apbs_paddr,
	input  wire [31:0] apbs_pwdata,
	output wire [31:0] apbs_prdata,
	output wire        apbs_pready,
	output wire        apbs_pslverr,

    output wire                 dio_schmitt,
    output wire                 dio_slew,
    output wire [1:0]           dio_drive,

    output wire                 sram_dq_schmitt,
    output wire                 sram_dq_slew,
    output wire [1:0]           sram_dq_drive,

    output wire                 sram_a_slew,
    output wire [1:0]           sram_a_drive,

    output wire                 sram_strobe_slew,
    output wire [1:0]           sram_strobe_drive,

    output wire                 audio_schmitt,
    output wire                 audio_slew,
    output wire [1:0]           audio_drive,

    output wire                 lcd_clk_slew,
    output wire [1:0]           lcd_clk_drive,

    output wire                 lcd_dat_schmitt,
    output wire                 lcd_dat_slew,
    output wire [1:0]           lcd_dat_drive,

    output wire                 lcd_dc_slew,
    output wire [1:0]           lcd_dc_drive,

    output wire                 lcd_bl_slew,
    output wire [1:0]           lcd_bl_drive,

    output wire                 gpio_schmitt,
    output wire                 gpio_slew,
    output wire [1:0]           gpio_drive,

    output wire [N_GPIO-1:0]    gpio_pu,
    output wire [N_GPIO-1:0]    gpio_pd
);

wire              dio_schmitt_nofp;
wire              dio_slew_nofp;
wire [1:0]        dio_drive_nofp;
wire              sram_dq_schmitt_nofp;
wire              sram_dq_slew_nofp;
wire [1:0]        sram_dq_drive_nofp;
wire              sram_a_slew_nofp;
wire [1:0]        sram_a_drive_nofp;
wire              sram_strobe_slew_nofp;
wire [1:0]        sram_strobe_drive_nofp;
wire              audio_schmitt_nofp;
wire              audio_slew_nofp;
wire [1:0]        audio_drive_nofp;
wire              lcd_clk_slew_nofp;
wire [1:0]        lcd_clk_drive_nofp;
wire              lcd_dat_schmitt_nofp;
wire              lcd_dat_slew_nofp;
wire [1:0]        lcd_dat_drive_nofp;
wire              lcd_dc_slew_nofp;
wire [1:0]        lcd_dc_drive_nofp;
wire              lcd_bl_slew_nofp;
wire [1:0]        lcd_bl_drive_nofp;
wire              gpio_schmitt_nofp;
wire              gpio_slew_nofp;
wire [1:0]        gpio_drive_nofp;
wire [N_GPIO-1:0] gpio_pu_nofp;
wire [N_GPIO-1:0] gpio_pd_nofp;

padctrl_regs regs_u	(
	.clk                 (clk),
	.rst_n               (rst_n),

	.apbs_psel           (apbs_psel),
	.apbs_penable        (apbs_penable),
	.apbs_pwrite         (apbs_pwrite),
	.apbs_paddr          (apbs_paddr),
	.apbs_pwdata         (apbs_pwdata),
	.apbs_prdata         (apbs_prdata),
	.apbs_pready         (apbs_pready),
	.apbs_pslverr        (apbs_pslverr),

	.dio_drive_o         (dio_drive_nofp),
	.dio_slew_o          (dio_slew_nofp),
	.dio_schmitt_o       (dio_schmitt_nofp),

	.gpio_drive_o        (gpio_drive_nofp),
	.gpio_slew_o         (gpio_slew_nofp),
	.gpio_schmitt_o      (gpio_schmitt_nofp),
	.gpio_pu_o           (gpio_pu_nofp),
	.gpio_pd_o           (gpio_pd_nofp),

	.sram_dq_drive_o     (sram_dq_drive_nofp),
	.sram_dq_slew_o      (sram_dq_slew_nofp),
	.sram_dq_schmitt_o   (sram_dq_schmitt_nofp),
	.sram_a_drive_o      (sram_a_drive_nofp),
	.sram_a_slew_o       (sram_a_slew_nofp),
	.sram_strobe_drive_o (sram_strobe_drive_nofp),
	.sram_strobe_slew_o  (sram_strobe_slew_nofp),

	.audio_schmitt_o     (audio_schmitt_nofp),
	.audio_drive_o       (audio_drive_nofp),
	.audio_slew_o        (audio_slew_nofp),

	.lcd_clk_drive_o     (lcd_clk_drive_nofp),
	.lcd_clk_slew_o      (lcd_clk_slew_nofp),
	.lcd_dat_schmitt_o   (lcd_dat_schmitt_nofp),
	.lcd_dat_drive_o     (lcd_dat_drive_nofp),
	.lcd_dat_slew_o      (lcd_dat_slew_nofp),
	.lcd_dc_drive_o   	 (lcd_dc_drive_nofp),
	.lcd_dc_slew_o    	 (lcd_dc_slew_nofp),
	.lcd_bl_drive_o      (lcd_bl_drive_nofp),
	.lcd_bl_slew_o       (lcd_bl_slew_nofp)
);

falsepath_anchor fp_dio_schmitt_u                     (.i (dio_schmitt_nofp      ), .z (dio_schmitt      ));
falsepath_anchor fp_dio_slew_u                        (.i (dio_slew_nofp         ), .z (dio_slew         ));
falsepath_anchor fp_dio_drive_u          [1:0]        (.i (dio_drive_nofp        ), .z (dio_drive        ));
falsepath_anchor fp_sram_dq_schmitt_u                 (.i (sram_dq_schmitt_nofp  ), .z (sram_dq_schmitt  ));
falsepath_anchor fp_sram_dq_slew_u                    (.i (sram_dq_slew_nofp     ), .z (sram_dq_slew     ));
falsepath_anchor fp_sram_dq_drive_u      [1:0]        (.i (sram_dq_drive_nofp    ), .z (sram_dq_drive    ));
falsepath_anchor fp_sram_a_slew_u                     (.i (sram_a_slew_nofp      ), .z (sram_a_slew      ));
falsepath_anchor fp_sram_a_drive_u       [1:0]        (.i (sram_a_drive_nofp     ), .z (sram_a_drive     ));
falsepath_anchor fp_sram_strobe_slew_u                (.i (sram_strobe_slew_nofp ), .z (sram_strobe_slew ));
falsepath_anchor fp_sram_strobe_drive_u  [1:0]        (.i (sram_strobe_drive_nofp), .z (sram_strobe_drive));
falsepath_anchor fp_audio_schmitt_u                   (.i (audio_schmitt_nofp    ), .z (audio_schmitt    ));
falsepath_anchor fp_audio_slew_u                      (.i (audio_slew_nofp       ), .z (audio_slew       ));
falsepath_anchor fp_audio_drive_u        [1:0]        (.i (audio_drive_nofp      ), .z (audio_drive      ));
falsepath_anchor fp_lcd_clk_slew_u                    (.i (lcd_clk_slew_nofp     ), .z (lcd_clk_slew     ));
falsepath_anchor fp_lcd_clk_drive_u      [1:0]        (.i (lcd_clk_drive_nofp    ), .z (lcd_clk_drive    ));
falsepath_anchor fp_lcd_dat_schmitt_u                 (.i (lcd_dat_schmitt_nofp  ), .z (lcd_dat_schmitt  ));
falsepath_anchor fp_lcd_dat_drive_u      [1:0]        (.i (lcd_dat_drive_nofp    ), .z (lcd_dat_drive    ));
falsepath_anchor fp_lcd_dc_slew_u                     (.i (lcd_dc_slew_nofp      ), .z (lcd_dc_slew      ));
falsepath_anchor fp_lcd_dc_drive_u       [1:0]        (.i (lcd_dc_drive_nofp     ), .z (lcd_dc_drive     ));
falsepath_anchor fp_lcd_bl_slew_u                     (.i (lcd_bl_slew_nofp      ), .z (lcd_bl_slew      ));
falsepath_anchor fp_lcd_bl_drive_u       [1:0]        (.i (lcd_bl_drive_nofp     ), .z (lcd_bl_drive     ));
falsepath_anchor fp_gpio_schmitt_u                    (.i (gpio_schmitt_nofp     ), .z (gpio_schmitt     ));
falsepath_anchor fp_gpio_slew_u                       (.i (gpio_slew_nofp        ), .z (gpio_slew        ));
falsepath_anchor fp_gpio_drive_u         [1:0]        (.i (gpio_drive_nofp       ), .z (gpio_drive       ));
falsepath_anchor fp_gpio_pu_u            [N_GPIO-1:0] (.i (gpio_pu_nofp          ), .z (gpio_pu          ));
falsepath_anchor fp_gpio_pd_u            [N_GPIO-1:0] (.i (gpio_pd_nofp          ), .z (gpio_pd          ));

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
