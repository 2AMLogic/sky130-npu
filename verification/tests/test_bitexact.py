"""Bit-exact tests of ``npu_top`` against the integer golden model.

Every output byte is compared with ``==``; there is no tolerance anywhere.
Directed workloads are compared to the committed ``expected_out.hex`` and to a
live ``golden.gemm_int8`` call (the live call guards the vectors themselves).
Utilization is recorded per workload, labelled ``simulated``.

Env: ``ARRAY_N`` (4 or 8, set by the runner), ``NPU_SEED`` (random-test seed,
printed and recorded), ``NPU_RANDOM_RUNS`` (random GEMM count, default 8).
"""

import os
import random
import sys
from pathlib import Path

import cocotb
from cocotb.triggers import ClockCycles

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import npu_bench as nb  # noqa: E402
from verification.golden import gemm_int8, requantize  # noqa: E402

SEED = int(os.environ.get("NPU_SEED", random.SystemRandom().getrandbits(32)))
RANDOM_RUNS = int(os.environ.get("NPU_RANDOM_RUNS", "8"))
print(f"NPU_SEED={SEED}")
nb.record_result("seed", SEED)


def first_mismatch(got, want):
    for i, (g, w) in enumerate(zip(got, want)):
        if g != w:
            return i, g, w
    return None


def check(got, want, what):
    """Zero-tolerance matrix compare; fails with the first differing element."""
    assert len(got) == len(want), f"{what}: {len(got)} rows, want {len(want)}"
    for r, (g, w) in enumerate(zip(got, want)):
        mm = first_mismatch(g, w)
        assert mm is None, f"{what}: row {r} col {mm[0]} got {mm[1]} want {mm[2]}"


async def setup(dut):
    bench = nb.Bench(dut)
    await bench.start_clock()
    await bench.reset()
    return bench


async def check_cap_regs(bench):
    assert await bench.read(nb.ID) == 0x4E505530
    cap = await bench.read(nb.CAP)
    assert cap & 0xFF == bench.n, f"CAP.ARRAY_N {cap & 0xFF}"


async def run_workload(dut, wid):
    bench = await setup(dut)
    await check_cap_regs(bench)
    p, a, b, bias, exp = nb.load_workload(wid)
    m, k, n = p["M"], p["K"], p["N"]
    _, live = gemm_int8(a, b, bias, p["mult"], p["shift"], p["relu"])
    check(live, exp, f"{wid}: golden vs committed vectors")
    out, cycles = await bench.run_gemm(a, b, bias, p["mult"], p["shift"], p["relu"])
    check(out, exp, f"{wid} vs expected_out.hex")
    check(out, live, f"{wid} vs live golden")
    nb.record_result(f"workload:{wid}", {
        "array_n": bench.n, "M": m, "K": k, "N": n,
        "perf_cycles": cycles,
        "u_array": nb.utilization(m, k, n, cycles, bench.n),
        "mismatches": 0, "basis": "simulated",
    })


@cocotb.test()
async def test_workload_mm_smoke(dut):
    await run_workload(dut, "mm-smoke")


@cocotb.test()
async def test_workload_mm_fc(dut):
    await run_workload(dut, "mm-fc")


@cocotb.test()
async def test_workload_conv_3x3_a(dut):
    await run_workload(dut, "conv-3x3-a")


@cocotb.test()
async def test_workload_conv_3x3_edge(dut):
    await run_workload(dut, "conv-3x3-edge")


async def gemm_vs_golden(bench, a, b, bias, mult, shift, relu, what):
    out, _ = await bench.run_gemm(a, b, bias, mult, shift, relu)
    _, want = gemm_int8(a, b, bias, mult, shift, relu)
    check(out, want, what)


