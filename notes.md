# TODOs

## RTL

* PPU
	* Think harder about palette RAM read/write collisions
	* Possible to reduce RAM bandwidth for ABLIT/ATILE? (possibly have timing budget for 1-entry tilenum cache)
* GPIOs
	* Finalise list of peripherals
* SPI flash read
* Clocking
	* Create DCO
		* Hard macro?
	* Create clock muxes and dividers
	* Create control registers and hook everything up
* Review resettable flops and see if they can be made non-reset for better density/routing
* Hazard3: can use predecoded, registered versions of d_rs1/d_rs2 for stalled regfile read

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

