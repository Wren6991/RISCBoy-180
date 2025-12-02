# SPDX-FileCopyrightText: © 2025 Project Template Contributors
# SPDX-License-Identifier: Apache-2.0

import argparse
import inspect
import logging
import os
import random
import re
import struct
import subprocess
import sys
import yaml
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, Edge, RisingEdge, FallingEdge, ClockCycles
from cocotb_tools.runner import get_runner
from cocotb.handle import Release

sim = os.getenv("SIM", "icarus")
pdk_root = "../gf180mcu"
pdk = os.getenv("PDK", "gf180mcuD")
scl = os.getenv("SCL", "gf180mcu_fd_sc_mcu9t5v0")
gl = os.getenv("GL", False)

###############################################################################
# System address map

ERAM_BASE    = 0x00000
IRAM_BASE    = 0x40000
APU_BASE     = 0x60000
PERI_BASE    = 0x70000

IRAM_END     = IRAM_BASE + 0x2000
APU_RAM_BASE = APU_BASE
APU_RAM_END  = APU_RAM_BASE + 0x800

APU_PERI_BASE = APU_BASE + 0x8000
APU_IPC_BASE = APU_PERI_BASE
APU_IPC_SOFTIRQ_SET = APU_IPC_BASE + 4
APU_IPC_SOFTIRQ_CLR = APU_IPC_BASE + 8

###############################################################################
# TWD debug helpers

TWD_PERIOD = 50

TWD_CMD_DISCONNECT = 0x0
TWD_CMD_R_IDCODE   = 0x1
TWD_CMD_R_AINFO    = 0x2
TWD_CMD_R_STAT     = 0x4
TWD_CMD_W_CSR      = 0x6
TWD_CMD_R_CSR      = 0x7
TWD_CMD_R_ADDR     = 0x8
TWD_CMD_W_ADDR     = 0x9
TWD_CMD_W_ADDR_R   = 0xa
TWD_CMD_R_DATA     = 0xb
TWD_CMD_W_DATA     = 0xc
TWD_CMD_R_BUFF     = 0xd

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

VUART_STAT = 0x80
VUART_STAT_RXVLD = 1 << 31
VUART_STAT_TXRDY = 1 << 30
VUART_INFO = 0x81
VUART_FIFO = 0x82

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

async def twd_command(dut, cmd, n_bits, wdata=None):
    await twd_shift_out(dut, 1 << 5 | (cmd << 1) | (odd_parity(cmd)), 6)
    if cmd == TWD_CMD_DISCONNECT:
        return None
    if wdata is None:
        _ = await twd_shift_in(dut, 2)
        rdata = await twd_shift_in(dut, n_bits)
        parity = await twd_shift_in(dut, 1)
        assert parity == odd_parity(rdata)
        _ = await twd_shift_in(dut, 3)
        return rdata
    else:
        await twd_shift_out(dut, 0, 2)
        await twd_shift_out(dut, wdata, n_bits)
        await twd_shift_out(dut, odd_parity(wdata) << 3, 4)

twd_cached_addr = None
async def twd_connect(dut):
    global twd_cached_addr
    twd_cached_addr = None
    connect_seq = [
        0x00, 0xa7, 0xa3, 0x92, 0xdd, 0x9a, 0xbf, 0x04, 0x31, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x0f
    ]
    _ = await twd_shift_in(dut, 80)
    await twd_command(dut, TWD_CMD_DISCONNECT, 0)
    for b in connect_seq:
        await twd_shift_out(dut, b, 8)
    csr_rdata = await twd_command(dut, TWD_CMD_R_CSR, 32)
    assert ((csr_rdata & TWD_CSR_VERSION_BITS) >> TWD_CSR_VERSION_LSB) == 1
    assert ((csr_rdata & TWD_CSR_ASIZE_BITS) >> TWD_CSR_ASIZE_LSB) == 0
    await twd_command(dut, TWD_CMD_W_CSR, 32,
        TWD_CSR_EPARITY_BITS |
        TWD_CSR_EBUSFAULT_BITS |
        TWD_CSR_EBUSY_BITS
    )