@cocotb.test()
async def test_requant_edges(dut):
    """Ties, saturation both ways, ReLU on/off, shift 0 and 47 (spec 3.2)."""
    bench = await setup(dut)
    n = bench.n
    # (t, mult, shift, relu): spec 3.2 worked examples plus neighbours.
    cases = [
        (100, 1, 1, 0), (3, 1, 1, 0), (-3, 1, 1, 0), (-1, 1, 1, 0), (1, 1, 1, 0),
        (5, 3, 2, 0), (-5, 3, 2, 0), (1000, 40000, 20, 0),
        (10000, 1, 4, 0), (-10000, 1, 4, 0), (-10000, 1, 4, 1), (10000, 1, 4, 1),
        (2, 1, 2, 0), (-2, 1, 2, 0), (6, 1, 2, 0), (-6, 1, 2, 0),
        (127, 1, 0, 0), (128, 1, 0, 0), (-128, 1, 0, 0), (-129, 1, 0, 0),
        (0, 65535, 47, 0), (2**30 - 1, 65535, 0, 0), (-2**30, 65535, 0, 0),
        (2**30 - 1, 65535, 47, 0), (-2**30, 65535, 47, 0),
        (2**30 - 1, 65535, 47, 1), (-2**30, 65535, 0, 1),
        (2**30 - 1, 0, 0, 0), (12345, 65535, 30, 0), (-12345, 65535, 30, 0),
    ]
    a = [[0] * 1 for _ in range(n)]
    b = [[0] * n]
    for t, mult, shift, relu in cases:
        # K=1, A=B=0 so acc=0 and the requantizer sees exactly t = bias.
        what = f"requant t={t} mult={mult} shift={shift} relu={relu}"
        bias = [t] * n
        out, _ = await bench.run_gemm(a, b, bias, mult, shift, relu)
        _, want = gemm_int8(a, b, bias, mult, shift, relu)
        check(out, want, what)
        scalar = requantize(t, mult, shift, relu)
        assert all(v == scalar for row in out for v in row), f"{what}: != {scalar}"


@cocotb.test()
async def test_k_extremes(dut):
    """K = 1 and K = K_MAX = 256, shift 0 and 47, extreme operand values."""
    bench = await setup(dut)
    n = bench.n
    rng = random.Random(SEED ^ 0xE57)
    for k in (1, 2, 255, 256):
        for shift in (0, 47):
            a = [[rng.choice((-128, 127, rng.randint(-128, 127))) for _ in range(k)]
                 for _ in range(n)]
            b = [[rng.choice((-128, 127, rng.randint(-128, 127))) for _ in range(n)]
                 for _ in range(k)]
            bias = [rng.randint(-2**30, 2**30 - 1) for _ in range(n)]
            await gemm_vs_golden(bench, a, b, bias, 65535, shift, 0,
                                 f"K={k} shift={shift}")
    # all -128 x -128 at K=256: the largest accumulator magnitude (2^22).
    a = [[-128] * 256 for _ in range(n)]
    b = [[-128] * n for _ in range(256)]
    await gemm_vs_golden(bench, a, b, [0] * n, 1, 16, 0, "K=256 all -128")
    await gemm_vs_golden(bench, a, b, [0] * n, 1, 0, 1, "K=256 all -128 shift 0")


@cocotb.test()
async def test_back_to_back(dut):
    """Two tiles with START issued right after the first DONE, different offsets."""
    bench = await setup(dut)
    n, k = bench.n, 16
    rng = random.Random(SEED ^ 0xB2B)
    tiles = []
    for _ in range(2):
        a = [[rng.randint(-128, 127) for _ in range(k)] for _ in range(n)]
        b = [[rng.randint(-128, 127) for _ in range(n)] for _ in range(k)]
        tiles.append((a, b))
    bias = [rng.randint(-5000, 5000) for _ in range(n)]
    await bench.set_bias(bias)
    from verification.golden import pack_a, pack_b
    for i, (a, b) in enumerate(tiles):
        await bench.store_bytes(0, i * k * n, pack_a(a, n))
        await bench.store_bytes(1, i * k * n, pack_b(b, n))
    out_bank, out_base = (2, 0) if n == 8 else (0, 2 * k * n)
    for i in range(2):
        await bench.configure(k, 0, 1, out_bank, i * k * n, i * k * n,
                              out_base + 4 * n * n * i, 3, 9, 0)
        await bench.start()
        st = await bench.wait_done()
        assert st & nb.ST_DONE and not st & nb.ST_ERR, f"tile {i}: STATUS={st:#x}"
        # no STATUS clear: the next START clears DONE itself (spec 6)
    for i, (a, b) in enumerate(tiles):
        raw = await bench.load_bytes(out_bank, out_base + 4 * n * n * i, n * n)
        got = [[nb.to_s8(raw[r * n + c]) for c in range(n)] for r in range(n)]
        _, want = gemm_int8(a, b, bias, 3, 9, 0)
        check(got, want, f"back-to-back tile {i}")


