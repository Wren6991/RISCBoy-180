# SPDX-FileCopyrightText: © 2025 Project Template Contributors
# SPDX-License-Identifier: Apache-2.0

import os
import random
import logging
import yaml
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, Edge, RisingEdge, FallingEdge, ClockCycles
from cocotb_tools.runner import get_runner
from cocotb.types import Logic
from cocotb.handle import Release

sim = os.getenv("SIM", "icarus")
pdk_root = "../gf180mcu"
pdk = os.getenv("PDK", "gf180mcuD")
scl = os.getenv("SCL", "gf180mcu_fd_sc_mcu7t5v0")
gl = os.getenv("GL", False)

hdl_toplevel = "chip_top"

###############################################################################
# TWD debug helpers

TWD_PERIOD = 50

TWD_CMD_DISCONNECT = 0x0
TWD_CMD_R_IDCODE   = 0x1
TWD_CMD_R_CSR      = 0x2
TWD_CMD_W_CSR      = 0x3
TWD_CMD_R_ADDR     = 0x4
TWD_CMD_W_ADDR     = 0x5
TWD_CMD_R_DATA     = 0x7
TWD_CMD_R_BUFF     = 0x8
TWD_CMD_W_DATA     = 0x9
TWD_CMD_R_AINFO    = 0xb

TWD_CSR_VERSION_LSB       = 28
TWD_CSR_VERSION_BITS      = 0xf << TWD_CSR_VERSION_LSB
TWD_CSR_ASIZE_LSB         = 24
TWD_CSR_ASIZE_BITS        = 0x7 << TWD_CSR_ASIZE_LSB
TWD_CSR_EPARITY_BITS      = 1 << 18
TWD_CSR_EBUSFAULT_BITS    = 1 << 17
TWD_CSR_EBUSY_BITS        = 1 << 16
TWD_CSR_AINCR_BITS        = 1 << 12
TWD_CSR_BUSY_BITS         = 1 << 8
TWD_CSR_NDTMRESETACK_BITS = 1 << 5
TWD_CSR_NDTMRESETREQ_BITS = 1 << 4
TWD_CSR_MDROPADDR_BITS    = 0xf

async def twd_shift_out(dut, bits, n):
    if n % 8 != 0:
        bits = bits << (8 - n)
    for i in range(n):
        bitidx = i ^ 0x7
        dut.DIO.value = (bits >> bitidx) & 1
        await Timer(TWD_PERIOD / 2, "ns")
        dut.DCK.value = 1
        await Timer(TWD_PERIOD / 2, "ns")
        dut.DCK.value = 0

async def twd_shift_in(dut, n):
    accum = 0
    dut.DIO.value = Release()
    for i in range(n):
        bitidx = i ^ 0x7
        accum = accum | ((int(dut.DIO.value) & 1) << bitidx)
        await Timer(TWD_PERIOD / 2, "ns")
        dut.DCK.value = 1
        await Timer(TWD_PERIOD / 2, "ns")
        dut.DCK.value = 0
    if n % 8 != 0:
        accum = accum >> (8 - n)
    return accum

def odd_parity(x):
    return 1 - (x.bit_count() & 1)

async def twd_command(dut, cmd, n_bytes, wdata=None):
    await twd_shift_out(dut, 1 << 5 | (cmd << 1) | (odd_parity(cmd)), 6)
    if cmd == TWD_CMD_DISCONNECT:
        return None
    if wdata is None:
        _ = await twd_shift_in(dut, 2)
        rdata = await twd_shift_in(dut, 8 * n_bytes)
        parity = await twd_shift_in(dut, 1)
        assert parity == odd_parity(rdata)
        _ = await twd_shift_in(dut, 3)
        return rdata
    else:
        await twd_shift_out(dut, 0, 2)
        await twd_shift_out(dut, wdata, 8 * n_bytes)
        await twd_shift_out(dut, odd_parity(wdata) << 3, 4)