async def twd_read_idcode(dut):
    return await twd_command(dut, TWD_CMD_R_IDCODE, 32)

async def twd_write_bus(dut, addr, wdata):
    global twd_cached_addr
    if addr != twd_cached_addr:
        await twd_command(dut, TWD_CMD_W_ADDR, 8, addr)
        twd_cached_addr = addr
    await twd_command(dut, TWD_CMD_W_DATA, 32, wdata)
    while True:
        stat = await twd_command(dut, TWD_CMD_R_STAT, 4)
        if (stat & 1) == 0:
            break

async def twd_read_bus(dut, addr):
    global twd_cached_addr
    twd_cached_addr = addr
    await twd_command(dut, TWD_CMD_W_ADDR_R, 8, addr)
    for i in range(10):
        stat = await twd_command(dut, TWD_CMD_R_STAT, 4)
        if (stat & 1) == 0:
            break
    else:
        assert False
    return await twd_command(dut, TWD_CMD_R_BUFF, 32)

async def twd_vuart_getchar(dut, max_poll=10):
    # The status flags are also present in the FIFO register, but still use
    # STAT because the FIFO storage flops are Xs initially.
    for i in range(max_poll):
        fifo_stat = await twd_read_bus(dut, VUART_STAT)
        if fifo_stat & VUART_STAT_RXVLD:
            return (await twd_read_bus(dut, VUART_FIFO)) & 0xff
    return None

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
CSR_MHARTID                = 0xf14
CSR_MISA                   = 0x301
CSR_MIE                    = 0x304
CSR_MIP                    = 0x344
CSR_H3_MSLEEP              = 0xbf0
CSR_TSELECT                = 0x7a0
CSR_TDATA1                 = 0x7a1
CSR_TDATA2                 = 0x7a2
CSR_TDATA3                 = 0x7a3
CSR_TINFO                  = 0x7a4
CSR_TCONTROL               = 0x7a5
CSR_DCSR                   = 0x7b0
CSR_DPC                    = 0x7b1

rvdebug_progbuf_cache = [0, 0]
async def rvdebug_init(dut):
    global rvdebug_progbuf_cache
    rvdebug_progbuf_cache = [0, 0]
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

async def rvdebug_wait_acmd_finish(dut):
    for i in range(10):
        stat = await twd_read_bus(dut, DM_ABSTRACTCS)
        if (stat & DM_ABSTRACTCS_BUSY) == 0:
            break
    else:
        assert False

async def rvdebug_get_gpr(dut, gpr):
    await twd_write_bus(dut, DM_COMMAND,
        DM_COMMAND_TRANSFER |
        DM_COMMAND_SIZE_WORD |
        ((0x1000 + gpr) << DM_COMMAND_REGNO_LSB)
    )
    await rvdebug_wait_acmd_finish(dut)
    return await twd_read_bus(dut, DM_DATA0)

async def rvdebug_put_progbuf(dut, idx, instr):
    global rvdebug_progbuf_cache
    if rvdebug_progbuf_cache[idx] != instr:
        rvdebug_progbuf_cache[idx] = instr
        await twd_write_bus(dut, DM_PROGBUF0 + idx, instr)

async def rvdebug_put_csr(dut, csr, wdata):
    gprsave = await rvdebug_get_gpr(dut, 8)
    await twd_write_bus(dut, DM_DATA0, wdata)
    await rvdebug_put_progbuf(dut, 0, 0x00001073 | (csr << 20) | (8 << 15)) # csrw xxx, s0
    await rvdebug_put_progbuf(dut, 1, 0x00100073) # ebreak
    await twd_write_bus(dut, DM_COMMAND,
        DM_COMMAND_POSTEXEC |
        DM_COMMAND_TRANSFER |
        DM_COMMAND_SIZE_WORD |
        DM_COMMAND_WRITE |
        0x1008
    )
    await rvdebug_wait_acmd_finish(dut)
    await rvdebug_put_gpr(dut, 8, gprsave)