@cocotb.test()
async def test_reset_mid_run(dut):
    """rst while BUSY: idle afterwards, and a following tile is bit-exact."""
    bench = await setup(dut)
    n, k = bench.n, 64
    rng = random.Random(SEED ^ 0x7E5)
    a = [[rng.randint(-128, 127) for _ in range(k)] for _ in range(n)]
    b = [[rng.randint(-128, 127) for _ in range(n)] for _ in range(k)]
    bias = [rng.randint(-1000, 1000) for _ in range(n)]
    from verification.golden import pack_a, pack_b
    await bench.store_bytes(0, 0, pack_a(a, n))
    await bench.store_bytes(1, 0, pack_b(b, n))
    await bench.set_bias(bias)
    lay = bench.layout(k)
    await bench.configure(k, mult=5, shift=8, relu=0, **lay)
    await bench.start()
    await ClockCycles(dut.clk, 20)
    assert await bench.read(nb.STATUS) & nb.ST_BUSY, "expected BUSY before reset"
    await bench.reset()
    st = await bench.read(nb.STATUS)
    assert st == 0, f"STATUS after reset {st:#x}"
    await gemm_vs_golden(bench, a, b, bias, 5, 8, 0, "tile after reset mid-run")


@cocotb.test()
async def test_errors_write_nothing(dut):
    """ERR_CODE 1..5; a rejected START leaves every bank unchanged (spec 6)."""
    bench = await setup(dut)
    n, k = bench.n, 8
    nbanks = 4 if n == 8 else 2
    rng = random.Random(SEED ^ 0xE44)
    from verification.golden import pack_a, pack_b
    a = [[rng.randint(-128, 127) for _ in range(k)] for _ in range(n)]
    b = [[rng.randint(-128, 127) for _ in range(n)] for _ in range(k)]
    await bench.set_bias([0] * n)
    await bench.store_bytes(0, 0, pack_a(a, n))
    await bench.store_bytes(1, 0, pack_b(b, n))
    for bk in range(nbanks):  # sentinel over the whole snapshot window
        await bench.store_bytes(bk, 0, bytes([0xA5]) * 640)
    await bench.store_bytes(0, 0, pack_a(a, n))
    await bench.store_bytes(1, 0, pack_b(b, n))

    async def snapshot():
        return [await bench.load_bytes(bk, 0, 640) for bk in range(nbanks)]

    base = bench.layout(k)
    # (expected ERR_CODE, field overrides)
    cases = [
        (1, dict(k=0)),
        (1, dict(k=257)),
        (2, dict(a_off=1)),
        (2, dict(out_off=2)),
        (2, dict(b_bank=nbanks)),
        (2, dict(a_bank=1)),                       # A_BANK == B_BANK
        (2, dict(a_off=4096 if n == 8 else 2048)), # out of bank
        (3, dict(out_bank=0, out_off=0)),          # result overlaps A
        (3, dict(out_bank=1, out_off=0)),          # result overlaps B
        (4, dict(shift=48)),
        (4, dict(shift=63)),
    ]
    base_cfg = dict(k=k, mult=7, shift=4, relu=0, **base)
    before = await snapshot()
    for code, over in cases:
        cfg = {**base_cfg, **over}
        await bench.configure(**cfg)
        await bench.start()
        st = await bench.wait_done()
        assert st & nb.ST_ERR and not st & nb.ST_DONE, f"{over}: STATUS={st:#x}"
        assert (st >> 8) & 0xF == code, f"{over}: ERR_CODE {(st >> 8) & 0xF}, want {code}"
        await bench.write(nb.STATUS, nb.ST_ERR)
        assert await bench.read(nb.STATUS) == 0, f"{over}: ERR did not clear (RW1C)"
        assert await snapshot() == before, f"{over}: a bank was written on ERR"

    # code 5: START while BUSY; the running tile still completes bit-exactly.
    big = 64
    ab = [[rng.randint(-128, 127) for _ in range(big)] for _ in range(n)]
    bb = [[rng.randint(-128, 127) for _ in range(n)] for _ in range(big)]
    await bench.store_bytes(0, 0, pack_a(ab, n))
    await bench.store_bytes(1, 0, pack_b(bb, n))
    await bench.set_bias([0] * n)  # after the loads: see npu_bench.run_gemm
    lay = bench.layout(big)
    await bench.configure(big, mult=7, shift=4, relu=0, **lay)
    await bench.start()
    await bench.start()
    st = await bench.read(nb.STATUS)
    assert st & nb.ST_BUSY, "tile should still be running"
    st = await bench.wait_done(mask=nb.ST_DONE)
    assert st & nb.ST_ERR and (st >> 8) & 0xF == 5, f"START while BUSY: STATUS={st:#x}"
    raw = await bench.load_bytes(lay["out_bank"], lay["out_off"], n * n)
    got = [[nb.to_s8(raw[r * n + c]) for c in range(n)] for r in range(n)]
    _, want = gemm_int8(ab, bb, [0] * n, 7, 4, 0)
    check(got, want, "tile running through START-while-BUSY")


