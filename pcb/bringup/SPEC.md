# Bringup Board

Purpose:

* Initial smoke test.
* Design validation:
	* Exercise all hardware interfaces at a basic level.
	* Sweep voltages and get coarse V/F sweeps etc.
* Early software development.

Non-purposes:

* Device test (ATE).
* Games console.

## Requirements

* 4-layer (2 would be adequate but 4 gives peace of mind).
	* Signals on outer layers for easy rework.
* Socket to support standard COB-to-socket wafer.space PCBs.
* All DUT signals accessible on test points or headers (headers preferred; test points minimise stubs for high-speed signals, mainly SRAM).
* Power and debug through single USB C socket.
* Allow running chip at: 5V (VBUS), 3.3V (onboard LDO), external supply, selected by jumper.
	* External supply for: smoke test soft-start, voltage sweep, and current measurement. 0.1" header is fine for power supply connection.
	* External supply range: 3.0V to 5.5V (3.3 -10%, 5 +10%). Interested in validating 3V3 operation.
* Built-in debug probe:
	* RP2350 running modified picoprobe firmware.
	* (RP2040 is obviously sufficient but using Hazard3 to debug the second Hazard3 tapeout was evaluated on its technical merits and found to be hella balls to the walls fucking awesome.)
	* Probe enumerates as CMSIS-DAP with JTAG, plus a CDC UART.
	* Probe tunnels all traffic through the TWD DAP to internal DMI and VUARTs.
* DUT clock driven by debug probe (derived from probe's XOSC via internal PLL, just driven as single-ended CMOS clock via level shifter).
* DUT reset also driven by debug probe.
* Level shifters between debug probe and all DUT connections.
* All level shifter outputs that connect to DUT pads must be tristatable (controlled by debug probe), and the default state at power-up must be tristate.
* Onboard async parallel SRAM runs at DUT supply voltage (check: footprints are standard, so 5V and 3V3 devices should be available).
* SPI flash for DUT.
	* 5V serial NOR flash with decent speed or density is nonexistent.
	* Therefore use level shifters (SPI stream peripheral is max 12 MHz, clk_sys/2, and can be slower)
	* Use same device as the RP2350's boot flash.
* LCD connects to a ZIF connector (pick a specific one from BuyDisplay etc) through level shifters; LCD outputs are all 3V3.
	* Level shifter needs to support 24 MHz operation with reasonable edge rates.
* LCD lies flat on top surface of the board.
	* Trading board size/cost for not having flying wires. Onboard LCD can be a small one.
* ***Rounded corners*** (I cannot stress this enough), oh and mounting holes I guess.
* Audio PWM demodulator: just digital buffer (or spare level shifter) -> RC + C, with 3.5 mm socket.
* No direct access from probe to DUT SPI flash (TWD debug is fine for flash programming).
* Spare probe GPIOs brought out to pin headers (can be wired to DUT signals if DUT is at 3.3V)
* 8 push buttons connected to LCD D7..D0 with ~1k resistors (sample during vblank)
	* Make the board reasonably comfortable to pick up, hold, push buttons with two thumbs.

## Part Selection

Trying to stick to JLC basic or preferred parts where possible.

* [ER-TFT020-7 LCD](https://www.buydisplay.com/download/manual/ER-TFT020-7_Datasheet.pdf)
* [SN74LVC8T245 level shifter](https://www.ti.com/lit/ds/symlink/sn74lvc8t245.pdf)
* [HC-PBB40C-70DS-0.4V-2.0-02 CoB Socket](https://www.lcsc.com/product-detail/C19089262.html)
* [R1RP0416DI async SRAM](https://www.renesas.com/en/document/dst/r1rp0416di-series-datasheet)
* [NCP115ASN330 3V3 LDO](https://www.lcsc.com/product-detail/C603505.html)
* [GT-USB-7010B](https://www.lcsc.com/product-detail/USB-Connectors_G-Switch-GT-USB-7010B_C2837092.html)
* [SHOU HAN PJ-320D 3.5mm socket](https://www.lcsc.com/product-detail/C431535.html)
* [W25Q128JVSIQ NOR flash](https://jlcpcb.com/partdetail/WinbondElec-W25Q128JVSIQ/C97521)
* [X322512MSB4SI 12 MHz crystal](https://jlcpcb.com/partdetail/YXC_CrystalOscillators-X322512MSB4SI/C9002)

## Level Shifters

### To DUT

From probe:

* Debug: DCK + DO (2)
* CLK (1)
* RSTn (1)

From SPI flash:

* MISO (1)

Total: 5. Use spare level shifters to buffer some probe signals to the VDUT domain and bring them out on a header for patching in.

### From DUT

To probe:

* Debug: DI (1)

To LCD:

* BL, DC, CLK (3)
* DAT0 to DAT7 (8)

To SPI flash:

* SCK, CSn, MOSI (3)

To audio filter:

* AUDIO (1)

Total: 16

## Other Useful Links

* [wafer.space CoB documentation](https://github.com/wafer-space/chip-on-board-wire-bonded-pcbs)