async def rvdebug_get_csr(dut, csr):
    gprsave = await rvdebug_get_gpr(dut, 8)
    await rvdebug_put_progbuf(dut, 0, 0x00002073 | (csr << 20) | (8 << 7)) # csrr s0, xxx
    await rvdebug_put_progbuf(dut, 1, 0xbff01073 | (8 << 15)) # csrw dmdata0, s0
    await twd_write_bus(dut, DM_COMMAND, DM_COMMAND_POSTEXEC)
    await rvdebug_wait_acmd_finish(dut)
    rdata = await twd_read_bus(dut, DM_DATA0)
    await rvdebug_put_gpr(dut, 8, gprsave)
    return rdata

async def rvdebug_write_mem32(dut, addr, wdata):
    save_s0 = await rvdebug_get_gpr(dut, 8)
    save_s1 = await rvdebug_get_gpr(dut, 9)
    await rvdebug_put_gpr(dut, 9, wdata)
    await twd_write_bus(dut, DM_DATA0, addr)
    await rvdebug_put_progbuf(dut, 0, 0x00002023 | (9 << 20) | (8 << 15)) # sw s1, (s0)
    await rvdebug_put_progbuf(dut, 1, 0x00100073) # ebreak
    await twd_write_bus(dut, DM_COMMAND,
        DM_COMMAND_POSTEXEC |
        DM_COMMAND_TRANSFER |
        DM_COMMAND_SIZE_WORD |
        DM_COMMAND_WRITE |
        0x1008
    )
    await rvdebug_wait_acmd_finish(dut)
    await rvdebug_put_gpr(dut, 8, save_s0)
    await rvdebug_put_gpr(dut, 9, save_s1)

async def rvdebug_read_mem32(dut, addr):
    save_s0 = await rvdebug_get_gpr(dut, 8)
    await twd_write_bus(dut, DM_DATA0, addr)
    await rvdebug_put_progbuf(dut, 0, 0x00002003 | (8 << 7) | (8 << 15)) # lw s0, (s0)
    await rvdebug_put_progbuf(dut, 1, 0x00100073) # ebreak
    await twd_write_bus(dut, DM_COMMAND,
        DM_COMMAND_POSTEXEC |
        DM_COMMAND_TRANSFER |
        DM_COMMAND_SIZE_WORD |
        DM_COMMAND_WRITE |
        0x1008
    )
    await rvdebug_wait_acmd_finish(dut)
    rdata = await rvdebug_get_gpr(dut, 8)
    await rvdebug_put_gpr(dut, 8, save_s0)
    return rdata

###############################################################################
# Helpers

async def start_up(dut):
    if gl:
        dut.VDD.value = 1
        dut.VSS.value = 0
    dut.RSTn.value = 0
    dut.clk_running.value = 0
    await Timer(1, "us")
    dut.clk_running.value = 1
    await Timer(1, "us")
    dut.RSTn.value = 1

###############################################################################
# Debug-driven tests

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
    assert misa == 0x40801106

@cocotb.test()
async def test_debug_hart_ids(dut):
    """Enumerate harts, then connect to each one and check mhartid == HARTSEL"""
    await start_up(dut)
    cocotb.log.info(f"Connecting debug")
    await rvdebug_init(dut)
    n_harts = await rvdebug_count_harts(dut)
    cocotb.log.info(f"Found {n_harts} harts")
    assert n_harts == 2

    for hart in range(n_harts):
        cocotb.log.info(f"Connecting to hart {hart}")
        await rvdebug_select_hart(dut, hart)
        await rvdebug_halt(dut)
        # GPRs aren't reset, so initialise the one that's saved and restored:
        await rvdebug_put_gpr(dut, 8, 0)
        marchid = await rvdebug_get_csr(dut, CSR_MARCHID)
        cocotb.log.info(f"marchid = {marchid:08x}")
        assert marchid == 0x1b # Hazard3
        mhartid = await rvdebug_get_csr(dut, CSR_MHARTID)
        cocotb.log.info(f"mhartid = {mhartid:08x}")
        assert mhartid == hart