@cocotb.test()
async def test_constrained_random(dut):
    """Random shapes, parameters and data within spec limits; seed recorded."""
    bench = await setup(dut)
    n = bench.n
    rng = random.Random(SEED)
    done = 0
    for i in range(RANDOM_RUNS):
        m = rng.randint(1, 2 * n + 3)
        nn = rng.randint(1, 2 * n + 3)
        k = rng.choice((1, rng.randint(1, 40), rng.randint(1, 40), 256 if i == 0 else 17))
        hi = rng.choice((3, 127))
        a = [[rng.randint(-hi - 1, hi) for _ in range(k)] for _ in range(m)]
        b = [[rng.randint(-hi - 1, hi) for _ in range(nn)] for _ in range(k)]
        span = rng.choice((100, 2**15, 2**30))
        bias = [rng.randint(-span, span - 1) for _ in range(nn)]
        mult = rng.choice((0, 1, 65535, rng.randint(0, 65535)))
        shift = rng.choice((0, 47, rng.randint(0, 47)))
        relu = rng.randint(0, 1)
        await gemm_vs_golden(
            bench, a, b, bias, mult, shift, relu,
            f"random #{i} seed={SEED} M={m} K={k} N={nn} mult={mult} shift={shift} relu={relu}")
        done += 1
    nb.record_result("random", {"seed": SEED, "gemms": done, "mismatches": 0,
                                "basis": "simulated"})


@cocotb.test()
async def test_bank_window_does_not_alias_bias(dut):
    """A bank-window write must not touch BIAS (spec 6 address map). Fails on
    the current RTL: issue #37.

    BIAS lives at block offset 0x100..0x13C; a bank window starts at 0x1000 *
    (b + 1), so a write to bank offset 0x100 is a different address and must
    leave the BIAS registers alone.
    """
    bench = await setup(dut)
    n = bench.n
    bias = [0x1000 + j for j in range(n)]
    await bench.set_bias(bias)
    for bank in range(2):
        await bench.store_bytes(bank, 0x100, bytes([0xEE]) * (4 * n))
        got = [await bench.read(nb.BIAS_BASE + 4 * j) for j in range(n)]
        assert got == bias, f"bank {bank} write at offset 0x100 changed BIAS: {got}"