async def twd_connect(dut):
    connect_seq = [
        0x00, 0xa7, 0xa3, 0x92, 0xdd, 0x9a, 0xbf, 0x04, 0x31, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x0f
    ]
    _ = await twd_shift_in(dut, 80)
    await twd_command(dut, TWD_CMD_DISCONNECT, 0)
    for b in connect_seq:
        await twd_shift_out(dut, b, 8)
    csr_rdata = await twd_command(dut, TWD_CMD_R_CSR, 4)
    assert ((csr_rdata & TWD_CSR_VERSION_BITS) >> TWD_CSR_VERSION_LSB) == 1
    assert ((csr_rdata & TWD_CSR_ASIZE_BITS) >> TWD_CSR_ASIZE_LSB) == 0
    await twd_command(dut, TWD_CMD_W_CSR, 4,
        TWD_CSR_EPARITY_BITS |
        TWD_CSR_EBUSFAULT_BITS |
        TWD_CSR_EBUSY_BITS
    )

async def twd_read_idcode(dut):
    return await twd_command(dut, TWD_CMD_R_IDCODE, 4)

async def twd_write_bus(dut, addr, wdata):
    await twd_command(dut, TWD_CMD_W_ADDR, 1, addr)
    await twd_command(dut, TWD_CMD_W_DATA, 4, wdata)
    while True:
        csr = await twd_command(dut, TWD_CMD_R_CSR, 4)
        if (csr & TWD_CSR_BUSY_BITS) == 0:
            break

async def twd_read_bus(dut, addr):
    await twd_command(dut, TWD_CMD_W_ADDR, 1, addr)
    _ = await twd_command(dut, TWD_CMD_R_DATA, 4)
    while True:
        csr = await twd_command(dut, TWD_CMD_R_CSR, 4)
        if (csr & TWD_CSR_BUSY_BITS) == 0:
            break
    return await twd_command(dut, TWD_CMD_R_BUFF, 4)

###############################################################################
# RISC-V debug helpers

DM_DATA0                   = 0x04
DM_DMCONTROL               = 0x10
DM_DMSTATUS                = 0x11
DM_ABSTRACTCS              = 0x16
DM_COMMAND                 = 0x17
DM_ABSTRACTAUTO            = 0x18
DM_PROGBUF0                = 0x20
DM_PROGBUF1                = 0x21

DM_DMCONTROL_DMACTIVE      = 0x1
DM_DMCONTROL_HARTSEL_LSB   = 16
DM_DMCONTROL_HALTREQ       = 1 << 31
DM_DMCONTROL_RESUMEREQ     = 1 << 30

DM_DMSTATUS_VERSION_BITS   = 0xf
DM_DMSTATUS_ANYHALTED      = 1 << 8
DM_DMSTATUS_ALLHALTED      = 1 << 9
DM_DMSTATUS_ANYRUNNING     = 1 << 10
DM_DMSTATUS_ALLRUNNING     = 1 << 11
DM_DMSTATUS_ANYUNAVAIL     = 1 << 12
DM_DMSTATUS_ALLUNAVAIL     = 1 << 13
DM_DMSTATUS_ALLNONEXISTENT = 1 << 14
DM_DMSTATUS_ANYNONEXISTENT = 1 << 15
DM_DMSTATUS_ALLRESUMEACK   = 1 << 16
DM_DMSTATUS_ANYRESUMEACK   = 1 << 17
DM_DMSTATUS_ALLHAVERESET   = 1 << 18
DM_DMSTATUS_ANYHAVERESET   = 1 << 19

DM_ABSTRACTCS_BUSY         = 1 << 12
DM_ABSTRACTCS_CMDERR       = 0x7 << 8

DM_COMMAND_SIZE_WORD       = 2 << 20
DM_COMMAND_POSTEXEC        = 1 << 18
DM_COMMAND_TRANSFER        = 1 << 17
DM_COMMAND_WRITE           = 1 << 16
DM_COMMAND_REGNO_LSB       = 0

CSR_MVENDORID              = 0xf11
CSR_MARCHID                = 0xf12
CSR_MIMPID                 = 0xf13
CSR_MISA                   = 0x301
CSR_H3_MSLEEP              = 0xbf0
CSR_TSELECT                = 0x7a0
CSR_TDATA1                 = 0x7a1
CSR_TDATA2                 = 0x7a2
CSR_TDATA3                 = 0x7a3
CSR_TINFO                  = 0x7a4
CSR_TCONTROL               = 0x7a5
CSR_DCSR                   = 0x7b0
CSR_DPC                    = 0x7b1

async def rvdebug_init(dut):
    await twd_connect(dut)
    dmstatus = await twd_read_bus(dut, DM_DMSTATUS)
    assert (dmstatus & 0xf) == 2
    await twd_write_bus(dut, DM_DMCONTROL, 0)
    await twd_write_bus(dut, DM_DMCONTROL, DM_DMCONTROL_DMACTIVE)

