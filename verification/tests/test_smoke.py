"""Smoke test: reset, clocking and a scoreboard against the placeholder DUT.

The DUT is a registered pass-through, so the scoreboard's expected value is the
input from the previous clock edge. This is a stand-in model; the bit-exact
golden model plugs in via ``verification/golden`` (#3).
"""

import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer

WIDTH = int(os.environ.get("WIDTH", "8"))
MASK = (1 << WIDTH) - 1


async def reset(dut, cycles=2):
    dut.rst.value = 1
    dut.d.value = 0
    await ClockCycles(dut.clk, cycles)
    dut.rst.value = 0


@cocotb.test()
async def test_reset_clock_scoreboard(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.d.value = MASK  # nonzero data while in reset must not leak through
    dut.rst.value = 1
    await ClockCycles(dut.clk, 3)
    await Timer(1, unit="ns")
    assert int(dut.q.value) == 0, "q must be 0 during reset"
    await reset(dut)

    rng = random.Random(7)
    expected = 0  # value q must show after the next edge
    mismatches = []
    for cycle in range(64):
        value = rng.getrandbits(WIDTH)
        dut.d.value = value
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        got = int(dut.q.value)
        if got != value:
            mismatches.append((cycle, value, got))
        expected = value
    assert not mismatches, f"scoreboard mismatches (cycle, exp, got): {mismatches[:5]}"
    assert expected == int(dut.q.value)
