"""Regression: a bank-window write at offset 0x100-0x13F must not touch BIAS.

Spec section 6 puts BIAS at block offsets 0x0100-0x013C of the register block
only. The bank window for bank b sits at 0x1000 * (b + 1), so bank offsets
0x100..0x13F share adr[11:6] with BIAS and must not decode as BIAS.
"""

import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer

ARRAY_N = int(os.environ.get("ARRAY_N", "8"))
NBANKS = 2 if ARRAY_N == 4 else 4


async def wb(dut, adr, dat=0, we=False, sel=0xF):
    """One Wishbone classic cycle; returns (dat_o, err)."""
    dut.wb_cyc_i.value = 1
    dut.wb_stb_i.value = 1
    dut.wb_we_i.value = int(we)
    dut.wb_adr_i.value = adr
    dut.wb_dat_i.value = dat
    dut.wb_sel_i.value = sel
    for _ in range(64):
        await RisingEdge(dut.clk)
        await Timer(1, unit="step")  # let registered outputs settle
        if int(dut.wb_ack_o.value) or int(dut.wb_err_o.value):
            break
    else:
        raise AssertionError(f"no ACK/ERR for adr {adr:#06x}")
    err = bool(int(dut.wb_err_o.value))
    got = (0 if we or err else int(dut.wb_dat_o.value), err)
    dut.wb_cyc_i.value = 0
    dut.wb_stb_i.value = 0
    dut.wb_we_i.value = 0
    await RisingEdge(dut.clk)
    return got


async def start(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="step").start())
    dut.wb_cyc_i.value = 0
    dut.wb_stb_i.value = 0
    dut.rst.value = 1
    await ClockCycles(dut.clk, 3)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)


@cocotb.test()
async def test_bank_window_does_not_alias_bias(dut):
    await start(dut)

    bias = [0x11111111 * (i + 1) & 0xFFFFFFFF for i in range(ARRAY_N)]
    for i, v in enumerate(bias):
        await wb(dut, 0x0100 + 4 * i, v, we=True)

    # Neighbours of the BIAS range and every word inside it, in every bank.
    offsets = [0x0FC, 0x100, 0x104, 0x13C, 0x140]
    for b in range(NBANKS):
        base = 0x1000 * (b + 1)
        for k, off in enumerate(offsets):
            val = 0xEE000000 | (b << 16) | (k << 8) | 0xA5
            _, err = await wb(dut, base + off, val, we=True)
            assert not err, f"bank {b} write at {off:#x} returned ERR"
            got, err = await wb(dut, base + off)
            assert not err and got == val, (
                f"bank {b} off {off:#x}: wrote {val:#010x}, read {got:#010x}"
            )

    for i, v in enumerate(bias):
        got, _ = await wb(dut, 0x0100 + 4 * i)
        assert got == v, f"BIAS[{i}] changed by bank write: {v:#010x} -> {got:#010x}"