@cocotb.test()
async def test_iram_smoke(dut):
    """Smoke test for IWRAM (cover all four banks with 32-bit read/write)"""
    cocotb.log.info(f"Read + write all banks")
    await start_up(dut)
    await rvdebug_init(dut)
    await rvdebug_halt(dut)
    await rvdebug_put_gpr(dut, 8, 0)
    await rvdebug_put_gpr(dut, 9, 0)
    expect = dict()
    for i in range(8):
        addr = IRAM_BASE + (i & 0xc) + ((i % 4) * 0x800)
        wdata = addr * 123 ^ 0xaa55aa55
        cocotb.log.info(f"{addr:08x} <- {wdata:08x}")
        expect[addr] = wdata
        # Cover R2W on same bank
        await rvdebug_write_mem32(dut, addr, wdata)
        rdata = await rvdebug_read_mem32(dut, addr)
        cocotb.log.info(f"         -> {rdata:08x}")
        assert rdata == wdata
    cocotb.log.info(f"Re-read")
    for i in range(8):
        addr = IRAM_BASE + (i & 0xc) + ((i % 4) * 0x800)
        rdata = await rvdebug_read_mem32(dut, addr)
        assert rdata == expect[addr]

@cocotb.test()
async def test_cross_apu_cpu_mem(dut):
    """Check APU and CPU can see each other's writes to APU memory"""
    await start_up(dut)
    await rvdebug_init(dut)
    for i in range(2):
        await rvdebug_select_hart(dut, i)
        await rvdebug_halt(dut)
        await rvdebug_put_gpr(dut, 8, 0)
        await rvdebug_put_gpr(dut, 9, 0)

    cocotb.log.info(f"Write on CPU")
    await rvdebug_select_hart(dut, 0)
    await rvdebug_write_mem32(dut, APU_RAM_BASE, 0x12345678)
    cocotb.log.info(f"Read on APU")
    await rvdebug_select_hart(dut, 1)
    rdata = await rvdebug_read_mem32(dut, APU_RAM_BASE)
    assert rdata == 0x12345678

    cocotb.log.info(f"Write on APU")
    await rvdebug_select_hart(dut, 1)
    await rvdebug_write_mem32(dut, APU_RAM_BASE, 0xabcdef5a)
    cocotb.log.info(f"Read on CPU")
    await rvdebug_select_hart(dut, 0)
    rdata = await rvdebug_read_mem32(dut, APU_RAM_BASE)
    assert rdata == 0xabcdef5a

@cocotb.test()
async def test_riscv_soft_irq(dut):
    """Check APU and CPU can post each other soft IRQs."""
    await start_up(dut)
    cocotb.log.info(f"Initialising debug")
    await rvdebug_init(dut)
    await rvdebug_select_hart(dut, 0)
    await rvdebug_halt(dut)
    await rvdebug_put_gpr(dut, 8, 0)
    await rvdebug_put_gpr(dut, 9, 0)
    await rvdebug_select_hart(dut, 1)
    await rvdebug_halt(dut)
    await rvdebug_put_gpr(dut, 8, 0)
    await rvdebug_put_gpr(dut, 9, 0)

    for irq_mask in range(4):
        irq_apu = (irq_mask >> 1) & 1
        irq_cpu = irq_mask & 1
        cocotb.log.info(f"Set APU = {(irq_mask >> 1) & 1} CPU = {irq_mask & 1}")
        await rvdebug_write_mem32(dut, APU_IPC_SOFTIRQ_CLR, 0x3)
        await rvdebug_write_mem32(dut, APU_IPC_SOFTIRQ_SET, irq_mask)
        await rvdebug_select_hart(dut, 0)
        mip = await rvdebug_get_csr(dut, CSR_MIP)
        cocotb.log.info(f"CPU mip = {mip:08x}")
        assert ((mip >> 3) & 0x1) == irq_cpu
        await rvdebug_select_hart(dut, 1)
        mip = await rvdebug_get_csr(dut, CSR_MIP)
        cocotb.log.info(f"APU mip = {mip:08x}")
        assert ((mip >> 3) & 0x1) == irq_apu


