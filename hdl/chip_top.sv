/*****************************************************************************\
|                        Copyright (C) 2025 Luke Wren                         |
|                     SPDX-License-Identifier: Apache-2.0                     |
\*****************************************************************************/

`default_nettype none

// useless:
/* verilator lint_off PINCONNECTEMPTY */

module chip_top #(
    parameter N_DVDD    = 8,
    parameter N_DVSS    = 10,
    parameter N_SRAM_DQ = 16,
    parameter N_SRAM_A  = 17,
    parameter N_GPIO    = 4
) (
    // Power supply pads
    inout  wire                 VDD,
    inout  wire                 VSS,

    // Root clock and global reset
    inout  wire                 CLK,
    inout  wire                 RSTn,

    // Debug (clock/data)
    inout  wire                 DCK,
    inout  wire                 DIO,

    // Parallel async SRAM
    inout  wire [N_SRAM_DQ-1:0] SRAM_DQ,
    inout  wire [N_SRAM_A-1:0]  SRAM_A,
    inout  wire                 SRAM_OEn,
    inout  wire                 SRAM_CSn,
    inout  wire                 SRAM_WEn,

    // Audio PWM, or software GPIO
    inout  wire                 AUDIO,

    // LCD data bus and backlight PWM.
    // LCD_DAT[7:6] are available as GPIO if LCD is serial.
    inout  wire                 LCD_CLK,
    inout  wire [7:0]           LCD_DAT,
    inout  wire                 LCD_DC,
    inout  wire                 LCD_BL,

    // Software GPIO or boot flash
    inout  wire [N_GPIO-1:0]    GPIO
);
// ----------------------------------------------------------------------------
// IO signals connected to core

// Global signal from core to enable outputs on output-only pins after reset
// is released and system clock starts. Ensure we don't drive all the pads at
// reset (in bird culture this is considered a dick move).
wire                 enable_fixed_outputs;

// Root clock/reset
wire                 padin_clk;
wire                 padin_rst_n;

// Debug
wire                 padin_dck;
wire                 padin_dio;
wire                 padoe_dio;
wire                 padout_dio;

// SRAM signals
wire [N_SRAM_DQ-1:0] padin_sram_dq;
wire [N_SRAM_DQ-1:0] padoe_sram_dq;
wire [N_SRAM_DQ-1:0] padout_sram_dq;
wire [N_SRAM_A-1:0]  padout_sram_a;
wire                 padout_sram_oe_n;
wire                 padout_sram_cs_n;
wire                 padout_sram_we_n;
wire                 padout_sram_ub_n;
wire                 padout_sram_lb_n;

// Audio PWM signals (bidirectional as they have GPIO alternates):
wire                 padout_audio;
wire                 padoe_audio;
wire                 padin_audio;

// LCD signals
wire                 padout_lcd_clk;
wire [7:0]           padout_lcd_dat;
wire [7:0]           padoe_lcd_dat;
wire [7:0]           padin_lcd_dat;
wire                 padout_lcd_dc;
wire                 padout_lcd_bl;

// GPIO signals (bidirectional)
wire [N_GPIO-1:0]    padin_gpio;
wire [N_GPIO-1:0]    padoe_gpio;
wire [N_GPIO-1:0]    padout_gpio;

// Auxiliary pad controls
// Output-only pads lack Schmitt control.
wire                 dio_schmitt;
wire                 dio_slew;
wire [1:0]           dio_drive;

wire                 sram_dq_schmitt;
wire                 sram_dq_slew;
wire [1:0]           sram_dq_drive;

wire                 sram_a_slew;
wire [1:0]           sram_a_drive;

wire                 sram_strobe_slew;
wire [1:0]           sram_strobe_drive;

wire                 audio_schmitt;
wire                 audio_slew;
wire [1:0]           audio_drive;

wire                 lcd_clk_slew;
wire [1:0]           lcd_clk_drive;

wire                 lcd_dat_schmitt;
wire                 lcd_dat_slew;
wire [1:0]           lcd_dat_drive;

wire                 lcd_dc_slew;
wire [1:0]           lcd_dc_drive;

wire                 lcd_bl_slew;
wire [1:0]           lcd_bl_drive;

wire                 gpio_schmitt;
wire                 gpio_slew;
wire [1:0]           gpio_drive;

wire [N_GPIO-1:0]    gpio_pu;
wire [N_GPIO-1:0]    gpio_pd;
wire [7:0]           lcd_dat_pu;
wire [7:0]           lcd_dat_pd;
wire                 audio_pu;
wire                 audio_pd;

// ----------------------------------------------------------------------------
// IO pad instances: clock, reset, debug

// All input-only pads are Schmitt trigger type.

// Clock: no pull. Should be connected to an always-on output on the PCB.
gf180mcu_fd_io__in_s pad_CLK (
    .DVDD   (VDD),
    .DVSS   (VSS),
    .VDD    (VDD),
    .VSS    (VSS),

    .Y      (padin_clk),
    .PAD    (CLK),

    .PU     (1'b0),
    .PD     (1'b0)
);

// Reset: pull HIGH
gf180mcu_fd_io__in_s pad_RSTn (
    .DVDD   (VDD),
    .DVSS   (VSS),
    .VDD    (VDD),
    .VSS    (VSS),

    .Y      (padin_rst_n),
    .PAD    (RSTn),

    .PU     (1'b1),
    .PD     (1'b0)
);

// DCK: pull LOW (mandated by TWD spec)
gf180mcu_fd_io__in_s pad_DCK (
    .DVDD   (VDD),
    .DVSS   (VSS),
    .VDD    (VDD),
    .VSS    (VSS),

    .Y      (padin_dck),
    .PAD    (DCK),

    .PU     (1'b0),
    .PD     (1'b1)
);

gf180mcu_fd_io__bi_t pad_DIO (
    .DVDD   (VDD),
    .DVSS   (VSS),
    .VDD    (VDD),
    .VSS    (VSS),

    .A      (padout_dio),
    .OE     (padoe_dio),
    .Y      (padin_dio),
    .PAD    (DIO),

    .CS     (dio_schmitt),
    .PDRV1  (dio_drive[1]),
    .PDRV0  (dio_drive[0]),
    .SL     (dio_slew),
    .IE     (!padoe_dio),

    .PU     (1'b0),
    .PD     (1'b1)
);


// ----------------------------------------------------------------------------
// IO pad instances: SRAM

// False-path on loopback, timing isn't important as pulls have low edge rates
wire [N_SRAM_DQ-1:0] padin_sram_dq_fp;
falsepath_anchor fp_padin_u [N_SRAM_DQ-1:0] (
    .i (padin_sram_dq),
    .z (padin_sram_dq_fp)
);

generate
for (genvar i = 0; i < N_SRAM_DQ; i++) begin: pad_SRAM_DQ
    (* keep *)
    gf180mcu_fd_io__bi_t u (
        .DVDD   (VDD),
        .DVSS   (VSS),
        .VDD    (VDD),
        .VSS    (VSS),

        .A      (padout_sram_dq[i]),
        .OE     (padoe_sram_dq[i]),
        .Y      (padin_sram_dq[i]),
        .PAD    (SRAM_DQ[i]),

        .CS     (sram_dq_schmitt),
        .SL     (sram_dq_slew),
        .PDRV1  (sram_dq_drive[1]),
        .PDRV0  (sram_dq_drive[0]),
        .IE     (!padoe_sram_dq[i]),

        // Loop back input for bus keeper function (pull down at reset):
        .PU     (padin_sram_dq_fp[i] && enable_fixed_outputs),
        .PD     (!padin_sram_dq_fp[i] || !enable_fixed_outputs)
    );
end
endgenerate

// Address: pull LOW at reset
generate
for (genvar i = 0; i < N_SRAM_A; i++) begin: pad_SRAM_A
    (* keep *)
    gf180mcu_fd_io__bi_t u (
        .DVDD   (VDD),
        .DVSS   (VSS),
        .VDD    (VDD),
        .VSS    (VSS),

        .A      (padout_sram_a[i]),
        .OE     (enable_fixed_outputs),
        .Y      (/* unused */),
        .PAD    (SRAM_A[i]),

        .CS     (1'b0),
        .SL     (sram_a_slew),
        .PDRV1  (sram_a_drive[1]),
        .PDRV0  (sram_a_drive[0]),
        .IE     (1'b0),

        .PU     (1'b0),
        .PD     (!enable_fixed_outputs)
    );
end
endgenerate

// Strobes: pull HIGH at reset
gf180mcu_fd_io__bi_t pad_SRAM_CSn (
    .DVDD   (VDD),
    .DVSS   (VSS),
    .VDD    (VDD),
    .VSS    (VSS),

    .A      (padout_sram_cs_n),
    .OE     (enable_fixed_outputs),
    .Y      (/* unused */),
    .PAD    (SRAM_CSn),

    .CS     (1'b0),
    .SL     (sram_strobe_slew),
    .PDRV1  (sram_strobe_drive[1]),
    .PDRV0  (sram_strobe_drive[0]),
    .IE     (1'b0),

    .PU     (!enable_fixed_outputs),
    .PD     (1'b0)
);

gf180mcu_fd_io__bi_t pad_SRAM_WEn (
    .DVDD   (VDD),
    .DVSS   (VSS),
    .VDD    (VDD),
    .VSS    (VSS),

    .A      (padout_sram_we_n),
    .OE     (enable_fixed_outputs),
    .Y      (/* unused */),
    .PAD    (SRAM_WEn),

    .CS     (1'b0),
    .SL     (sram_strobe_slew),
    .PDRV1  (sram_strobe_drive[1]),
    .PDRV0  (sram_strobe_drive[0]),
    .IE     (1'b0),

    .PU     (!enable_fixed_outputs),
    .PD     (1'b0)
);

gf180mcu_fd_io__bi_t pad_SRAM_OEn (
    .DVDD   (VDD),
    .DVSS   (VSS),
    .VDD    (VDD),
    .VSS    (VSS),

    .A      (padout_sram_oe_n),
    .OE     (enable_fixed_outputs),
    .Y      (/* unused */),
    .PAD    (SRAM_OEn),

    .CS     (1'b0),
    .SL     (sram_strobe_slew),
    .PDRV1  (sram_strobe_drive[1]),
    .PDRV0  (sram_strobe_drive[0]),
    .IE     (1'b0),

    .PU     (!enable_fixed_outputs),
    .PD     (1'b0)
);

// ----------------------------------------------------------------------------
// IO pad instances: Audio (also available for GPIO use)

gf180mcu_fd_io__bi_t pad_AUDIO (
    .DVDD   (VDD),
    .DVSS   (VSS),
    .VDD    (VDD),
    .VSS    (VSS),

    .A      (padout_audio),
    .OE     (padoe_audio),
    .Y      (padin_audio),
    .PAD    (AUDIO),

    .CS     (audio_schmitt),
    .SL     (audio_slew),
    .PDRV1  (audio_drive[1]),
    .PDRV0  (audio_drive[0]),
    .IE     (!padoe_audio),

    .PU     (audio_pu),
    .PD     (audio_pd)
);

// ----------------------------------------------------------------------------
// IO pad instances: LCD

// Clock: pulled LOW at reset
gf180mcu_fd_io__bi_t pad_LCD_CLK (
    .DVDD   (VDD),
    .DVSS   (VSS),
    .VDD    (VDD),
    .VSS    (VSS),

    .A      (padout_lcd_clk),
    .OE     (enable_fixed_outputs),
    .Y      (/* unused */),
    .PAD    (LCD_CLK),

    .CS     (1'b0),
    .SL     (lcd_clk_slew),
    .PDRV1  (lcd_clk_drive[1]),
    .PDRV0  (lcd_clk_drive[0]),
    .IE     (1'b0),

    .PU     (1'b0),
    .PD     (!enable_fixed_outputs)
);

generate
for (genvar i = 0; i < 8; i++) begin: pad_LCD_DAT
    gf180mcu_fd_io__bi_t u (
        .DVDD   (VDD),
        .DVSS   (VSS),
        .VDD    (VDD),
        .VSS    (VSS),

        .A      (padout_lcd_dat[i]),
        .OE     (padoe_lcd_dat[i]),
        .Y      (padin_lcd_dat[i]),
        .PAD    (LCD_DAT[i]),

        .CS     (lcd_dat_schmitt),
        .SL     (lcd_dat_slew),
        .PDRV1  (lcd_dat_drive[1]),
        .PDRV0  (lcd_dat_drive[0]),
        .IE     (!padoe_lcd_dat[i]),

        .PU     (lcd_dat_pu[i]),
        .PD     (lcd_dat_pd[i])
    );
end
endgenerate

// DC: pulled LOW at reset
gf180mcu_fd_io__bi_t pad_LCD_DC (
    .DVDD   (VDD),
    .DVSS   (VSS),
    .VDD    (VDD),
    .VSS    (VSS),

    .A      (padout_lcd_dc),
    .OE     (enable_fixed_outputs),
    .Y      (/* unused */),
    .PAD    (LCD_DC),

    .CS     (1'b0),
    .SL     (lcd_dc_slew),
    .PDRV1  (lcd_dc_drive[1]),
    .PDRV0  (lcd_dc_drive[0]),
    .IE     (1'b0),

    .PU     (1'b0),
    .PD     (!enable_fixed_outputs)
);

// BL: pulled LOW at reset
gf180mcu_fd_io__bi_t pad_LCD_BL (
    .DVDD   (VDD),
    .DVSS   (VSS),
    .VDD    (VDD),
    .VSS    (VSS),

    .A      (padout_lcd_bl),
    .OE     (enable_fixed_outputs),
    .Y      (/* unused */),
    .PAD    (LCD_BL),

    .CS     (1'b0),
    .SL     (lcd_bl_slew),
    .PDRV1  (lcd_bl_drive[1]),
    .PDRV0  (lcd_bl_drive[0]),
    .IE     (1'b0),

    .PU     (1'b0),
    .PD     (!enable_fixed_outputs)
);

// ----------------------------------------------------------------------------
// IO pad instances: GPIO

generate
for (genvar i = 0; i < N_GPIO; i++) begin: pad_GPIO
    (* keep *)
    gf180mcu_fd_io__bi_t u (
        .DVDD   (VDD),
        .DVSS   (VSS),
        .VDD    (VDD),
        .VSS    (VSS),

        .A      (padout_gpio[i]),
        .OE     (padoe_gpio[i]),
        .Y      (padin_gpio[i]),
        .PAD    (GPIO[i]),

        .CS     (gpio_schmitt),
        .SL     (gpio_slew),
        .PDRV1  (gpio_drive[1]),
        .PDRV0  (gpio_drive[0]),
        .IE     (!padoe_gpio[i]),

        .PU     (gpio_pu[i]),
        .PD     (gpio_pd[i])
    );
end
endgenerate

// ----------------------------------------------------------------------------
// Power/ground pad instances

generate
for (genvar i = 0; i < N_DVDD; i++) begin: dvdd_pads
    (* keep *)
    gf180mcu_ws_io__dvdd pad (
        `ifdef USE_POWER_PINS
        .DVDD   (VDD),
        .DVSS   (VSS),
        .VSS    (VSS)
        `endif
    );
end

for (genvar i = 0; i < N_DVSS; i++) begin: dvss_pads
    (* keep *)
    gf180mcu_ws_io__dvss pad (
        `ifdef USE_POWER_PINS
        .DVDD   (VDD),
        .DVSS   (VSS),
        .VDD    (VDD)
        `endif
    );
end
endgenerate

// ----------------------------------------------------------------------------
// Core design

chip_core #(
    .N_SRAM_DQ (N_SRAM_DQ),
    .N_SRAM_A  (N_SRAM_A),
    .N_GPIO    (N_GPIO)
) i_chip_core (
    .VDD                   (VDD),
    .VSS                   (VSS),
    .enable_fixed_outputs  (enable_fixed_outputs),
    .padin_clk             (padin_clk),
    .padin_rst_n           (padin_rst_n),
    .padin_dck             (padin_dck),
    .padin_dio             (padin_dio),
    .padoe_dio             (padoe_dio),
    .padout_dio            (padout_dio),
    .padin_sram_dq         (padin_sram_dq),
    .padoe_sram_dq         (padoe_sram_dq),
    .padout_sram_dq        (padout_sram_dq),
    .padout_sram_a         (padout_sram_a),
    .padout_sram_oe_n      (padout_sram_oe_n),
    .padout_sram_cs_n      (padout_sram_cs_n),
    .padout_sram_we_n      (padout_sram_we_n),
    .padout_sram_ub_n      (padout_sram_ub_n),
    .padout_sram_lb_n      (padout_sram_lb_n),
    .padout_audio          (padout_audio),
    .padoe_audio           (padoe_audio),
    .padin_audio           (padin_audio),
    .padout_lcd_clk        (padout_lcd_clk),
    .padout_lcd_dat        (padout_lcd_dat),
    .padoe_lcd_dat         (padoe_lcd_dat),
    .padin_lcd_dat         (padin_lcd_dat),
    .padout_lcd_dc         (padout_lcd_dc),
    .padout_lcd_bl         (padout_lcd_bl),
    .padin_gpio            (padin_gpio),
    .padoe_gpio            (padoe_gpio),
    .padout_gpio           (padout_gpio),
    .dio_schmitt           (dio_schmitt),
    .dio_slew              (dio_slew),
    .dio_drive             (dio_drive),
    .sram_dq_schmitt       (sram_dq_schmitt),
    .sram_dq_slew          (sram_dq_slew),
    .sram_dq_drive         (sram_dq_drive),
    .sram_a_slew           (sram_a_slew),
    .sram_a_drive          (sram_a_drive),
    .sram_strobe_slew      (sram_strobe_slew),
    .sram_strobe_drive     (sram_strobe_drive),
    .audio_schmitt         (audio_schmitt),
    .audio_slew            (audio_slew),
    .audio_drive           (audio_drive),
    .lcd_clk_slew          (lcd_clk_slew),
    .lcd_clk_drive         (lcd_clk_drive),
    .lcd_dat_schmitt       (lcd_dat_schmitt),
    .lcd_dat_slew          (lcd_dat_slew),
    .lcd_dat_drive         (lcd_dat_drive),
    .lcd_dc_slew           (lcd_dc_slew),
    .lcd_dc_drive          (lcd_dc_drive),
    .lcd_bl_slew           (lcd_bl_slew),
    .lcd_bl_drive          (lcd_bl_drive),
    .gpio_schmitt          (gpio_schmitt),
    .gpio_slew             (gpio_slew),
    .gpio_drive            (gpio_drive),
    .lcd_dat_pu            (lcd_dat_pu),
    .lcd_dat_pd            (lcd_dat_pd),
    .gpio_pu               (gpio_pu),
    .gpio_pd               (gpio_pd),
    .audio_pu              (audio_pu),
    .audio_pd              (audio_pd)
);

// ----------------------------------------------------------------------------
// Trinkets
// Chip ID - do not remove, necessary for tapeout
(* keep *)
gf180mcu_ws_ip__id chip_id ();

// wafer.space logo - can be removed
(* keep *)
gf180mcu_ws_ip__logo wafer_space_logo ();

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
