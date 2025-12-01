# TODOs

## RTL

* RISCBoy display controller:
	* Support 8 bits per clock (for use with 8080 instead of SPI)
	* Support VGA output
* Review resettable flops and see if they can be made non-reset for better density/routing

## "Verification"

* Gate sims
* Cover all address decode targets
	* CPU
	* APU
	* PPU
* Toggle every IRQ
* Dump 4-bit 1.5 MSa/s stream from AOUT, filter it back down to 48 kHz, make sure it sounds good
* Render a video frame on the PPU
* Review all verilator lints

## Implementation

* Finalise SRAM IO constraints
* Report all IO paths and review
* Report all cross-domain paths and review
* Report all false-path constraints inserted by RTL buffers and check their endpoints
* QoR:
	* Write mapping for DFFE -> SDFF
	* Write extraction for mux + flop -> SDFF
	* Look at SYNTH_ABC_BUFFERING

## Submission

* Run wafer space pre-check
* Check VDD and VSS pad locations are compatible

## Post-tapeout

* File on OpenROAD:
	* DRT crash on MacOS on some designs
* File somewhere:
	* KLayout vs Magic DRC XOR on MacOS
* File on Yosys:
	* Correctly attribute flops to their Q nets (could also be done in librelane)
* File on GF180MCU repo:
	* Fix RAM simulation model to correctly initialise its internal variables and not need an extra edge on CSn before the first access
	* Fix RAM simulation model to capture inputs directly on the clock so it is usable for RTL sims


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

The clock tree synthesis seems quite temperamental. I tried moving the main CPU's bus fabric and IRAM onto the gated processor clock, and this caused a 7 ns degradation in setup WNS. Also the clock tree viewer in OpenRoad doesn't show any clock tree branches after the clock gate, although inspecting the netlist shows buffers have been inserted. I think what might be happening is the tool is inserting buffers to respect max fanout/capacitance constraints but making no attempt to actually balance the clock tree across the gates; this would be disappointing as an ICG is just a buffer from a CTS point of view. It's also possible I'm just making the clock tree routing much harder by routing the gated clock out to the SRAMs as well as the ungated clock out to the SRAM IO flops, but surely it's not **7 ns** harder?

I looked through the Triton CTS documentation and it had a flag for balancing cells across clock gates, which defaults to `false`. Maybe that is worth revisiting.

### Day 5: TEN DAYS REMAIN

Today is software day. I have some useful components in the system now, so it would be nice to exercise them a bit and confirm they still work as expected.

Actually first let's put in some time making the software environment a bit nicer and more compliant. Currently only the main CPU has access to the (extravagant) 64-bit RISC-V timer; I don't plan to change this. However I do want to add some nice custom looping timers in the APU for timing your bleeps and bloops accurately, and I need some interrupts going back and forth between the processors, etc.

So let's push one _more_ stack frame and add AHB-Lite support to my register block generator so I can have single-cycle access to those registers from the APU. Today is software day, remember?

When testing the AHB regblock support and the new IPC registers for soft IRQs, I got frustrated with how slow debugger-based tests were. I don't want to make the test code any more complicated so instead I expanded the TWD spec to include a short-form status response to make polling more efficient for hosts that just want to implement polled IO. This took a full test run from 34.1 s to 24.3 s.

...ok so software didn't happen today. I spent a while fighting CTS again, and eventually gave up as there's no obvious way to stop it from inferring a clock root at a clock gate output. For those not in the know a "clock root" essentially means "do not look above this point in the clock tree when balancing below this point" and this is an _absurdly dangerous_ thing for a tool to infer. They should always be specified manually. I was seeing multi-ns hold violations on SRAM addresses _after_ hold buffer insertion.

I did enable clock gate inferencing via `USE_LIGHTER`. This also makes the clock tree less balanced but since the inferred flop groups are small, the amount of skew is limited and can be fixed later with buffer insertion and resizing on the datapath. This is not ideal; CTS issues should be fixed during CTS. Still the QoR is ok and I'm less likely to burn a hole in the die. It's actually a little better on setup (compared to no clock gates) because the inferred clock gates make up for the lack of DFFEs in the cell library.

I also moved to the 9-track cell library, which helps out with fmax a bit. Not much to say here: the cells are a bit bigger but a bit faster.

I implemented the virtual UART for printing to debug. This is really just a pair of async FIFOs which are accessed on one side by the TWD-DTM (in the DCK domain) and on the other side by the main CPU. You can get IRQs on RX fullness or TX emptiness, just like a UART. There's also a status flag for whether the host is currently connected, so you can skip through debug prints when nobody is at the other end of the FIFO.

### Day 6: NINE DAYS REMAIN

Finally I wrote a hello world C binary which runs from IRAM.

```c
#include "vuart.h"

void main() {
	vuart_puts("Hello, world!\n");
}
```

I have the testbench polling for characters, like the probe will poll on the real hardware.

My tests are taking an annoyingly long time to run again, so let's do the other TWD optimisation feature I was thinking of (triggering a bus read with an address write). I re-orderd all the TWD command opcodes, which was a bit fiddly because I force all read opcodes to have a parity bit of 0 to park the bus before turnaround. This takes me from 44.77 to 37.19 seconds for a test run -- a bit less than I hoped but I'll take it.

I also wrote some simple code to copy from IRAM to APU RAM, and start the APU core. Until this point I didn't have a register to hold APU execution until it was launched, so I added that too.

I spent the rest of the day building the APU audio output pipeline. This runs from a 24 MHz clock and has three stages:

* Upsample from stereo 16-bit 48 kSa/s to stereo 16-bit 8 x 48 kSa/s (384 kSa/s) with a 33-tap FIR lowpass
	* Quantised to 7-bit coefficients, scaled to not overflow but use full integer range
	* Filter cutoff set to 22 kHz
	* 33 taps puts the filter window edges roughly on the second zero crossing on each side of the sinc pulse
* Sigma-delta up to 4-bit 1.5 MSa/s
* Output 4-bit PWM with a 1.5 MHz carrier

This is probably terribly suboptimal but I could bang it together in a few hours including designing the filter, and it should be well-behaved wrt overflow and whatnot. I'm aware of CIC but to be honest the fact the integrator stages can just overflow without issue has always been slightly mysterious to me, especially once the stuffing/dropping is involved. I'm worried there will be an edge case I missed, and I don't have much time to verify this, so good ol' reliable FIR it is.

I want to look into higher-order sigma-delta in future to push more of the quantisation noise up out of the audio band but a first-order is basically one line of RTL so the engineering choice is clear here.

I wrote some software to start up the audio output pipeline and generate ramps to/from midrail (which is necessary to avoid popping on startup, and will be done entirely in software).

I was going to design some fancy timers for the APU but right now I'm attracted to the idea that samples are time, and APU software just counts samples to get things at the right point in time. The sample train must never stop after all. I'll probably add some simple repeating timers but scale back my ideas for things like a timer that executes delay sequences from a FIFO.