###############################################################################
# Test signatures

expected_outputs = {
    "hellow": "Hello, world!",
    "start_apu": "\r\n".join([
        "Starting APU",
        "Received IRQ"
    ]),
    "byte_strobe": "\r\n".join([
        "Zero init",
        "00000000",
        "00000000",
        "00000000",
        "00000000",
        "Byte write",
        "a3a2a1a0",
        "a7a6a5a4",
        "abaaa9a8",
        "afaeadac",
        "Byte write, one per word",
        "000000e0",
        "0000e100",
        "00e20000",
        "e3000000",
        "Halfword write",
        "b3b2b1b0",
        "b7b6b5b4",
        "bbbab9b8",
        "bfbebdbc",
        "Word write",
        "c3c2c1c0",
        "c7c6c5c4",
        "cbcac9c8",
        "cfcecdcc",
    ]),
    "byte_strobe_cproc_contention": "\r\n".join([
        "Starting CPROC",
        "Zero init",
        "00000000",
        "00000000",
        "00000000",
        "00000000",
        "Byte write",
        "a3a2a1a0",
        "a7a6a5a4",
        "abaaa9a8",
        "afaeadac",
        "Byte write, one per word",
        "000000e0",
        "0000e100",
        "00e20000",
        "e3000000",
        "Halfword write",
        "b3b2b1b0",
        "b7b6b5b4",
        "bbbab9b8",
        "bfbebdbc",
        "Word write",
        "c3c2c1c0",
        "c7c6c5c4",
        "cbcac9c8",
        "cfcecdcc",
    ]),
    "iram_addr_width": "\r\n".join([
        "Writing",
        "Reading",
        "21",
        "42",
        "63",
        "84",
        "a5",
        "c6",
        "e7",
        "08",
        "29",
        "4a",
        "6b",
        "8c",
        "ad",
    ]),
    "aram_addr_width": "\r\n".join([
        "Writing",
        "Reading",
        "21",
        "42",
        "63",
        "84",
        "a5",
        "c6",
        "e7",
        "08",
        "29",
        "4a",
        "6b",
    ]),
    "spi_stream_clkdiv": "\r\n".join([
        "Trying clkdiv: 02",
        "07060504",
        "Trying clkdiv: 04",
        "0b0a0908",
        "Trying clkdiv: 06",
        "0f0e0d0c",
        "Trying clkdiv: 08",
        "13121110",
        "Trying clkdiv: 0a",
        "17161514",
        "Trying clkdiv: 0c",
        "1b1a1918",
        "Trying clkdiv: 0e",
        "1f1e1d1c",
        "Trying clkdiv: 10",
        "23222120",
    ]),
    "spi_stream_pause": "\r\n".join([
        "Trying clkdiv: 02",
        "03020100",
        "07060504",
        "0b0a0908",
        "0f0e0d0c",
        "13121110",
        "17161514",
        "1b1a1918",
        "1f1e1d1c",
        "Trying clkdiv: 08",
        "03020100",
        "07060504",
        "0b0a0908",
        "0f0e0d0c",
        "13121110",
        "17161514",
        "1b1a1918",
        "1f1e1d1c",
    ]),
    "apu_timer_smoke": "\r\n".join([
        "Starting timer",
        "Stopped timer",
        # Intervals are 10, 15, 20 us. Simultaneous are reported in order 0, 1, 2.
        # t = 10
        "00",
        # t = 15
        "01",
        # t = 20
        "00",
        "02",
        # t = 30
        "00",
        "01",
        # t = 40
        "00",
        "02",
        # t = 45
        "01",
        # t = 50
        "00",
        # t = 60
        "00",
        "01",
        "02",
        # Now repeats until there are 32 total
        # t = 10
        "00",
        # t = 15
        "01",
        # t = 20
        "00",
        "02",
        # t = 30
        "00",
        "01",
        # t = 40
        "00",
        "02",
        # t = 45
        "01",
        # t = 50
        "00",
        # t = 60
        "00",
        "01",
        "02",
        # t = 10
        "00",
        # t = 15
        "01",
        # t = 20
        "00",
        "02",
        # t = 30
        "00",
        "01",
    ])
}