async def rvdebug_count_harts(dut):
    await twd_write_bus(dut, DM_DMCONTROL, DM_DMCONTROL_DMACTIVE)
    for i in range(32 + 1):
        # 32 is max harts supported by Hazard3 DM
        expect = DM_DMCONTROL_DMACTIVE | (i << DM_DMCONTROL_HARTSEL_LSB)
        await twd_write_bus(dut, DM_DMCONTROL, expect)
        actual = await twd_read_bus(dut, DM_DMCONTROL)
        if expect != actual:
            return i
        status = await twd_read_bus(dut, DM_DMSTATUS)
        if status & DM_DMSTATUS_ANYNONEXISTENT:
            return i
    return i

async def rvdebug_select_hart(dut, hart):
    await twd_write_bus(dut, DM_DMCONTROL,
        DM_DMCONTROL_DMACTIVE | (hart << DM_DMCONTROL_HARTSEL_LSB))

async def rvdebug_halt(dut):
    dmcontrol = await twd_read_bus(dut, DM_DMCONTROL)
    await twd_write_bus(dut, DM_DMCONTROL, dmcontrol | DM_DMCONTROL_HALTREQ)
    while True:
        stat = await twd_read_bus(dut, DM_DMSTATUS)
        if stat & DM_DMSTATUS_ALLHALTED:
            break

async def rvdebug_resume(dut):
    dmcontrol = await twd_read_bus(dut, DM_DMCONTROL)
    await twd_write_bus(dut, DM_DMCONTROL, dmcontrol | DM_DMCONTROL_RESUMEREQ)
    while True:
        stat = await twd_read_bus(dut, DM_DMSTATUS)
        if stat & DM_DMSTATUS_ALLRESUMEACK:
            break

async def rvdebug_put_gpr(dut, gpr, wdata):
    await twd_write_bus(dut, DM_DATA0, wdata)
    await twd_write_bus(dut, DM_COMMAND,
        DM_COMMAND_TRANSFER |
        DM_COMMAND_SIZE_WORD |
        DM_COMMAND_WRITE |
        ((0x1000 + gpr) << DM_COMMAND_REGNO_LSB)
    )
    while True:
        stat = await twd_read_bus(dut, DM_ABSTRACTCS)
        if (stat & DM_ABSTRACTCS_BUSY) == 0:
            break

async def rvdebug_get_gpr(dut, gpr):
    await twd_write_bus(dut, DM_COMMAND,
        DM_COMMAND_TRANSFER |
        DM_COMMAND_SIZE_WORD |
        ((0x1000 + gpr) << DM_COMMAND_REGNO_LSB)
    )
    while True:
        stat = await twd_read_bus(dut, DM_ABSTRACTCS)
        if (stat & DM_ABSTRACTCS_BUSY) == 0:
            break
    return await twd_read_bus(dut, DM_DATA0)

async def rvdebug_put_csr(dut, csr, wdata):
    gprsave = await rvdebug_get_gpr(dut, 8)
    await twd_write_bus(dut, DM_DATA0, wdata)
    await twd_write_bus(dut, DM_PROGBUF0, 0x00001073 | (csr << 20) | (8 << 15)) # csrw xxx, s0
    await twd_write_bus(dut, DM_PROGBUF1, 0x00100073) # ebreak
    await twd_write_bus(dut, DM_COMMAND,
        DM_COMMAND_POSTEXEC |
        DM_COMMAND_TRANSFER |
        DM_COMMAND_SIZE_WORD |
        DM_COMMAND_WRITE |
        0x1008
    )
    while True:
        stat = await twd_read_bus(dut, DM_ABSTRACTCS)
        if (stat & DM_ABSTRACTCS_BUSY) == 0:
            break
    await rvdebug_put_gpr(dut, 8, gprsave)

async def rvdebug_get_csr(dut, csr):
    gprsave = await rvdebug_get_gpr(dut, 8)
    await twd_write_bus(dut, DM_PROGBUF0, 0x00002073 | (csr << 20) | (8 << 7)) # csrr s0, xxx
    await twd_write_bus(dut, DM_PROGBUF1, 0xbff01073 | (8 << 15)) # csrw dmdata0, s0
    await twd_write_bus(dut, DM_COMMAND, DM_COMMAND_POSTEXEC)
    while True:
        stat = await twd_read_bus(dut, DM_ABSTRACTCS)
        if (stat & DM_ABSTRACTCS_BUSY) == 0:
            break
    rdata = await twd_read_bus(dut, DM_DATA0)
    await rvdebug_put_gpr(dut, 8, gprsave)
    return rdata


