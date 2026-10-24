"""Bench library for ``npu_top``: Wishbone master, tiling, utilization.

PDK-independent: touches only the ``npu_top`` ports and the register map of
spec section 6. The helpers here never compute an expected value; expected
values come from ``verification.golden`` (the tests do the comparing).
"""

import json
import os
import sys
from pathlib import Path

from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from verification.golden import pack_a, pack_b  # noqa: E402

WORKLOADS = Path(__file__).resolve().parents[1] / "workloads"

# Register byte offsets (spec section 6).
ID, SPEC, CAP, CTRL, STATUS, K = 0x00, 0x04, 0x08, 0x0C, 0x10, 0x14
BANKS, A_OFF, B_OFF, OUT_OFF = 0x18, 0x1C, 0x20, 0x24
REQ_MULT, REQ_CTRL, PERF_CYCLES = 0x28, 0x2C, 0x30
BIAS_BASE = 0x100
BANK_BASE = 0x1000  # bank b window at BANK_BASE * (b + 1)

CTRL_START, CTRL_SOFT_RESET, CTRL_IRQ_EN = 1, 2, 4
ST_BUSY, ST_DONE, ST_ERR = 1, 2, 4


class BusError(Exception):
    """The DUT answered a Wishbone access with ERR."""


def array_n():
    return int(os.environ.get("ARRAY_N", "8"))


def to_s8(v):
    return v - 256 if v >= 128 else v


def read_matrix(name, workload, rows, cols, digits=2):
    """Load ``a.hex`` / ``b.hex`` / ``expected_out.hex`` as a rows x cols list."""
    vals = [
        int(x, 16)
        for x in (WORKLOADS / workload / name).read_text().split()
    ]
    assert len(vals) == rows * cols, f"{workload}/{name}: {len(vals)} values"
    vals = [to_s8(v) for v in vals]
    return [vals[r * cols:(r + 1) * cols] for r in range(rows)]


def load_workload(wid):
    import json as _json

    p = _json.loads((WORKLOADS / wid / "params.json").read_text())
    m, k, n = p["M"], p["K"], p["N"]
    a = read_matrix("a.hex", wid, m, k)
    b = read_matrix("b.hex", wid, k, n)
    bias = [
        int(x, 16) - (1 << 32) if int(x, 16) >= 1 << 31 else int(x, 16)
        for x in (WORKLOADS / wid / "bias.hex").read_text().split()
    ]
    assert len(bias) == n
    exp = read_matrix("expected_out.hex", wid, m, n)
    return p, a, b, bias, exp