# Bit 8 is D/C (0 for command)
expected_lcd_cmds_st7789 = [
    0x001,
    0x011,
    0x03a,
    0x155,
    0x036,
    0x100,
    0x02a,
    0x100,
    0x100,
    0x100,
    0x1f0,
    0x02b,
    0x100,
    0x100,
    0x100,
    0x1f0,
    0x021,
    0x013,
    0x029,
]

def rgb565_to_displaydata(l):
    for x in l:
        yield 0x100 | ((x >> 8) & 0xff)
        yield 0x100 | ((x >> 0) & 0xff)

def rgb555_to_displaydata(l):
    for x in l:
        y = ((x & 0x7fe0) << 1) | (x & 0x1f)
        yield 0x100 | ((y >> 8) & 0xff)
        yield 0x100 | ((y >> 0) & 0xff)

def hdouble(l):
    for x in l:
        yield x
        yield x

expected_lcd_capture = {
    "display_init_parallel": expected_lcd_cmds_st7789,
    "display_init_parallel_halfrate": expected_lcd_cmds_st7789,
    "display_init_serial": expected_lcd_cmds_st7789,
    "display_init_serial_halfrate": expected_lcd_cmds_st7789,
    "ppu_parallel_scanbuf_width": list(rgb555_to_displaydata(range(2 * 512))),
    "ppu_parallel_pram_write": list(rgb555_to_displaydata(x + 0xab00 for x in range(256))),
    "ppu_parallel_pixel_double":
        list(rgb555_to_displaydata(hdouble(x + 0xab00 for x in range(128)))) +
        list(rgb555_to_displaydata(hdouble(x + 0xab00 for x in range(128)))) +
        list(rgb555_to_displaydata(hdouble(x + 0xab00 for x in range(128, 256)))) +
        list(rgb555_to_displaydata(hdouble(x + 0xab00 for x in range(128, 256)))),
    "ppu_parallel_frame_height": list(rgb555_to_displaydata(range(512))),
    "ppu_parallel_cproc_address_range": list(rgb555_to_displaydata(range(7)))
}

###############################################################################
# Execution-driven tests