### Day 7: EIGHT DAYS REMAIN

I spent a bit of time today looking at why my SRAMs are carving a big hole in my vertical power routing. It turns out the straps Leo added down the east and west side of the RAMs to connect those edge pins cause pdngen to emit _no other metal 4 routing_ within the macro's halo. There's no easy solution to that one (it requires a redesign of the macro's power connections to hook up with M4 PDN strapping over M3 bars, and possibly an M3 ring to make it hook up nicely in both orientations) so I settled for adding some extra vertical stripes within the macro halo to ensure the internal M3 rails on the SRAM are nailed up to the M5 PDN routing, and also to keep the M5 nailed together. I still have a really awful slot in M4 below each RAM macro but lucky alignment means this gap is (tenuously) bridged above the macro. Overall the RAMs are much better-connected than they were, and it's 5V Vcore so we can tolerate some supply bounce.

My goals for today are:

* Write the APU timers (if any)
* Implement the flash XIP interface (if any)
* Finalise the GPIO pinout

Just to recap I have 18 SRAM address inputs now (up to 512 kB with a 16-bit bus) and am moderately attached to them, partly since I could find 256k x 16 5V SRAMs on Digikey that weren't obsolete, but not 128k x 16. Would be shame to have that much RAM connected and not address all of it. This leaves me with 6 GPIOs. I have thoroughly eliminated UART since my virtual UART over TWD works great. So I need:

* Flash (SPI or dual SPI): SCK, IO0, IO1, CS0n
* GPIO: either an SPI GPIO expander (expensive) or a PISO shift register.

A common PISO register is the 74HC165. This lacks an output enable, so I'll connect it in a slightly sneaky way: clock will be the flash SCK, LOADn will be the flash chip select, and the data output QH will always be connected to the GPIO. So, after at least one flash read (or just pulsing the chip select low without issuing any other clocks) I just read in on QH for eight SCK cycles, or however many buttons are connected. Delightfully devilish, Seymour.

I have one spare pin. I don't have any particular need for it (it could be a blinkylight) but I think it would be fun to have infrared on here, for multiplayer. I have a (kinda shitty) UART already, so if you have an external demodulator then all that's necessary is to modulate the output by mixing in a 38 or 40 kHz carrier. Having an actual hardware UART output might be handy for low-level debug, and

Ok enough navel gazing, let's get on with it. APU timers first, as they're very simple.

...and that went fairly quickly. We have some simple timers (3x one-shot or repeating timers with a shared TICK timebase) and the APU interrupts are now also exposed to the main CPU, both because it might want to use the peripheral and because you might want to test your APU code running on the main CPU so you have access to VUART and more RAM.

I also stuck in some GPIO registers, and promoted the two AUDIO pins to honorary GPIO status (there are 6 GPIOs, 0 through 5, but AUDIO pins are bits 6 and 7 in the GPIO registers). I also wrote a bin-to-ROM generator to make AHB sea-of-gates ROMs from binary files, and wrote a very quick and dirty bootloader which searches for an image with a valid adler32 checksum in either of the first two flash sectors, and jumps into the first one it finds. It annoyingly comes out at just over 256 bytes (with bitbanged SPI).

I've decided I'm not interested in flash XIP. For one thing, I do that at work. For another, there's a big focus on real-time here and it's a performance trap (even though you can avoid it fine if you know it's there). Also I just straight up have enough RAM already to run some interesting firmware like MicroPython, so it's not necessary to execute-in-place from flash. Finally I don't want the timing cost of decoding an extra address MSB (or more than one) on the processor address bus, so good, that's gone.

I will add one flash peripheral which is a simple streaming read with a FIFO. This would be useful for paging in more game data, tile sets etc somewhat asynchronously with the CPU. This will be mapped on the same pins used by the bootrom for SPI, and will support (only) dual-SPI BBh reads.

### Day 8: SEVEN DAYS REMAIN

First task for the day is to bring up the flash bootloader I wrote yesterday. As I was lying in bed waiting to fall asleep I realised I missed a byte swap on the SPI read function so I added that.

I wrote a very quick and dirty SPI flash model in Verilog to load and run code from. I'll just write one testcase for this because it should always execute in the same way; what matters is what the second stage code does after being loaded into RAM.

I also moved the behavioural clock generator into the Verilog testbench. Fun fact: toggling the clock in Verilog and then just letting the simulator run using Timer(), simulates **twice as fast** as toggling the clock from cocotb. 100% overhead to toggle one signal. I don't think I will use cocotb in any future projects. Other complaints about coocotb to get it out of my system:

* The way the test runner implicitly scrapes all of the tests from a python module and doesn't let you filter the test list is dumb. If one test fails then the next thing I want to do is re-run the failing test, **only**. The developers apparently put zero thought into how their tool would be used.

* Having all of my tests in one big waveform dump is difficult to navigate.

* Running all tests sequentially in one simulator instance is incredibly slow compared to parallelising them over multiple instances, and this behaviour seems to be hardcoded.

* This may be a simulator issue, but refreshing the waveform viewer while the test is running misses all activity beyond about 300 us into the trace. I'm used to watching tests as they progress so I can spot mistakes early, kill and restart the test.

I don't like ragging on open-source projects but _damn_ this thing is a hot mess. I do not understand the hype. Python is a better language than Verilog for describing simulation models with complex _internal_ behaviour but every other part of the experience is slower and more frustrating.

I reduced the size of the flash second stage from 4k to 1k, partly because I'm bored of watching the simulator load zeroes. That's still plenty to run a basic C program that finds and loads the next stage. The bootrom still searches at addresses 0 and 4k (alternating until it gives up) so you can double-buffer any modifications to the bootloader.

Now the bootrom is brought up I can spend a bit of time looking at timing optimisation. First register the read/write strobes inside the APB register blocks (as PSEL && !PENABLE _always_ implies PENABLE on the next cycle): nice, looks better. Then remove the reset from the datapath flops on the SBUS bridge. Timing got a little worse, no clear reason why, may also just be because I added some clock enable terms to some signals like the write data. Then register the address bits in the APB blocks. This went less well:


```
 0# handler(int) in /nix/store/g74fz644z0828i5dksxm95mzdb91aq2g-openroad-2025-10-28/bin/.openroad-wrapped
 1# _sigtramp in /usr/lib/system/libsystem_platform.dylib
 2# drt::FlexDRWorker::initMazeCost_ap() in /nix/store/g74fz644z0828i5dksxm95mzdb91aq2g-openroad-2025-10-28/bin/.openroad-wrapped
 3# drt::FlexDRWorker::init(drt::frDesign const*) in /nix/store/g74fz644z0828i5dksxm95mzdb91aq2g-openroad-2025-10-28/bin/.openroad-wrapped
 4# drt::FlexDRWorker::main(drt::frDesign*) in /nix/store/g74fz644z0828i5dksxm95mzdb91aq2g-openroad-2025-10-28/bin/.openroad-wrapped
 5# drt::FlexDR::processWorkersBatch(std::__1::vector<std::__1::unique_ptr<drt::FlexDRWorker, std::__1::default_delete<drt::FlexDRWorker>>, std::__1::allocator<std::__1::unique_ptr<drt::FlexDRWorker, std::__1::default_delete<drt::FlexDRWorker>>>>&, drt::FlexDR::IterationProgress&) (.omp_outlined) in /nix/store/g74fz644z0828i5dksxm95mzdb91aq2g-openroad-2025-10-28/bin/.openroad-wrapped
```

This isn't the first time I've had the router crash, though the previous backtrace was inside some boost library. I can file a ticket but it's not like it'll be fixed before tapeout. Let's just change the design some more and hope it doesn't come back...

Ok, modified design still crashes. Just making a note. This one was the first crash:

`947219ba8c3e`

This one also crashes:

`9be10ee4b8`

```
[INFO DRT-0076]   Complete 3000 pins.
Signal 6 received
Stack trace:
 0# handler(int) in /nix/store/g74fz644z0828i5dksxm95mzdb91aq2g-openroad-2025-10-28/bin/.openroad-wrapped
 1# _sigtramp in /usr/lib/system/libsystem_platform.dylib
 2# pthread_kill in /usr/lib/system/libsystem_pthread.dylib
 3# abort in /usr/lib/system/libsystem_c.dylib
 4# malloc_vreport in /usr/lib/system/libsystem_malloc.dylib
 5# malloc_report in /usr/lib/system/libsystem_malloc.dylib
 6# ___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED in /usr/lib/system/libsystem_malloc.dylib

```

Yeah that does look like a heap corruption that got caught.

Ok I reverted that last APB change. Next on the list of optimisations is to implement a latch-based register file for Hazard3. Besides being smaller (and therefore hopefully more routable) it's easy to make this transparent for writes without additional muxing, so I can remove one of the inputs to the register bypass at the start of stage 2 and improve... basically all of my critical paths.

I'm using ICGTNs (negedge clock gates, i.e. positive latch + OR) to generate a latch enable in the second half of the clock cycle. This creates a half-cycle path into the register file write enable, but I'm not overly worried about that since that write enable is essentially just `mw_rd` gated with HREADY, and HREADY is available early in the cycle on this system.

A slight wrinkle is that there are no negative-enable latches in the GF180 library. First time round I put a clock inverter between the ICGTNs and the latch enables, and this went catastrophically wrong when CTS replicated the buffers: somehow I ended up with exactly one of the buffers for one bit of one register on one of the two processors with _only its output connected._ This problem was in the post-CTS netlist and not in the pre-CTS netlist, so the culprit is our old friend CTS again. The second time round I just put a behavioural invert on the latch enables and this went better.

With the latch register file in place, and the bypass logic slightly simplified to remove the MW->X path (unnecessary due to transparent writes on the latches), my setup WNS is from -7.2 ns to 4.7 ns. That's a pretty decent improvement, at the cost of high risk due to changing a core part of Hazard3 and additional risk of not properly constraining the latches for STA.

While I'm changing Hazard3 I went through and ripped out the resets from most of the datapath flops and some CSRs like mscratch and mepc. And... it's up at 6.9 ns. Wow, not sure why that is... don't think I did anything to make it worse!

### Day 9: SIX DAYS REMAIN

I want to work on timing and also start freezing the RTL.

I keep bumping into weird omissions from OpenSTA that make it difficult to describe my IO constraints in a sane way. I couldn't make it _not_ time the paths from the ICGTNs I use for SRAM_WEn and LCD_CLK from the negedge, so I worked around it by subtracting 50% of a clock period from the output delay.

That seemed to work, but now detailed routing crashes on my Mac, again. I'll move to my slower Linux box.

I couldn't figure out how to set different output delays for the A and OE paths through the SRAM_DQ pads (normally you would use `-through` on `set_output_delay` but OpenSTA doesn't support that). I ended up with this abomination:

```
set_output_delay $SRAM_IO_DELAY -clock [get_clock clk_sys] [get_ports {
    SRAM_A[*]
    SRAM_DQ[*]
    SRAM_OEn
    SRAM_CSn
    SRAM_UBn
    SRAM_LBn
}]

# The SRAM D paths are longer than others as they go through (a small amount
# of) logic in the processor instead of coming straight from flops. It's also
# desirable for them to remain valid a little longer for hold time against the
# release (rise) of WEn; quite common for async RAMs to have a hold
# requirement of 0 on this edge.
#
# OpenSTA does not support -through on set_output_delay (!) so can't specify
# different output delays through the OE (out enable) and A (out value) pins
# to the pad. Instead reset the A path and apply a normal set_max_delay
# constraint.
#
# Cannot relax the OE paths of the same pads in this way because it would
# create drive contention with the next read cycle.
set SRAM_D_DERATE 10
set_max_delay -through [get_pins {pad_SRAM_DQ*/A} ] -to [get_ports {SRAM_DQ*} ] \
    -reset_path [expr $CLK_SYS_PERIOD + $SRAM_D_DERATE - $SRAM_IO_DELAY]
```

...and that gives me 30 ns max delay violations where I used to have 10 ns ones. Stay calm... I realised I'm being dumb and sitting and waiting for synthesis/PnR results when I could be doing something productive in the meantime. An important task I've been putting off is bringing up code execution from the external SRAM, so let's go do that.

I tried my first sim with the behavioural async SRAM model I used on the original RISCBoy project, and... nothing. The Icarus simulator build hangs forever. None of these tools really work very well do they? By hacking out parts of the model I found that these lines were making it unhappy:

```verilog
always @ (*) begin: readport
	integer i;
	for (i = 0; i < W_BYTES; i = i + 1) begin
		dq_r[i * 8 +: 8] = !ce_n && !oe_n && we_n && !ben_n[i] ?
			mem[addr][i * 8 +: 8] : 8'hz;
	end 	
end
```

I _guess_ that this is unrolling into a huge set of parallel decoded statements instead of an index on `addr` followed by some byte-by-byte tristating. Let's test that theory by writing the steps out separately.


```verilog
wire [W_DATA-1:0] mem_rdata = mem[addr];
genvar g;
generate
for (g = 0; g < W_DATA; g = g + 1) begin: obuf
	assign dq = !ce_n && !oe_n && we_n && !ben_n[g] ?
		mem_rdata[g * 8 +: 8] : 8'hzz;
end
endgenerate
```

Ladies, gentlemen and furries we have solved the halting problem.

My previous synth run with 30ns failures has finished and I can look at the reports.

```
===========================================================================
report_checks -path_delay max (Setup)
============================================================================
======================= nom_tt_025C_5v00 Corner ===================================

Startpoint: _097153_ (rising edge-triggered flip-flop clocked by clk_sys)
Endpoint: SRAM_DQ[3] (output port clocked by clk_sys)
Path Group: clk_sys
Path Type: max

Fanout         Cap        Slew       Delay        Time   Description
---------------------------------------------------------------------------------------------
                                  0.000000    0.000000   clock clk_sys (rise edge)
                                  0.000000    0.000000   clock source latency
     2    0.395815    0.286553    0.000000    0.000000 ^ i_chip_core.clkroot_sys_u.magic_clkroot_anchor_u/Z (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
                                                         i_chip_core.apu_u.aout_fifo_u.gray_counter_w.clk (net)
                      0.293074    0.024544    0.024544 ^ clkbuf_0_i_chip_core.apu_u.aout_fifo_u.gray_counter_w.clk/I (gf180mcu_fd_sc_mcu9t5v0__clkbuf_20)
     2    0.208106    0.149035    0.259340    0.283884 ^ clkbuf_0_i_chip_core.apu_u.aout_fifo_u.gray_counter_w.clk/Z (gf180mcu_fd_sc_mcu9t5v0__clkbuf_20)
                                                         clknet_0_i_chip_core.apu_u.aout_fifo_u.gray_counter_w.clk (net)
                      0.150983    0.014117    0.298001 ^ clkbuf_1_0_0_i_chip_core.apu_u.aout_fifo_u.gray_counter_w.clk/I (gf180mcu_fd_sc_mcu9t5v0__buf_20)
     2    0.096313    0.093352    0.171571    0.469572 ^ clkbuf_1_0_0_i_chip_core.apu_u.aout_fifo_u.gray_counter_w.clk/Z (gf180mcu_fd_sc_mcu9t5v0__buf_20)
                                                         clknet_1_0_0_i_chip_core.apu_u.aout_fifo_u.gray_counter_w.clk (net)
                      0.093494    0.005428    0.474999 ^ delaybuf_397_clk_sys/I (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
     1    0.050961    0.080402    0.177239    0.652238 ^ delaybuf_397_clk_sys/Z (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
                                                         delaynet_397_clk_sys (net)
                      0.080449    0.003196    0.655434 ^ delaybuf_398_clk_sys/I (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
     3    0.326053    0.243139    0.274376    0.929810 ^ delaybuf_398_clk_sys/Z (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
                                                         delaynet_398_clk_sys (net)
                      0.247114    0.017529    0.947339 ^ clkbuf_3_3_0_i_chip_core.apu_u.aout_fifo_u.gray_counter_w.clk/I (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
     2    0.173324    0.152113    0.254513    1.201852 ^ clkbuf_3_3_0_i_chip_core.apu_u.aout_fifo_u.gray_counter_w.clk/Z (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
                                                         clknet_3_3_0_i_chip_core.apu_u.aout_fifo_u.gray_counter_w.clk (net)
                      0.152418    0.007275    1.209127 ^ delaybuf_259_clk_sys/I (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
     1    0.053513    0.082060    0.190453    1.399580 ^ delaybuf_259_clk_sys/Z (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
                                                         delaynet_259_clk_sys (net)
                      0.082110    0.003277    1.402858 ^ clkbuf_4_7__f_i_chip_core.apu_u.aout_fifo_u.gray_counter_w.clk/I (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
     5    0.322911    0.241437    0.276085    1.678943 ^ clkbuf_4_7__f_i_chip_core.apu_u.aout_fifo_u.gray_counter_w.clk/Z (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
                                                         clknet_4_7__leaf_i_chip_core.apu_u.aout_fifo_u.gray_counter_w.clk (net)
                      0.243535    0.012387    1.691330 ^ clkbuf_leaf_124_i_chip_core.apu_u.aout_fifo_u.gray_counter_w.clk/I (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
     4    0.115882    0.120642    0.233376    1.924706 ^ clkbuf_leaf_124_i_chip_core.apu_u.aout_fifo_u.gray_counter_w.clk/Z (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
                                                         clknet_leaf_124_i_chip_core.apu_u.aout_fifo_u.gray_counter_w.clk (net)
                      0.120717    0.004626    1.929332 ^ delaybuf_221_clk_sys/I (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
     1    0.024572    0.064592    0.171166    2.100498 ^ delaybuf_221_clk_sys/Z (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
                                                         delaynet_221_clk_sys (net)
                      0.064598    0.001306    2.101804 ^ _101385_/CLK (gf180mcu_fd_sc_mcu9t5v0__icgtp_2)
     1    0.051260    0.309442    0.363059    2.464863 ^ _101385_/Q (gf180mcu_fd_sc_mcu9t5v0__icgtp_2)
                                                         _047632_ (net)
                      0.309555    0.003255    2.468118 ^ clkbuf_0__047632_/I (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
     2    0.095405    0.110696    0.238976    2.707094 ^ clkbuf_0__047632_/Z (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
                                                         clknet_0__047632_ (net)
                      0.110715    0.002346    2.709440 ^ clkbuf_1_1__f__047632_/I (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
     3    0.026045    0.065488    0.169824    2.879265 ^ clkbuf_1_1__f__047632_/Z (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
                                                         clknet_1_1__leaf__047632_ (net)
                      0.065491    0.001056    2.880321 ^ _097153_/CLK (gf180mcu_fd_sc_mcu9t5v0__dffq_2)
     2    0.052230    0.308247    0.671910    3.552231 ^ _097153_/Q (gf180mcu_fd_sc_mcu9t5v0__dffq_2)
                                                         i_chip_core.cpu_u.core.mw_rd[0] (net)
                      0.308279    0.002024    3.554255 ^ _061992_/I (gf180mcu_fd_sc_mcu9t5v0__clkinv_4)
     2    0.030896    0.149886    0.131795    3.686050 v _061992_/ZN (gf180mcu_fd_sc_mcu9t5v0__clkinv_4)
                                                         _014941_ (net)
                      0.149894    0.001703    3.687753 v _061993_/A1 (gf180mcu_fd_sc_mcu9t5v0__and2_4)
     1    0.027301    0.100535    0.224044    3.911797 v _061993_/Z (gf180mcu_fd_sc_mcu9t5v0__and2_4)
                                                         _014942_ (net)
                      0.100546    0.001712    3.913509 v _061995_/B (gf180mcu_fd_sc_mcu9t5v0__aoi211_4)
     1    0.031798    0.535560    0.377450    4.290959 ^ _061995_/ZN (gf180mcu_fd_sc_mcu9t5v0__aoi211_4)
                                                         _014944_ (net)
                      0.535564    0.002952    4.293911 ^ _061996_/A2 (gf180mcu_fd_sc_mcu9t5v0__nand3_4)
     1    0.046756    0.281555    0.200218    4.494129 v _061996_/ZN (gf180mcu_fd_sc_mcu9t5v0__nand3_4)
                                                         _014945_ (net)
                      0.281567    0.002990    4.497119 v rebuffer3402/I (gf180mcu_fd_sc_mcu9t5v0__buf_12)
     8    0.225602    0.154900    0.296852    4.793971 v rebuffer3402/Z (gf180mcu_fd_sc_mcu9t5v0__buf_12)
                                                         net3401 (net)
                      0.158253    0.013858    4.807829 v _062007_/I (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
    10    0.128956    0.119690    0.224198    5.032028 v _062007_/Z (gf180mcu_fd_sc_mcu9t5v0__clkbuf_16)
                                                         _014954_ (net)
                      0.119844    0.004754    5.036781 v _066328_/I (gf180mcu_fd_sc_mcu9t5v0__buf_4)
    10    0.119569    0.210891    0.289962    5.326743 v _066328_/Z (gf180mcu_fd_sc_mcu9t5v0__buf_4)
                                                         _018952_ (net)
                      0.212054    0.008895    5.335639 v _066379_/A1 (gf180mcu_fd_sc_mcu9t5v0__nand2_1)
     1    0.014198    0.330655    0.201942    5.537580 ^ _066379_/ZN (gf180mcu_fd_sc_mcu9t5v0__nand2_1)
                                                         _018985_ (net)
                      0.330655    0.000458    5.538038 ^ _066380_/B (gf180mcu_fd_sc_mcu9t5v0__oai211_2)
     1    0.037834    0.531008    0.301178    5.839216 v _066380_/ZN (gf180mcu_fd_sc_mcu9t5v0__oai211_2)
                                                         _018986_ (net)
                      0.531010    0.001994    5.841210 v _066381_/B (gf180mcu_fd_sc_mcu9t5v0__oai21_4)
     3    0.061273    0.460562    0.366992    6.208202 ^ _066381_/ZN (gf180mcu_fd_sc_mcu9t5v0__oai21_4)
                                                         i_chip_core.apb_hwdata[19] (net)
                      0.460564    0.001496    6.209698 ^ max_cap475/I (gf180mcu_fd_sc_mcu9t5v0__buf_8)
     1    0.170435    0.258621    0.297572    6.507269 ^ max_cap475/Z (gf180mcu_fd_sc_mcu9t5v0__buf_8)
                                                         net475 (net)
                      0.259320    0.010016    6.517285 ^ wire474/I (gf180mcu_fd_sc_mcu9t5v0__buf_8)
     1    0.162954    0.247453    0.275630    6.792915 ^ wire474/Z (gf180mcu_fd_sc_mcu9t5v0__buf_8)
                                                         net474 (net)
                      0.248279    0.009867    6.802783 ^ wire473/I (gf180mcu_fd_sc_mcu9t5v0__clkbuf_12)
     3    0.151452    0.170127    0.267399    7.070181 ^ wire473/Z (gf180mcu_fd_sc_mcu9t5v0__clkbuf_12)
                                                         net473 (net)
                      0.170231    0.005666    7.075847 ^ _073574_/I0 (gf180mcu_fd_sc_mcu9t5v0__mux2_1)
     1    0.024898    0.336391    0.405414    7.481261 ^ _073574_/Z (gf180mcu_fd_sc_mcu9t5v0__mux2_1)
                                                         i_chip_core.eram_ctrl_u.sram_dq_out[3] (net)
                      0.336392    0.000798    7.482059 ^ wire383/I (gf180mcu_fd_sc_mcu9t5v0__clkbuf_8)
     1    0.224607    0.325392    0.375604    7.857663 ^ wire383/Z (gf180mcu_fd_sc_mcu9t5v0__clkbuf_8)
                                                         net383 (net)
                      0.326310    0.009897    7.867560 ^ pad_SRAM_DQ[3].u/A (gf180mcu_fd_io__bi_t)
     1    2.865654    1.581011    2.635134   10.502694 ^ pad_SRAM_DQ[3].u/PAD (gf180mcu_fd_io__bi_t)
                                                         SRAM_DQ[3] (net)
                      1.581011    0.000000   10.502694 ^ SRAM_DQ[3] (inout)
                                             10.502694   data arrival time

                                 18.333334   18.333334   max_delay
                                  0.000000   18.333334   clock clk_sys (rise edge)
                                  0.000000   18.333334   clock network delay (propagated)
                                 -0.250000   18.083334   clock uncertainty
                                  0.000000   18.083334   clock reconvergence pessimism
                                -33.333332  -15.249999   output external delay
                                            -15.249999   data required time
---------------------------------------------------------------------------------------------
                                            -15.249999   data required time
                                            -10.502694   data arrival time
---------------------------------------------------------------------------------------------
                  
```

This is mostly sane but there are two issues:

* Minor issue: it includes the clock insertion delay (my fault as I didn't specify it should start from the Q)

* Major issue: it still subtracts the output delay (also kind of my fault, OpenSTA doesn't list this on the list of things reset by `-reset_path`)

Because only the OE paths have named flops (D comes from the processor if you recall) a way to fix this would be to relax the output delay on the pad as a whole and then tighten then OE paths via `set_max_delay` from flop Q to pad PAD.

This is all kind of disgusting and, emboldened by my success with the ICGTNs (or at least I now depend on those working already) I'm going to re-add the negedge flops present on RISCBoy. They'll get the same +50% margin as the "negedge" ICGTN paths (though this is a genuine negedge). Timings from the specimen 5V SRAM part (12 ns version of R1RP0416DI, which is the slowest grade of this part):

```
                                         MIN MAX
Read cycle time                    tRC   12  -
Address access time                tAA   -   12
Chip select access time            tACS  -   12
Output enable to output valid      tOE   -   6
Byte select to output valid        tBA   -   6
Output hold from address change    tOH   3   -
Chip select to output in low-Z     tCLZ  3   -
Output enable to output in low-Z   tOLZ  0   -
Byte select to output in low-Z     tBLZ  0   -
Chip deselect to output in high-Z  tCHZ  -   6
Output disable to output in high-Z tOHZ  -   6
Byte deselect to output in high-Z  tBHZ  -   6

                                        MIN MAX
Write cycle time                   tWC  12  -
Address valid to end of write      tAW  8   -
Chip select to end of write        tCW  8   -
Write pulse width                  tWP  8   -
Byte select to end of write        tBW  8   -
Address setup time                 tAS  0   -
Write recovery time                tWR  0   -
Data to write time overlap         tDW  6   -
Data hold from write time          tDH  0   -
Write disable to output in low-Z   tOW  3   -
Output disable to output in high-Z tOHZ -   6
Write enable to output in high-Z   tWHZ -   6
```

"Write recovery time" is effectively a hold time against WEn deassertion, and is 0. tDW (write overlap) is essentially a setup time against WEn deassertion, and is 6 ns, or half the cycle time. This means putting the output on a negedge is reasonable and I should be able to bend OpenSTA to my will by timing from the explicit flops I'll add back to the SRAM PHY.

The last big thing on my RTL list is the GPIOs and peripherals. There are two planned peripherals: a UART (optional as the TWD VUART thing seems to work great) and a streaming SPI read peripheral. The SPI read will probably go on the APU side as I don't have a DMA, so the idea is the APU can use it to stream out ADPCM etc directly from flash without involving the main CPU.

The UART is the quickest one to add tonight. I took the RISCBoy UART, added a couple of missing features like FIFO flush, and added the ability to modulate the output at (e.g.) 38 kHz so you can use it for IR transmit and recieve.

### Day 10: FIVE DAYS REMAIN

I moved back to my Linux workstation (slower than my macbook but the tools run correctly) and noticed I am genuinely getting a lot of DRCs from both Magic and KLayout. All of the DRCs are in the standard cell library provided by Global Foundries. I spent some time looking into it and I'm pretty sure all of these are issues with the KLayout and Magic DRC decks, not genuine manufacturability issues. I filed an issue [here](https://github.com/wafer-space/gf180mcu-project-template/issues/34).

I spent quite a while yesterday iterating on timing instead of closing down the final RTL. Let's try and get that locked down today. Anything after today doesn't make the cut. So:

* SPI streaming read peripheral

* Clock muxes and dividers

* Maybe DCO ring osc

* Prioritise palette writes over palette writes in PRAM (bad read makes one pixel wrong, bad write makes many pixels wrong).

Let's go gamers.

Uh actually first, I should look into why I'm getting 0.5 ns TNS hold violations in the fast corner. The WNS is only 70 ps, so I'll just add 80 ps more hold margin and not think any more about why my CTS is such a shitshow. (I have around 0.7 ns of skew on my system clock so I am already leaning *hard* on buffer fixes, but I don't think there is much more I can do to improve this within tool limitations.)

Ok, I'm pretty happy with the design of the SPI streaming peripheral now. It's on the APU side, but the CPU can reach across and "pause" the stream which cleanly interrupts the sequence of SPI transfers and releases the chip select. The CPU can then do its stuff with the GPIOs (like reading from a shift register to get the buttons) and then unpause the stream. The APU doesn't have to do anything special to handle this, other than tolerate occasional drops in bandwidth.

The SPI is single-width only, because this is going to have to go through level shifters to get to the 3.3V SPI flash. I'm not exposing myself to the horrors of bidirectional level shifters again.

I made the PPU PRAM change, and while I was in there I also put some pipestaging on the APB signals going to the RAM. I haven't really seen these on any timing reports but without these there is only one stage of flops between the CPU's address adders and the palette RAM address bus, and they are physically distant, so this was a 100% vibe-based optimisation.

I looked at the difficult paths in Hazard3. There was a small simplification I could make which is to use the pre-registered regnum in stage 2 for the re-read during stall. I looked at using a simpler condition for the select and bringing the stall in later as a clock enable, and mostly succeeded in reminding myself why this circuit is the way it currently is :)

Clock dividers! I had lots of fun ideas but I don't have time to implement them. It's going to be two stages of ripple divider with a mux to select between 0, 1 and 2 stages. This gives division by 1, 2 and 4. It's getting pretty late...

Currently I'm trying a number of things which intuitively I think should improve timing, and timing is degraded or swings wildly around. This is an experience I've had a lot with Yosys on FPGAs, just have to push through it.


### Day 10: FOUR DAYS REMAIN

I wrote the new clock generators. clk_sys and clk_audio are both independently selectable from one of the following: padin_clk, padin_clk x 2/3, padin_clk x 1/2, and DCK. I wrote what I thought was a reasonable first pass at constraints. And... it's completely fucked. 40 ns setup violations and multi ns hold.

```
###############################################################################
# Clock definitions

# Pad clocks
set PADIN_CLK_MHZ 48
set DCK_MHZ 20

# Internally generated clocks
set CLK_SYS_MHZ 24
set CLK_LCD_MHz 48
set CLK_AUDIO_MHZ 24

set PADIN_CLK_PERIOD [expr 1000.0 / $PADIN_CLK_MHZ]
set CLK_SYS_PERIOD   [expr 1000.0 / $CLK_SYS_MHZ]
set DCK_PERIOD       [expr 1000.0 / $DCK_MHZ]
set CLK_LCD_PERIOD   [expr 1000.0 / $CLK_LCD_MHz]
set CLK_AUDIO_PERIOD [expr 1000.0 / $CLK_AUDIO_MHZ]

# Primary input clock. Source of all other clocks except for DCK.
create_clock [get_pins i_chip_core.clocks_u.clkroot_padin_clk_u.magic_clkroot_anchor_u/Z] \
    -name padin_clk \
    -period $PADIN_CLK_PERIOD

# Divisions of primary input clock. These only clock a few flops and a clock
# gate in the clock muxes (each). There are no synchronous paths between these
# and other clocks, so they are constrained as primary instead of generated
# clocks.

create_clock [get_pins i_chip_core.clocks_u.clkroot_div_2_u.magic_clkroot_anchor_u/Z] \
    -name padin_clk_div_2 \
    -period [expr 2.0 * $PADIN_CLK_PERIOD]

create_clock [get_pins i_chip_core.clocks_u.clkroot_div_3over2_u.magic_clkroot_anchor_u/Z] \
    -name padin_clk_div_3over2 \
    -period [expr 1.5 * $PADIN_CLK_PERIOD]

# System clock: main CPU, SRAM, digital peripherals and external SRAM interface
create_clock [get_pins i_chip_core.clocks_u.clkroot_sys_u.magic_clkroot_anchor_u/Z] \
    -name clk_sys \
    -period $CLK_SYS_PERIOD

# LCD serial clock
create_clock [get_pins i_chip_core.clkroot_lcd_u.magic_clkroot_anchor_u/Z] \
    -name clk_lcd \
    -period $CLK_LCD_PERIOD

# Audio clock
create_clock [get_pins i_chip_core.clkroot_audio_u.magic_clkroot_anchor_u/Z] \
    -name clk_audio \
    -period $CLK_AUDIO_PERIOD

# Debug clock: clocks the debug transport module and one side of its bus CDC.
# Defined at the pad so we can constrain IO against it.
create_clock [get_pins pad_DCK/PAD] \
    -name dck \
    -period $DCK_PERIOD
```

The first hold path I see in the STA makes no sense. It's a path from the data path flops in the APU async FIFO on the clk_sys side to the receiving flop on the clk_audio side, **but**, the originating clock is reported as `padin_clk` and the receiving clock is reported as `dck`. That is not a functional path and could only be reported if OpenSTA was propagating the upstream clock through the root of the primary clock I defined. The docs imply it does not do that, but the reports imply that it DEFINITELY DOES. I could also just be confused by CTS.

After a couple of misfires the next promising solution I tried was defining generated clocks on the divider outputs (which do not work the same way as the OpenSTA docs):

```tcl
# System clock: main CPU, SRAM, digital peripherals and external SRAM interface
create_generated_clock \
    -source [get_pins i_chip_core.clocks_u.clkroot_padin_clk_u.magic_clkroot_anchor_u/Z] \
    -master_clock [get_clocks padin_clk] \
    -name clk_sys \
    -divide_by 2 \
    [get_pins i_chip_core.clocks_u.clkroot_sys_u.magic_clkroot_anchor_u/Z]

# Audio clock
create_generated_clock  \
    -source [get_pins i_chip_core.clocks_u.clkroot_padin_clk_u.magic_clkroot_anchor_u/Z] \
    -master_clock [get_clocks padin_clk] \
    -name clk_audio \
    -divide_by 2 \
    [get_pins i_chip_core.clocks_u.clkroot_audio_u.magic_clkroot_anchor_u/Z]

# LCD serial clock
create_generated_clock \
    -source [get_pins i_chip_core.clocks_u.clkroot_padin_clk_u.magic_clkroot_anchor_u/Z] \
    -master_clock [get_clocks padin_clk] \
    -name clk_lcd \
    -divide_by 1 \
    [get_pins i_chip_core.clocks_u.clkroot_lcd_u.magic_clkroot_anchor_u/Z]
```

This takes my setup WNS from -37 ns to -11 ns. Still not sure what that degraded at all.

Ok, I'm just losing far too much time to OpenSTA issues. Time to do something drastic. I'm considering going to go to one functional clock (plus DCK) and a parallel bus connection for the display.

Currently this is my top level:

```verilog
module chip_top #(
    parameter N_DVDD    = 8,
    parameter N_DVSS    = 10,
    parameter N_SRAM_DQ = 16,
    parameter N_SRAM_A  = 18,
    parameter N_GPIO    = 6
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
    inout  wire                 SRAM_UBn,
    inout  wire                 SRAM_LBn,

    // Audio PWM
    inout  wire                 AUDIO_L,
    inout  wire                 AUDIO_R,

    // Serial LCD and backlight PWM
    inout  wire                 LCD_CLK,
    inout  wire                 LCD_DAT,
    inout  wire                 LCD_CSn,
    inout  wire                 LCD_DC,
    inout  wire                 LCD_BL,

    // Other stuff (incl boot SPI flash)
    inout  wire [N_GPIO-1:0]    GPIO
);
```

I'm pretty sure I can tie the RD and WR (for an 8080 mode display) and just pulse CSn. So LCD_CLK and LCD_DAT would both disappear, and I would need to find 6 more signals from somewhere to make up my 8-bit parallel bus.

GPIO has a minimum of 4 if I want to do SPI flash for boot and games storage. So, that's 2 I can steal.

Buttons can be attached with 1k or so resistors to the LCD data bus, then read during vblank by tristating and enabling the pad pull-ups.

I could sacrifice one audio pin. That would also free up a bit of logic.

I could drop an address pin on the RAM. It would be a shame but survivable.

Still two to find. Debug is not negotiable. SRAM data bus is not negotiable. SRAM_CSn could go, but it wastes a shit ton of power; I think the specimen part I looked at used 70 mA while selected and < 1 mA otherwise. I _could_ get rid of the byte strobes, if I implemented byte writes as read-modify-write.

### Day 11: THREE DAYS REMAIN

Actually I think my day count might be off by one. Not sure what happened there.

I made one more attempt to constrain clocks in a sensible way, going back to my old primary clocks and blocking the propagation of other clocks through those points:

```tcl
# Prevent all other clocks from propagating through the point we define as the
# origin of clock generator outputs
proc block_pregen_clocks {dst} {
    set_sense -stop_propagation [get_pins $dst] -clock [get_clocks {
        padin_clk
        padin_clk_div_2
        padin_clk_div_3over2
        dck
    }]
}

block_pregen_clocks i_chip_core.clocks_u.clkroot_sys_u.magic_clkroot_anchor_u/Z
block_pregen_clocks i_chip_core.clocks_u.clkroot_lcd_u.magic_clkroot_anchor_u/Z
block_pregen_clocks i_chip_core.clocks_u.clkroot_audio_u.magic_clkroot_anchor_u/Z
```

Setup: -37 ns WNS. Someone somewhere is doing something dumb and I've run out of time to debug it. The generated clocks approach yesterday was getting -11 ns WNS. I looked at the path and a high-fanout flop inside the processor (part of the current instruction register) was still unit drive, and had a 

Looking at parallel displays. Taking ST7796S as an example:

* Write cycle time tWC 66 ns
* Write data setup tDST 10 ns
* Write data hold time tDHT 10 ns
* Write pulse high/low duration tWRH/tWRL 15 ns each

Setup and hold are both referenced from the rising edge of WRX.

At 25 MHz my clock period is 41.67 ns. So I can't write every cycle, but I can use the same clock gate used for serial clocking and just write on alternate cycles. There is a cute 3.9" 320 x 320 display with ST7796S here:

https://www.buydisplay.com/square-3-92-inch-320x320-ips-tft-lcd-display-spi-interface

Another one, 240 x 320 2.8" with ILI9341:

https://www.buydisplay.com/2-8-inch-240x320-ips-tft-lcd-display-panel-optional-touch-panel-wide-view

ILI9341 also registers write data on the rising edge of WRX.

For ILI9341 the timings for 8080 (-I and -II) are:

* tWC 66 ns
* tWRH tWRL 15 ns each (pulse)
* tDST tDHT 10 ns each (referenced to WRX rising edge)

So essentially the same.


New chip top level:

```
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
```

There is no dedicated LCD chip select pin. Both ILI9341 and ST7796S say the chip select can be held low for these devices. DAT[1] can be a chip select for serial mode. So the LCD interface pin count has increased by 6. (As an aside, the LCD reset is assumed tied to the same board-level reset as the chip itself).

Those 6 additional pins came from:

* Removed SRAM_UBn and SRAM_LBn (2)
* Replaced AUDIO_L and AUDIO_R with AUDIO (1)
* Removed two GPIOs (2)
* Removed one SRAM address line (1)

All 8x LCD_DAT will also be available as software-controlled GPIO. In serial mode this means we have 11x GPIO total (SPI x4, AUDIO x1, LCD_DAT x6).

Maximum external RAM is now 256 kB (17 address bits, 128k x 16). I'll also take this opportunity to shrink the processor address space to 19 bits (512 kB total) because this slightly improves address-phase timing.

Also worth noting serial LCD at 24 Mbps gives 26 FPS on a 240 x 240 serial LCD (like ST7789) so it's not completely useless.

The modifications to the SRAM controller were mostly painless. I still don't have system-level tests with the PPU fetching from RAM so I just hooked up the "DMA" read port on the RAM controller to toggle on/off every cycle to give it a quick smoke test with CPU contending with PPU access.

Lots of boring structural RTL with high chance of failure... it's fine, there are a couple days for verification lmao

I rewrote the display controller to add support for 8-bit output, horizontal and vertical doubling, and half-rate output (i.e. output clock division). This is a fairly simple block but there is scope to fuck it up.

With the last big RTL changes in I spent a couple of hours looking at increasing the APU RAM from 2 kB to 4 kB. This would make quite a big difference to what you can do with the APU, and also the CPU can make use of spare APU RAM at a cost of 3 cycles per access. Unfortunately no matter how much I pushed the RAMs around I was seeing a couple of ns of timing degradation from the higher utilisation and possibly also from bits of processor getting trowelled into the buffer channels between RAMs (which I haven't figured out how to put exclusions on). Also, when I started squeezing out the margins between RAMS and between RAMs and the chip edge I kept getting detailed placement failures saying it failed to place one instance which was not even an instance in my netlist (it would be called something like `wire263`) making it impossible to diagnose where the congestion was. After global placement I did see a few big flops getting put in vertical buffer channels that were narrower than the flop, so it's possible that would fail to legalise, but then I would expect the detailed placer to give me a real flop instance name in its output. Anyway, I spent as much time on this as I was willing to and it is sadly a no.

### Day 12: TWO DAYS REMAIN

Today the design is going to meet timing. The secret to timing closure is to know at all times that you are right and the computer is wrong. The design will meet timing if you maintain the patience to explain to the computer what a useless dumbass it is.

I looked into mapping DFFEs as scan flops, like I threatened to do at the start of the project. This turns out to be mostly very easy, with some caveats. Just write some modules like so (with reference to Yosys' [internal cell library](https://yosyshq.readthedocs.io/projects/yosys/en/latest/cell_index.html)):


```verilog
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
```

Then pass that file to Yosys through a curious series of pipes by putting this in your LibreLane config file:

```yaml
SYNTH_EXTRA_MAPPING_FILE: dir::/gf180_scanflop_map.v
```

This tells Yosys it can implement a DFFE (aka flop with enable) using a scan flop (aka flop with an integrated mux, used for DFT scan chain insertion) by recirculating the output back to the input when the scan enable is low. A model of a scan flop is something like:

```verilog
always @ (posedge CLK) Q <= SE ? SI : D;
```

I wrote a few of these to cover the different variants of high/low enable, async reset/preset etc. I also added some mappings for flops with synchronous set/clear, which appear in a few places where I have non-reset flops.

One issue with this is STA sees a hold check on the short path from Q back to D. On my first run with the above tech mapping I saw hold buffers inserted on the short path. This is actually a false path because after all we are using the feedback path to hold Q stable, therefore on clock edges where D is selected there is no transition on Q, and no potential for hold violation.

It's all well and good understanding this, but translating it into constraints is difficult because there is no tracability from Yosys' early tech mapping through to the synthesised netlist. I ended up just writing some awful TCL to filter out the correct flops and disable hold checks on the correct inputs:

```tcl
puts "(SCANMAP) Adding hold waivers to pseudo-DFFE scan flops:"
set scan_flops [get_cells -hier -filter "ref_name =~ gf180mcu_fd_sc_mcu9t5v0__sdffq_*"]
foreach flop $scan_flops {
    set flop_name [sta::get_full_name $flop]
    set q [sta::get_full_name [get_nets -of_object [get_pins ${flop_name}/Q]]]
    set d [sta::get_full_name [get_nets -of_object [get_pins ${flop_name}/D]]]
    set si [sta::get_full_name [get_nets -of_object [get_pins ${flop_name}/SI]]]
    if {[string equal $q $d]} {
        puts "(SCANMAP) Disabling hold checks -> D for pseudo-DFFE $flop_name (Q = ${q})"
        set_false_path -hold -to [get_pins ${flop_name}/D]
    } elseif {[string equal $q $si]} {
        puts "(SCANMAP) Disabling hold checks -> SI for pseudo-DFFE $flop_name (Q = ${q})"
        set_false_path -hold -to [get_pins ${flop_name}/SI]
    } else {
        puts "(SCANMAP) Skipping scan flop ${flop_name}: D = ${d} SI = ${si} Q = ${q}"
    }
}
```

This has some quite verbose but useful log output:

```
(SCANMAP) Disabling hold checks -> SI for pseudo-DFFE _105324_ (Q = i_chip_core.cpu_u.core.xm_addr_align[0])
(SCANMAP) Disabling hold checks -> SI for pseudo-DFFE _105325_ (Q = i_chip_core.cpu_u.core.xm_addr_align[1])
(SCANMAP) Disabling hold checks -> D for pseudo-DFFE _105515_ (Q = i_chip_core.dtm_async_bridge_u.src_paddr_pwdata_pwrite[0])
(SCANMAP) Disabling hold checks -> D for pseudo-DFFE _105516_ (Q = i_chip_core.dtm_async_bridge_u.src_paddr_pwdata_pwrite[1])
(SCANMAP) Disabling hold checks -> D for pseudo-DFFE _105517_ (Q = i_chip_core.dtm_async_bridge_u.src_paddr_pwdata_pwrite[2])
...
(SCANMAP) Skipping scan flop _105811_: D = net1172 SI = _002624_ Q = i_chip_core.rom_hrdata[31]
(SCANMAP) Skipping scan flop _105812_: D = net SI = _002623_ Q = i_chip_core.rom_hrdata[30]
(SCANMAP) Skipping scan flop _105813_: D = net1175 SI = _002621_ Q = i_chip_core.rom_hrdata[29]
(SCANMAP) Skipping scan flop _105814_: D = net1176 SI = _002620_ Q = i_chip_core.rom_hrdata[28]
```

With the above I can now somewhat reasonably disable clock gating (yes), which reduces my clock skew and is overall a win, at least from a timing point of view. Might run a bit warm for a GameBoy.

I'm close but in my worst reg2reg path I see that there are high-fanout scan flops in my processor which are still the minimum possible size with multi-nanosecond slew times I'm a bit confused by this because I don't think there is anything stopping the tools from resizing the cells I mapped, and some of the immediate loads of these flops have been sized up. In fact in theory I have enabled resizing during _synthesis_, which is not enabled by default. As a temporary hack (...) I changed the default size by just using a different cell instance in the tech map file (for _all_ scan flops): this is just substituting `gf180mcu_fd_sc_mcu9t5v0__sdffq_1` above for `gf180mcu_fd_sc_mcu9t5v0__sdffq_4` etc.

After fixing up some overly tight IO constraints on the SRAM D outputs I'm at -1.1 ns WNS on the reg2reg paths, which seems in reach of my goal. After then finally re-instating the negedge flops on the SRAM_D outputs which I couldn't figure out how to constrain sensibly before (since there are some posedge flops going to the same pad and (editor removed long rant about OpenSTA)), which relaxes the tough paths from the processor even further, I'm at... -4.1 ns. The critical reg2reg path through the processor is in the same place it was before, and there are a ton of unit-drive cells on that path.