###############################################################################

async def enable_power(dut):
    dut.VDD.value = 1
    dut.VSS.value = 0

async def start_clock(clock, freq=50):
    c = Clock(clock, 1 / freq * 1000, "ns")
    cocotb.start_soon(c.start())

async def reset(reset, active_low=True, time_ns=1000):
    reset.value = not active_low
    await Timer(time_ns, "ns")
    reset.value = active_low


async def start_up(dut):
    """Startup sequence"""
    if gl:
        await enable_power(dut)
    await start_clock(dut.CLK)
    await reset(dut.RSTn)

@cocotb.test()
async def test_twd_idcode(dut):
    """Connect TWD and read IDCODE. Check against predefined value."""
    await start_up(dut)
    await twd_connect(dut)
    idcode = await twd_read_idcode(dut)
    cocotb.log.info(f"IDCODE = {idcode:08x}")
    assert idcode == 0x00280035

@cocotb.test()
async def test_debug_archid(dut):
    """Connect to RISC-V core 0 and check marchid and misa CSRs"""
    await start_up(dut)
    cocotb.log.info(f"Connecting debug")
    await rvdebug_init(dut)
    cocotb.log.info(f"Halting core 0")
    await rvdebug_select_hart(dut, 0)
    await rvdebug_halt(dut)
    # GPRs aren't reset, so initialise the one that's saved and restored:
    await rvdebug_put_gpr(dut, 8, 0)
    marchid = await rvdebug_get_csr(dut, CSR_MARCHID)
    cocotb.log.info(f"marchid = {marchid:08x}")
    assert marchid == 0x1b # Hazard3
    misa = await rvdebug_get_csr(dut, CSR_MISA)
    cocotb.log.info(f"misa    = {misa:08x}")
    # assert misa == 0x1b # Hazard3

def chip_top_runner():

    proj_path = Path(__file__).resolve().parent

    sources = []
    defines = {}
    includes = []

    if gl:
        # SCL models
        sources.append(Path(pdk_root) / pdk / "libs.ref" / scl / "verilog" / f"{scl}.v")
        sources.append(Path(pdk_root) / pdk / "libs.ref" / scl / "verilog" / "primitives.v")

        # We use the powered netlist
        sources.append(proj_path / f"../final/pnl/{hdl_toplevel}.pnl.v")

        defines = {"FUNCTIONAL": True, "USE_POWER_PINS": True}
    else:
        config = yaml.safe_load(open("../librelane/config.yaml"))
        sources.extend([x.replace("dir::", "") for x in config["VERILOG_FILES"]])
        includes.extend([x.replace("dir::", "") for x in config["VERILOG_INCLUDE_DIRS"]])

    sources += [
        # IO pad models
        Path(pdk_root) / pdk / "libs.ref/gf180mcu_fd_io/verilog/gf180mcu_fd_io.v",
        Path(pdk_root) / pdk / "libs.ref/gf180mcu_fd_io/verilog/gf180mcu_ws_io.v",
        
        # SRAM macros
        Path(pdk_root) / pdk / "libs.ref/gf180mcu_fd_ip_sram/verilog/gf180mcu_fd_ip_sram__sram512x8m8wm1.v",
        
        # Custom IP
        proj_path / "../ip/gf180mcu_ws_ip__id/vh/gf180mcu_ws_ip__id.v",
        proj_path / "../ip/gf180mcu_ws_ip__logo/vh/gf180mcu_ws_ip__logo.v",
    ]

    build_args = []

    if sim == "icarus":
        # For debugging
        # build_args = ["-Winfloop", "-pfileline=1"]
        pass

    if sim == "verilator":
        build_args = ["--timing", "--trace", "--trace-fst", "--trace-structs"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel=hdl_toplevel,
        defines=defines,
        always=True,
        includes=includes,
        build_args=build_args,
        waves=True,
    )

    plusargs = []

    runner.test(
        hdl_toplevel=hdl_toplevel,
        test_module="chip_top_tb,",
        plusargs=plusargs,
        waves=True,
    )


if __name__ == "__main__":
    chip_top_runner()