@cocotb.test()
@cocotb.parametrize(app=[
    "hellow",
    "start_apu",
    "byte_strobe",
    "byte_strobe_cproc_contention",
    "display_init_parallel",
    "display_init_parallel_halfrate",
    "display_init_serial",
    "display_init_serial_halfrate",
    "ppu_parallel_scanbuf_width",
    "ppu_parallel_pram_write",
    "ppu_parallel_pixel_double",
    "ppu_parallel_frame_height",
    "ppu_parallel_cproc_address_range",
    "iram_addr_width",
    "aram_addr_width",
    "spi_stream_clkdiv",
    "spi_stream_pause",
    "apu_timer_smoke",
])
async def test_execute_eram(dut, app="hellow"):
    """Execute code from ERAM"""
    cocotb.log.info(f"Application: {app}")
    assert app in expected_outputs or app in expected_lcd_capture, f"Missing test signature for {app}"

    swtest_dir = Path(__file__).resolve().parent.parent / "software/tests/eram"
    rc = subprocess.run(["make", "-C", swtest_dir, f"APP={app}"])
    assert rc.returncode == 0
    with open(swtest_dir / f"build/{app}.bin", "rb") as f:
        prog_bytes = f.read()
    cocotb.log.info(f"Program size = {len(prog_bytes)}")
    prog_hwords = list(w[0] for w in struct.iter_unpack("<h", prog_bytes))
    for i, hword in enumerate(prog_hwords):
        dut.eram_u.mem[i].value = hword
        dut.eram_u.mem[i].value = Release()

    # Test pattern at start of flash
    for i in range(256):
        dut.flash_u.mem[i].value = i
        dut.flash_u.mem[i].value = Release()

    dut.lcd_bus_width.value = 1
    dut.lcd_capture_enable.value = 0

    await start_up(dut)
    await twd_connect(dut)

    capture_lcd = app in expected_lcd_capture
    if capture_lcd:
        dut.lcd_capture_enable.value = 1
        dut.lcd_bus_width.value = "parallel" in app

    await rvdebug_init(dut)
    await rvdebug_halt(dut)
    await rvdebug_put_gpr(dut, 8, 0)
    await rvdebug_put_csr(dut, CSR_DPC, ERAM_BASE)
    cocotb.log.info(f"Resuming at {ERAM_BASE:x}")
    await rvdebug_resume(dut)

    vuart_stdout = []
    def test_done():
        if len(vuart_stdout) < 6:
            return False
        endstr = "".join(vuart_stdout[-6:])
        if endstr == "!TPASS":
            return True
        if endstr == "!TFAIL":
            return True
        return False

    while not test_done():
        c = await twd_vuart_getchar(dut, max_poll=200)
        if c is None: break
        sys.stdout.write(chr(c))
        vuart_stdout.append(chr(c))

    sys.stdout.write("\n")
    vuart_stdout = "".join(vuart_stdout)

    assert vuart_stdout.endswith("!TPASS")
    vuart_stdout = vuart_stdout[:-6]

    cocotb.log.info(f"Processor standard output:\n\n{vuart_stdout}\n")
    if app in expected_outputs:
        assert vuart_stdout.strip() == expected_outputs[app], f"Did not match expected output:\n{expected_outputs[app]}"

    if capture_lcd:
        lcd_capture_len = dut.lcd_byte_count.value
        cocotb.log.info(f"Captured {lcd_capture_len} bytes from LCD output.")
        lcd_capture = list(int(dut.lcd_capture_buffer[i].value) for i in range(lcd_capture_len))
        if False:
            print("\nActual:\n")
            for b in lcd_capture: print(f"{b:03x}")
            print("\nExpected:\n")
            for b in expected_lcd_capture[app]: print(f"{b:03x}")
        assert lcd_capture == expected_lcd_capture[app]

@cocotb.test()
@cocotb.parametrize(app=[
    "hellow",
    "start_apu",
    "byte_strobe",
])
async def test_execute_iram(dut, app="hellow"):
    """Execute code from IRAM"""
    assert app in expected_outputs
    swtest_dir = Path(__file__).resolve().parent.parent / "software/tests/iram"
    rc = subprocess.run(["make", "-C", swtest_dir, f"APP={app}"])
    assert rc.returncode == 0
    with open(swtest_dir / f"build/{app}.bin", "rb") as f:
        prog_bytes = f.read()
    cocotb.log.info(f"Program size = {len(prog_bytes)}")
    prog_words = list(w[0] for w in struct.iter_unpack("<l", prog_bytes))
    for i, word in enumerate(prog_words):
        dut.chip_u.i_chip_core.iram_u.sram.mem[i].value = word
        dut.chip_u.i_chip_core.iram_u.sram.mem[i].value = Release()

    await start_up(dut)
    await twd_connect(dut)

    await rvdebug_init(dut)
    await rvdebug_halt(dut)
    await rvdebug_put_gpr(dut, 8, 0)
    await rvdebug_put_csr(dut, CSR_DPC, IRAM_BASE)
    cocotb.log.info(f"Resuming at {IRAM_BASE:x}")
    await rvdebug_resume(dut)

    vuart_stdout = []
    def test_done():
        if len(vuart_stdout) < 6:
            return False
        endstr = "".join(vuart_stdout[-6:])
        if endstr == "!TPASS":
            return True
        if endstr == "!TFAIL":
            return True
        return False

    while not test_done():
        c = await twd_vuart_getchar(dut, max_poll=10)
        if c is None: break
        sys.stdout.write(chr(c))
        vuart_stdout.append(chr(c))

    sys.stdout.write("\n")
    vuart_stdout = "".join(vuart_stdout)

    assert vuart_stdout.endswith("!TPASS")
    vuart_stdout = vuart_stdout[:-6]

    cocotb.log.info(f"Processor standard output:\n\n{vuart_stdout}\n")
    assert vuart_stdout.strip() == expected_outputs[app], f"Did not match expected output:\n{expected_outputs[app]}"

