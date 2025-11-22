# TODOs

## RTL

* APU
	* Sample pipeline
	* PWM/PDM output
	* Timers
	* IRQ to/from main CPU
* Debug
	* Write virtual UART peripheral
* PPU
	* Think harder about palette RAM read/write collisions
	* Possible to reduce RAM bandwidth for ABLIT/ATILE? (possibly have timing budget for 1-entry tilenum cache)
* CPU
	* Investigate long reg2reg paths
* GPIOs
	* Finalise list of peripherals
	* IO muxing scheme
	* Software GPIO registers (currently just have PU/PD in padctrl)
* Flash XIP
	* Drop?
* Backlight PWM

## "Verification"

* Bring up hello world on main CPU IRAM
* Bring up bootloader
* Gate sims

## Implementation

* Investigate 9-track cell library
* Finalise SRAM IO constraints
* Report all IO paths and review
* Report all cross-domain paths and review
* Report all false-path constraints inserted by RTL buffers and check their endpoints
* Check macro PDN connections

## Submission

* Run wafer space pre-check
* Check VDD and VSS pad locations are compatible 

# Blog Material and Work Log

The kind folks at [wafer.space](https://https://wafer.space/) offered me a free slot on their first GF180MCU shuttle. This is a full MPW slot with 20 mm^2 die size and customer-defined padring, valued at $7k. The catch is I have two weeks to go from conception to final GDS. Actually it was supposed to be three weeks but I was distracted by the Hazard3 v1.1 release, which was my fault.

Leo from wafer.space suggested a Hazard3, some memory, JTAG and a UART. I think that would be neat but it lacks a certain, as the French say, "I don't know what." This seems like an excellent excuse to resurrect an old project of mine called [RISCBoy](https://github.com/wren6991/riscboy). I summed up that project in its GitHub Readme as follows:

> It is a Gameboy Advance from a parallel universe where RISC-V existed in 2001. A love letter to the handheld consoles from my childhood, and a 3AM drunk text to the technology that powered them.

RISCBoy is a more-or-less finished project, missing two things:

* An audio processor and output sample pipeline.
* A permanent home in the form of a PCB and printed enclosure.

RISCBoy targeted an iCE40 HX8K FPGA. These FPGAs have a small logic fabric with a simple, regular structure: just LUT4s and carry chains like the good old days. They have no DSP tiles and limited internal memory resources, which helps avoid FPGA-isms like "multipliers are free, right?". This makes the RISCBoy RTL a good candidate for porting to the fairly low-density cells and SRAM macros available for the first wafer.space shuttle.

The RISC-V core I designed for RISCBoy ([Hazard5](git@github.com:Wren6991/Hazard5.git))  is the progenitor of Hazard3. It's a bit more aggressively pipelined (four or five stages depending on who's counting), has a somewhat impressionistic interpretation of some parts of the RISC-V privileged ISA, and lacks support for debug and most of the optional ISA extensions supported by Hazard3. There are also some ~~silly~~ pro gamer FPGA frequency hacks like putting the register file BRAM read port on a negedge in the middle of the decode stage. I'm going to replace it with Hazard3.

For my own inscrutable reasons I will refer to the ASIC incarnation of RISCBoy as **RISCBoy Digital**.

## IOs

The RISCBoy PPU assumes it has access to RAM with per-cycle random access, and deterministic low latency.

The amount of on-chip SRAM is limited by the density of the 5V SRAM macros: if we assume 1/3rd of the die is padring, and dedicate half of the remainder to SRAM, then we can fit about 16 kB. An 8bpp 256-tile tileset at 8x8 pixels per tile is already 16 kB, so this is inadequate for PPU VRAM. The only option that meets the constraints is external parallel SRAM (which was the original design for RISCBoy). This is very tight on the available IOs.

The default padring in the template project has 54 IOs. In the example `.yml` it's 40 bidirectional, 12 input-only and 2 analog, but those three pad types are interchangeable: they have the same dimensions and same bond pad location. I want to stay bond-compatible with the default padring so that I can get my chips wire-bonded as chip-on-board.

In short we have 54 pins available for digital I/O. Here is a rough first-pass allocation:

* Parallel async SRAM: 38 IOs
	* 16 DQ
	* 17 A (for 256 kB)
	* OEn, WEn, CSn, UBn, LBn
	* Can sacrifice UBn/LBn if we don't need byte writes (-2 IO)
	* Can sacrifice CSn but this wastes power (-1 IO)
* Clock and reset: 2 IOs
	* Assume we can derive all necessary clocks internally from one root clock
	* Likely just two internal clocks: system and LCD TX
* SPI LCD: 4 IOs
	* DAT, CLK, CSn, DC
	* Would be nice to have a RST output as well (+1 IO) but this can be tied to the chip reset at board level. There is a soft reset command and it usually works
	* In theory CSn can be sacrificed (-1 IO) but makes it impossible to recover from resets of the SPI interface without also performing a hard reset of the display (unless there is some magic sequence)
	* TE would be nice (+1)
	* Backlight PWM would be nice (+1)
* Debug: 2 IOs
	* Use [Two-Wire Debug](https://github.com/Wren6991/TwoWireDebug)
	* Support stock OpenOCD by bridging JTAG to TWD in a software emulation layer inside the probe, like https://github.com/Wren6991/virtual-jtag-dtm
	* This can also be used for debug prints using either Segger RTT or a custom debug serial port added to the TWD DTM, so don't necessarily need a UART. (Can bridge this to the CDC ACM UART on the picoprobe firmware so it just looks like a UART to the user.)
* Buttons: at least 6 IOs.
	* 3x3 matrix: DPAD, ABXY, START
	* Needs diodes; possibly more expensive than just using an I/O expander or shift register
* Audio out: 1 IO
	* Fast PWM/PDM
* Spare: 1 IOs. Nice to haves:
	* SPI flash, for boot (additional chip select on LCD SPI? Not ideal as LCD will have fast SCK)
	* Blinky LED
	* Audio out
	* Additional address bit for 512 kB (256k x 16) SRAM

3x3 matrix might not be the best choice for the buttons. 6 I/Os for 9 buttons is a poor ratio. If we had some generic serial (SPI-ish) bus for peripheral access then we could use a shift register for button input, and then arbitrary numbers of buttons can be supported.

Assume SRAM, debug, LCD, clock + reset are locked in (38 + 4 + 2 + 2 = 46 IOs). That leaves 8 IOs for: buttons, audio out, SPI flash, blinky light, backlight PWM. Assign:

* 2 for stereo audio
	* Second channel can be re-used as status LED or as additional chip select GPIO
* 1 for backlight PWM
* 3 common QSPI signals (SCK, IO0, IO1), shared across peripherals (max of dual-SPI)
* CS0n, for flash
* CS1n, for shift register

## Digital Components

The main components are:

* Hazard3 main processor, CPU0
	* Probably 1-port
	* Turn on as many ISA options as practical (code density is important as memory is limited)
	* Probably RV32I base ISA
	* No memory protection etc; useless in this application
	* Can access all memory and peripherals
* Hazard3 audio processor, CPU1
	* Local RAM, ~2 kB, contains program code and input ring buffer
	* Generates audio samples and pushes them into fixed-function upsampling + dithering pipeline
	* Interrupts main CPU when its input ring buffer is half-empty
	* Can do blending, ADPCM, FM synthesis, etc
	* Can be used for other offload in theory (not a prioritised use case)
	* Probably RV32E base ISA
	* No access to system bus
* RISCBoy PPU
	* Priority to external SRAM
	* No access to any other memory
	* Two internal scanline buffers, 16 bits wide, at least 512 pixels deep (target 320x240 and maybe 480x320) -> 2 kB of RAM
	* Currently these are 1R1W but alpha blending was never implemented; could be reduced to 1RW
* Internal working RAM (IWRAM)
	* 32 bits wide, ~10 kB
	* Accessible only to main CPU
	* For stack and hot code/data
* Flash XIP cache? (~2 kB)
	* Would be nice for running MicroPython etc
	* Tags are flops
* TWD DTM for debug via Hazard3 DM
	* DM can see both CPU0 and CPU1
* Bootrom:
	* Sea of gates, <100 bytes
	* Load flash into IWRAM, checksum, give up if incorrect
* Smol peripherals:
	* Backlight PWM
	* GPIO registers and GPIO IRQs
	* Debug serial port connected to
	* Maybe a UART -- could be muxed onto audio pins?
* Serial IO:
	* Supports dual-SPI flash XIP on one chip select
	* Supports normal SPI on all chip selects
	* Used for accessing input shift register for buttons
* Clock generators
	* Single input clock, programmable division (1 -> 4) for system and LCD clocks.
	* Maybe have programmable ring oscillators available to mux in, if I have time. Use the RP2040 trick of multiple tristate buffers in parallel to create a variable-drive-strength delay stage.

## Work Log

### Day 0: FIFTEEN DAYS REMAIN

It's November 17th (Monday). After working through the weekend I pushed out the Hazard3 release in the small hours of the morning.

After going to work and taking a nap I download the [wafer.space GF180MCU project template](git@github.com:wafer-space/gf180mcu-project-template.git) and follow the instructions in the readme.  I clone the PDK, invoke `nix-shell`, and make some tea. When I come back I have a working ASIC toolchain. One `make` invocation and some time later, I have a GDS with the default padring, a handful of cells and a couple of SRAM macros.

This was my first interaction with nix and I might just be a convert. Commercial ASIC tool flow deployments are usually a complete shitshow.

Most of build the time is spent in the `klayout` DRC (around 3 hours). It has a peak RAM usage of around 20 GB, which it reports in units of kB. I think that's quite charming. This is good to know because I can probably skip DRC for most of my build iterations once I have the basic macro placement nailed down.

### Day 1: FOURTEEN DAYS REMAIN

The goal for today is to get the RTL for a Hazard3 + RAM + debug through the implementation flow, and get a rough idea of achievable timing.

I wrote a simple SRAM wrapper which builds larger RAMs out of the existing block macros. I probably will forgo simulating with the actual RAM models most of the time because they don't support preload, and I don't want to have to slice my firmware up into 16 pieces. I did read the models to check that there weren't any traps; Q is preserved on non-read cycles, good.

I noticed the example RTL has explicit connections for the supply nets on the SRAM macros. I'm not used to that but I don't have a lot of time to mess around with the tool flow and connect supplies in back-end, so I'll just adapt my RTL to suit.

It took quite a bit of iteration but I managed to get a Hazard, 8 kB of SRAM and JTAG debug through to GDS. Timing is pretty poor: slow corner setup is -5 ns WNS at 25 MHz (40 ns period). Will need to work on that. Targeting an LCD clock of 36 MHz which works out to almost exactly 30 Hz at 320 x 240 RGB565. Would love to run the system that fast, but if not, 24 MHz is a value which I could get from a 3/2 division of a 36 MHz input.

I got the Hazard5 version up to 48 MHz on iCE40 but I won't have much time to work on optimisation here.

I started ripping out the pad instances, and adding ones for my interfaces with the correct instance names, correct pull states etc. I'll thank myself for the instance names once I get to timing closure.

Having one weird issue which is the `librelane-magicdrc` flow failing on XOR between klayout and magic GDS. Looks like magic might not be writing out a GDS at all? I asked Leo if this was expected and he said "uhhhhh no" so I need to debug that.

Overall pretty fruitful day -- pushed through a lot of annoying issues with the flow so I can write some actual RTL tomorrow. I also really need to get some simulations running soon; up til now I've been going vibes-based on the amount of cells present and the critical paths being where I expect. It's a bit shit that the built-in cocotb flow has its own redundant copy of the file list hardcoded in a python file, so that will be early on the list of things to fit.

The last thing I did today was to swap the Hazard3 stock JTAG-DTM for my Two-Wire Debug (TWD DTM). I plan to use this for both processor debug and virtual UART support (with some hacked picoprobe firmware advertising JTAG and UART and then tunneling the traffic through TWD) so I'll be able to have a pretty civilised debug experience with just two wires and the stock upstream openocd. This is the plan anyway.

### Day 2: THIRTEEN DAYS REMAIN

I stayed up a *bit* too late last night. ASIC design is like crack in the sense that it's quite more-ish.

First order of the day is to fix my padring config to match the new pad instances I added yesterday, so I can get some layouts running again. It's not clear exactly how the YAML file order corresponds to padring order so I just take a guess. The intention is for the parallel SRAM to connect broadside with the NORTH, EAST and most of the SOUTH pads. This feels a lot like doing pinswaps on an FPGA to make everything route out cleanly.

The WEST pads are used for all the other interfaces: audio, reset, clock, LCD, and everything left is labelled as "GPIO" and I'll figure out how to use them later. 6 GPIOs is enough for dual SPI with three chip selects. So 1 chip select for flash, one for wrangling the input shift register for the buttons, and one spare (possibly a blinky LED).

I tried to keep the AUDIO_L and AUDIO_R pads somewhere quiet. They're next to some supply pads in the corner of the chip, with the next IO pad being the reset (which one hopes does not toggle at runtime). With the IO and core supplies shorted together it's still going to be noisy but I'd like to think this is a small improvement, and I can continue thinking that as I'll never measure it.

One problem I had was the klayout vs magic DRC xor crashing out because magic was failing to write anything. Turns out it was just a low file handle limit (1024 by default on my Ubuntu machine) and I could raise it with:

```
ulimit -Sn 4096
```

Leo on GitHub was very helpful with debugging this. I initially assumed it was an issue with the flow or with the tech library setup.

I wrote some basic simulations for what I have so far:

* Reading IDCODE from TWD-DTM
* Connecting to the RISC-V core through the DM and reading some identification CSRs
* Reading/writing SRAM using Program Buffer execution on the RISC-V core

I'm not analysing the coverage but this touches every major block at least once, and gives me confidence nothing is being optimised away as I iterate on synthesis and layout.

### Day 3: TWELVE DAYS REMAIN

Today I want to get some of the bigger blocks loosely integrated into the design:

* Audio processor and its RAM (maybe a simple PWM hooked up to the audio pads)
* RISCBoy PPU
* RISCBoy LCD interface
* RISCBoy external SRAM interface and PHY

First up is audio processor; the testbench support for debug that I wrote yesterday already supports selecting multiple cores, so it's pretty easy to extend the tests.

The main CPU can access the audio processor's local SRAM. For this I'm going to (ab)use the SBA feature on Hazard3. This is intended for arbitrating System Bus Access from the debug module directly into the core's bus manager port, but you can use it for other things too. The AHB-to-SBUS adapter also serves as a pipestage between the main CPU and audio CPU's bus, registering all paths at a cost of two wait states (so 3 cycles for a 32-bit write to audio RAM).

One issue I had was missing PDN connections on the SRAMS (just VDD I think) after adding the APU RAMs. I defined separate macro PDNs for CPU IRAM and APU RAM, and the issue went away. Still slightly mysterious.

### Day 4: ELEVEN DAYS REMAIN

I spent some time looking at timing reports last night. I've recently had some insane (> 100 ns) violations on reset paths. This lead to me asking this question on discord:

> Does anyone know which step in the (template) flow is responsible for adding buffers on a high fanout net? I have a reset net with a fanout of ~1k and in my powered netlist `./25-openroad-globalplacementskipio/chip_top.pnl.v` still has the reset synchroniser output going directly to all ~1k loads without buffering. This makes the following STAs meaningless because the reset net has like a 100 ns rise time

Digging in a bit further I found that my CTS run was taking one millisecond and had not produced a COMMANDS file to actually invoke any tools.

It turns out it is not sufficient to just create a clock in your SDCs. You need the magic YAML flags, or CTS does not run. This results in a completely unbuffered clock with hundreds of nanoseconds of slew (very low clock skew though) and the setup times for the flops are derated according to slew, resulting in absurd levels of timing violation.

After spending some time fiddling with this I chucked in the RISCBoy PPU. I had to replace the 1R1W memories with single-ported ones. I made the following substitutions:

* Scanline buffers (512 x 16, 2 instances): these are only ever written by the blitter or read by the scanout hardware, because I never got round to blending modes other than 1-bit alpha. Since blitting and scanning out are mutually exclusive, these map easily to single-ported RAMs with a mux on the address.

* Palette RAM (256 x 16, 1 instance): again this is mapped to a single-ported RAM (specifically a pair of the foundry 256 x 8 macros). Unfortunately it is possible to write to the palette RAM in the middle of a paletted span, and in this case I choose to drop the write and perform the read. It's not the end of the world because common per-scanline tricks like sky background gradients are covered by just using a per-scanline FILL command with a call to the shared sprite subroutine.

* Command processor call stack (8 x 18ish): this will just be a synthesisable register file. Specifically I'll synthesise the same behaviour RTL that was used for BRAM inference on iCE40.

I could work around this by adding an explicit write buffer for the palette to hold the write until it's ready (like an interrupter gear for a fighter plane with a propeller) or by adding a PPU command to write to its own APB registers. The second one sounds potentially funnier although all the useful knobs are exposed directly (and only) to the command processor anyway.

### Day 5: TEN DAYS REMAIN

Today is software day. I have some useful components in the system now, so it would be nice to exercise them a bit and confirm they still work as expected.

Actually first let's put in some time making the software environment a bit nicer and more compliant. Currently only the main CPU has access to the (extravagant) 64-bit RISC-V timer; I don't plan to change this. However I do want to add some nice custom looping timers in the APU for timing your bleeps and bloops accurately, and I need some interrupts going back and forth between the processors, etc.

So let's push one _more_ stack frame and add AHB-Lite support to my register block generator so I can have single-cycle access to those registers from the APU. Today is software day, remember?