class Bench:
    """Wishbone master and tile runner around one ``npu_top`` instance."""

    def __init__(self, dut):
        self.dut = dut
        self.n = array_n()
        self.cycles = 0  # PERF_CYCLES summed over every tile run

    # ------------------------------------------------------------------ bus
    async def start_clock(self):
        import cocotb

        self._clk = cocotb.start_soon(Clock(self.dut.clk, 10, unit="ns").start())

    def _idle_bus(self):
        d = self.dut
        d.wb_cyc_i.value = 0
        d.wb_stb_i.value = 0
        d.wb_we_i.value = 0
        d.wb_adr_i.value = 0
        d.wb_dat_i.value = 0
        d.wb_sel_i.value = 0

    async def reset(self, cycles=3):
        self._idle_bus()
        self.dut.rst.value = 1
        await ClockCycles(self.dut.clk, cycles)
        await FallingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await ClockCycles(self.dut.clk, 1)

    async def _xfer(self, adr, we, dat=0, sel=0xF, allow_err=False):
        """One classic cycle: hold STB until ACK or ERR is seen at a clock edge."""
        d = self.dut
        await FallingEdge(d.clk)
        d.wb_cyc_i.value = 1
        d.wb_stb_i.value = 1
        d.wb_we_i.value = 1 if we else 0
        d.wb_adr_i.value = adr
        d.wb_dat_i.value = dat & 0xFFFFFFFF
        d.wb_sel_i.value = sel
        for _ in range(200):
            await RisingEdge(d.clk)
            await FallingEdge(d.clk)  # outputs settled after this edge's update
            ack, err = int(d.wb_ack_o.value), int(d.wb_err_o.value)
            if ack or err:
                data = 0 if (we or err) else int(d.wb_dat_o.value)
                d.wb_cyc_i.value = 0
                d.wb_stb_i.value = 0
                if err and not allow_err:
                    raise BusError(f"ERR at {adr:#06x} we={we}")
                return data, bool(err)
        raise TimeoutError(f"no ACK/ERR at {adr:#06x}")

    async def write(self, adr, dat, sel=0xF):
        await self._xfer(adr, True, dat, sel)

    async def read(self, adr):
        return (await self._xfer(adr, False))[0]

    async def write_err(self, adr, dat=0):
        """Write that must be answered with ERR; returns True if it was."""
        return (await self._xfer(adr, True, dat, allow_err=True))[1]

    async def read_err(self, adr):
        return (await self._xfer(adr, False, allow_err=True))[1]

    # ---------------------------------------------------------------- banks
    def bank_addr(self, bank, off):
        return BANK_BASE * (bank + 1) + off

    async def store_bytes(self, bank, off, data):
        assert off % 4 == 0 and len(data) % 4 == 0
        for i in range(0, len(data), 4):
            word = int.from_bytes(data[i:i + 4], "little")
            await self.write(self.bank_addr(bank, off + i), word)

    async def load_bytes(self, bank, off, length):
        out = bytearray()
        for i in range(0, length, 4):
            out += (await self.read(self.bank_addr(bank, off + i))).to_bytes(4, "little")
        return bytes(out)

    # ----------------------------------------------------------- operations
    async def configure(self, k, a_bank, b_bank, out_bank, a_off, b_off, out_off,
                        mult, shift, relu):
        await self.write(K, k)
        await self.write(BANKS, a_bank | (b_bank << 8) | (out_bank << 16))
        await self.write(A_OFF, a_off)
        await self.write(B_OFF, b_off)
        await self.write(OUT_OFF, out_off)
        await self.write(REQ_MULT, mult)
        await self.write(REQ_CTRL, shift | (int(bool(relu)) << 8))

    async def set_bias(self, bias):
        for j in range(self.n):
            await self.write(BIAS_BASE + 4 * j, bias[j] if j < len(bias) else 0)

    async def start(self):
        await self.write(CTRL, CTRL_START)

    async def wait_done(self, mask=ST_DONE | ST_ERR, limit=20000):
        """Poll STATUS until a ``mask`` bit is set; return STATUS (not cleared).

        Waits on DONE/ERR rather than on BUSY clearing: BUSY is not yet visible
        in the first STATUS read after START, so "not BUSY" would return early;
        the same read can still show the previous operation's DONE/ERR, which
        START clears one cycle late, so give START two cycles to take effect.
        """
        await ClockCycles(self.dut.clk, 2)
        for _ in range(limit):
            st = await self.read(STATUS)
            if st & mask:
                return st
        raise TimeoutError(f"STATUS never showed {mask:#x}")

    def layout(self, k):
        """Bank plan: A bank 0, B bank 1; result in bank 2 (N=8) or beside A (N=4)."""
        nbanks = 4 if self.n == 8 else 2
        out_bank, out_off = (2, 0) if nbanks > 2 else (0, k * self.n)
        return dict(a_bank=0, b_bank=1, out_bank=out_bank, a_off=0, b_off=0,
                    out_off=out_off)

    async def run_tile(self, k, mult, shift, relu, lay=None):
        """START the configured tile, wait for DONE, return PERF_CYCLES."""
        lay = lay or self.layout(k)
        await self.configure(k, mult=mult, shift=shift, relu=relu, **lay)
        await self.start()
        st = await self.wait_done()
        if not st & ST_DONE or st & ST_ERR:
            raise AssertionError(f"tile did not complete cleanly: STATUS={st:#x}")
        await self.write(STATUS, ST_DONE)
        cyc = await self.read(PERF_CYCLES)
        self.cycles += cyc
        return cyc

    async def run_gemm(self, a, b, bias, mult, shift, relu):
        """Whole GEMM, tiled to ARRAY_N; returns (out M x N int8, summed cycles).

        Loads B once per column tile and A per row tile, serialized
        load-then-compute (valid at every K up to K_MAX, spec 2 / 5.3). Edge
        tiles are zero padded (spec 4); padding is stripped from the result.
        """
        n = self.n
        m_total, k, n_total = len(a), len(b), len(bias)
        out = [[0] * n_total for _ in range(m_total)]
        total_cycles = 0
        for n0 in range(0, n_total, n):
            nn = min(n, n_total - n0)
            b_tile = [row[n0:n0 + nn] for row in b]
            await self.set_bias(bias[n0:n0 + nn])
            await self.store_bytes(1, 0, pack_b(b_tile, n))
            for m0 in range(0, m_total, n):
                mm = min(n, m_total - m0)
                await self.store_bytes(0, 0, pack_a(a[m0:m0 + mm], n))
                lay = self.layout(k)
                total_cycles += await self.run_tile(k, mult, shift, relu, lay)
                raw = await self.load_bytes(lay["out_bank"], lay["out_off"], n * n)
                for i in range(mm):
                    for j in range(nn):
                        out[m0 + i][n0 + j] = to_s8(raw[i * n + j])
        return out, total_cycles


# ---------------------------------------------------------------- ledger hand-off
_results = {}


def record_result(key, value):
    """Add one entry to the run's results and rewrite the hand-off file.

    The runner folds this file into the ledger record (``results``). The
    ``basis`` of every entry is ``simulated``.
    """
    _results[key] = value
    path = os.environ.get("NPU_RESULTS_FILE")
    if path:
        Path(path).write_text(json.dumps(_results, indent=2, sort_keys=True) + "\n")


def utilization(m, k, n, cycles, array):
    """U_array of spec section 8; edge-padded tiles count only useful MACs."""
    return (m * k * n) / (cycles * array * array)