# Just one of these because after the bootrom runs it's just IRAM execution.
@cocotb.test()
@cocotb.parametrize(app=[
    "hellow"
])
async def test_execute_flash(dut, app="hellow"):
    """Run bootrom, with code loaded into flash. ROM should load code into IRAM then run it."""
    swtest_dir = Path(__file__).resolve().parent.parent / "software/tests/flash"
    rc = subprocess.run(["make", "-C", swtest_dir, f"APP={app}"])
    assert rc.returncode == 0
    with open(swtest_dir / f"build/{app}.padded.bin", "rb") as f:
        prog_bytes = f.read()
    cocotb.log.info(f"Program size = {len(prog_bytes)}")
    for i, b in enumerate(prog_bytes):
        dut.flash_u.mem[i].value = b
        dut.flash_u.mem[i].value = Release()

    await start_up(dut)
    await twd_connect(dut)

    vuart_stdout = []
    def test_done():
        if len(vuart_stdout) < 6:
            return False
        endstr = "".join(vuart_stdout[-6:])
        if endstr == "!TPASS":
            return True
        if endstr == "!TFAIL":
            return True
        return False

    for i in range(5):
        cocotb.log.info(f"Waiting {i} ms")
        await Timer(1, "ms")

    while not test_done():
        c = await twd_vuart_getchar(dut, max_poll=100)
        if c is None: break
        sys.stdout.write(chr(c))
        vuart_stdout.append(chr(c))

    sys.stdout.write("\n")
    vuart_stdout = "".join(vuart_stdout)

    assert vuart_stdout.endswith("!TPASS")
    vuart_stdout = vuart_stdout[:-6]

    cocotb.log.info(f"Processor standard output:\n\n{vuart_stdout}\n")
    if app == "hellow":
        assert vuart_stdout == "Hello, world!\r\n"

###############################################################################
# Test infrastructure

def get_sources_defines_includes():

    proj_path = Path(__file__).resolve().parent
    sources = []
    defines = {}
    includes = []

    # Only used in simulation:
    sources.extend([
        "tb/tb.v",
        "tb/spi_flash_model.v",
        "tb/sram_async.v"
    ])

    defines["GF180MCU"]       = True # Use inserted cells
    defines["BEHAV_SRAM_1RW"] = True # Don't use vendor models (TODO)

    # SCL models: included even for RTL sims, as RTL may instantiate cells in some rare cases
    sources.append(Path(pdk_root) / pdk / "libs.ref" / scl / "verilog" / f"{scl}.v")
    sources.append(Path(pdk_root) / pdk / "libs.ref" / scl / "verilog" / "primitives.v")

    if gl:
        # We use the powered netlist
        sources.append(proj_path / f"../final/pnl/{"tb"}.pnl.v")
        defines["FUNCTIONAL"] = True
        defines["USE_POWER_PINS"] = True
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
        Path(pdk_root) / pdk / "libs.ref/gf180mcu_fd_ip_sram/verilog/gf180mcu_fd_ip_sram__sram256x8m8wm1.v",
        
        # Custom IP
        proj_path / "../ip/gf180mcu_ws_ip__id/vh/gf180mcu_ws_ip__id.v",
        proj_path / "../ip/gf180mcu_ws_ip__logo/vh/gf180mcu_ws_ip__logo.v",
    ]

    return (sources, defines, includes)


if __name__ == "__main__":

    parser = argparse.ArgumentParser()
    parser.add_argument("--filter", help="Optional regex to filter testcases")
    args = parser.parse_args()

    sources, defines, includes = get_sources_defines_includes()

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
        hdl_toplevel="tb",
        defines=defines,
        always=True,
        includes=includes,
        build_args=build_args,
        waves=True,
    )

    plusargs = []

    runner.test(
        hdl_toplevel="tb",
        test_module="chip_top_tb,",
        plusargs=plusargs,
        waves=True,
        test_filter=args.filter
    )
