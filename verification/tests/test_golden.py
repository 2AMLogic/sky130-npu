"""Unit tests for the integer golden model (spec/npu.md sections 3, 4, 8).

Plain ``unittest`` (no extra dependency). Run from the repo root:
``python -m unittest discover -s verification/tests -p 'test_golden.py'``.
Every assertion is an exact integer comparison.
"""

import random
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from verification.golden import (  # noqa: E402
    conv2d_direct, conv2d_int8, gemm_acc, gemm_int8, im2col, pack_a, pack_b, requantize)
from verification.golden import workloads  # noqa: E402
from verification.golden.workloads import SplitMix64  # noqa: E402

# spec/npu.md section 3.2: (t, mult, shift, relu, p, out)
SPEC_ROWS = [
    (100, 1, 1, 0, 100, 50),
    (3, 1, 1, 0, 3, 2),
    (-3, 1, 1, 0, -3, -1),
    (-1, 1, 1, 0, -1, 0),
    (5, 3, 2, 0, 15, 4),
    (-5, 3, 2, 0, -15, -4),
    (1000, 40000, 20, 0, 40000000, 38),
    (10000, 1, 4, 0, 10000, 127),
    (-10000, 1, 4, 0, -10000, -128),
    (-10000, 1, 4, 1, -10000, 0),
    (2147483647, 65535, 0, 0, 140735340806145, 127),
    (-2147483648, 65535, 0, 0, -140735340871680, -128),
    (2147483647, 65535, 47, 0, 140735340806145, 1),
    (-2147483648, 65535, 47, 0, -140735340871680, -1),
]


class Requantize(unittest.TestCase):
    def test_spec_worked_examples(self):
        for t, mult, shift, relu, p, out in SPEC_ROWS:
            with self.subTest(t=t, mult=mult, shift=shift, relu=relu):
                self.assertEqual(t * mult, p)
                self.assertEqual(requantize(t, mult, shift, relu), out)

    def test_round_half_up_ties(self):
        # x / 2 for odd x: ties go toward +infinity, not away from zero.
        for t, want in [(1, 1), (3, 2), (-1, 0), (-3, -1), (-5, -2), (5, 3)]:
            self.assertEqual(requantize(t, 1, 1, 0), want)

    def test_saturation_both_ends(self):
        self.assertEqual(requantize(127, 1, 0, 0), 127)
        self.assertEqual(requantize(128, 1, 0, 0), 127)
        self.assertEqual(requantize(-128, 1, 0, 0), -128)
        self.assertEqual(requantize(-129, 1, 0, 0), -128)

    def test_shift_zero_has_no_rounding_term(self):
        self.assertEqual(requantize(7, 3, 0, 0), 21)

    def test_nested_shape_preserved(self):
        self.assertEqual(requantize([[3, -3], [100, 0]], 1, 1, 0),
                         [[2, -1], [50, 0]])

    def test_argument_ranges(self):
        for bad in [(0, 65536, 0, 0), (0, -1, 0, 0), (0, 1, 48, 0),
                    (0, 1, -1, 0), (2**31, 1, 0, 0), (-2**31 - 1, 1, 0, 0)]:
            with self.assertRaises(ValueError):
                requantize(*bad)

    def test_matches_rational_definition(self):
        # independent check: floor(t*mult/2^shift + 1/2) via integer fractions
        rng = random.Random(1)
        for _ in range(2000):
            t = rng.randrange(-2**31, 2**31)
            mult, shift = rng.randrange(65536), rng.randrange(48)
            relu = rng.randrange(2)
            num, den = 2 * t * mult + (1 << shift), 2 << shift
            want = max(min(num // den, 127), -128)
            if relu:
                want = max(min(max(num // den, 0), 127), -128)
            self.assertEqual(requantize(t, mult, shift, relu), want)


class Gemm(unittest.TestCase):
    def test_small_known(self):
        acc, out = gemm_int8([[1, 2], [3, 4]], [[5, 6], [7, 8]], [10, -10],
                             1, 0, 0)
        self.assertEqual(acc, [[29, 12], [53, 40]])
        self.assertEqual(out, [[29, 12], [53, 40]])

    def test_accumulator_extremes(self):
        k = 256
        for av, bv, want in [(-128, -128, 2**22), (-128, 127, -128 * 127 * k),
                             (127, 127, 127 * 127 * k)]:
            acc = gemm_acc([[av] * k], [[bv] for _ in range(k)], [0])
            self.assertEqual(acc, [[want]])
        self.assertEqual(
            gemm_acc([[-128] * k], [[-128] for _ in range(k)], [2**30 - 1]),
            [[2**22 + 2**30 - 1]])
        self.assertLess(2**22 + 2**30 - 1, 2**31)

    def test_input_contract(self):
        with self.assertRaises(ValueError):
            gemm_acc([[128]], [[1]], [0])
        with self.assertRaises(ValueError):
            gemm_acc([[1]], [[1]], [2**30])
        with self.assertRaises(ValueError):
            gemm_acc([[1] * 257], [[1]] * 257, [0])


def _rand_conv(rng, h, w, c, kh, kw, f):
    x = [[[rng.randint(-128, 127) for _ in range(c)] for _ in range(w)]
         for _ in range(h)]
    wt = [[[[rng.randint(-128, 127) for _ in range(f)] for _ in range(c)]
           for _ in range(kw)] for _ in range(kh)]
    return x, wt, [rng.randint(-2**30, 2**30 - 1) for _ in range(f)]


class Conv(unittest.TestCase):
    def test_conv_equals_gemm_equals_direct(self):
        rng = random.Random(5)
        for h, w, c, kh, kw, f, stride, pad in [
                (5, 4, 3, 3, 3, 5, 1, 1), (6, 6, 2, 3, 2, 3, 2, 0),
                (4, 5, 1, 1, 1, 2, 1, 0), (5, 5, 2, 3, 3, 4, 2, 2)]:
            x, wt, bias = _rand_conv(rng, h, w, c, kh, kw, f)
            got = conv2d_int8(x, wt, bias, stride, pad, 40000, 24, 1)
            ref = conv2d_direct(x, wt, bias, stride, pad, 40000, 24, 1)
            self.assertEqual(got, ref)

    def test_edge_workload_three_ways(self):
        wid = "conv-3x3-edge"
        _kind, p = workloads.WORKLOADS[wid]
        rng = SplitMix64(workloads.seed_of(wid))
        i8 = lambda: (lambda v: v - 256 if v >= 128 else v)(rng.next() & 255)
        x = [[[i8() for _ in range(p["C"])] for _ in range(p["W"])]
             for _ in range(p["H"])]
        flat = [[i8() for _ in range(p["F"])]
                for _ in range(p["KH"] * p["KW"] * p["C"])]
        wt = [[[flat[(i * 3 + j) * p["C"] + c] for c in range(p["C"])]
               for j in range(3)] for i in range(3)]
        bias = [(rng.next() & 0xFFFF) - 32768 for _ in range(p["F"])]
        params = workloads.generate(wid)[0]
        self.assertEqual((params["M"], params["N"]), (196, 20))
        self.assertNotEqual(params["M"] % 8, 0)
        self.assertNotEqual(params["N"] % 8, 0)
        args = (1, 1, params["mult"], params["shift"], params["relu"])
        viaconv = conv2d_int8(x, wt, bias, *args)
        self.assertEqual(viaconv, gemm_int8(im2col(x, 3, 3, 1, 1),
                                            workloads.reshape_weights(wt),
                                            bias, *args[2:]))
        self.assertEqual(viaconv, conv2d_direct(x, wt, bias, *args))
        self.assertEqual(viaconv[1], workloads.generate(wid)[5])

    def test_im2col_layout(self):
        x = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]]  # H=W=2, C=2
        a = im2col(x, 2, 2, 1, 0)
        self.assertEqual(a, [[1, 2, 3, 4, 5, 6, 7, 8]])
        a = im2col(x, 2, 2, 1, 1)  # 3x3 outputs, zero padding
        self.assertEqual(len(a), 9)
        self.assertEqual(a[0], [0, 0, 0, 0, 0, 0, 1, 2])
        self.assertEqual(a[8], [7, 8, 0, 0, 0, 0, 0, 0])


class Pack(unittest.TestCase):
    def test_pack_a_b_layout(self):
        a = [[1, 2, 3], [-1, -2, -3]]  # M=2, K=3
        self.assertEqual(pack_a(a, 4), bytes([1, 255, 0, 0, 2, 254, 0, 0,
                                              3, 253, 0, 0]))
        b = [[1, 2], [3, -4], [5, 6]]  # K=3, N=2
        self.assertEqual(pack_b(b, 4), bytes([1, 2, 0, 0, 3, 252, 0, 0,
                                              5, 6, 0, 0]))

    def test_oversize_rejected(self):
        with self.assertRaises(ValueError):
            pack_b([[1, 2, 3]], 2)


class Workloads(unittest.TestCase):
    def test_splitmix64_known_vector(self):
        # reference values for seed 0 (Vigna's splitmix64.c)
        rng = SplitMix64(0)
        self.assertEqual([rng.next() for _ in range(2)],
                         [0xE220A8397B1DCDAF, 0x6E789E6AA1B965F4])

    def test_seed_uses_last_eight_bytes(self):
        self.assertEqual(workloads.seed_of("conv-3x3-edge"),
                         int.from_bytes(b"3x3-edge", "big"))
        self.assertEqual(workloads.seed_of("mm-fc"),
                         int.from_bytes(b"mm-fc", "big"))

    def test_params_rules(self):
        for wid, (kind, _p) in workloads.WORKLOADS.items():
            params = workloads.generate(wid)[0]
            self.assertEqual(params["mult"], 40000 if kind == "conv" else 1)
            self.assertEqual(params["relu"], 1 if kind == "conv" else 0)
            self.assertTrue(0 <= params["shift"] <= 47)

    def test_shapes_match_spec(self):
        want = {"mm-smoke": (8, 64, 8), "mm-fc": (64, 256, 64),
                "conv-3x3-a": (256, 144, 32), "conv-3x3-edge": (196, 72, 20)}
        for wid, mkn in want.items():
            p = workloads.generate(wid)[0]
            self.assertEqual((p["M"], p["K"], p["N"]), mkn)

    def test_committed_files_regenerate_byte_identically(self):
        with tempfile.TemporaryDirectory() as tmp:
            workloads.write_all(tmp)
            for wid in workloads.WORKLOADS:
                for name in ("a.hex", "b.hex", "bias.hex", "params.json",
                             "expected_out.hex"):
                    got = (Path(tmp) / wid / name).read_bytes()
                    committed = (workloads.ROOT / wid / name).read_bytes()
                    self.assertEqual(got, committed, f"{wid}/{name}")

    def test_committed_expected_out_matches_independent_gemm(self):
        for wid in ("mm-smoke", "mm-fc"):
            d = workloads.ROOT / wid
            import json
            p = json.loads((d / "params.json").read_text())

            def ints(name, bits):
                return [int(s, 16) - ((1 << bits) if int(s, 16) >> (bits - 1)
                                      else 0)
                        for s in (d / name).read_text().split()]
            a, b = ints("a.hex", 8), ints("b.hex", 8)
            bias, out = ints("bias.hex", 32), ints("expected_out.hex", 8)
            for m in range(p["M"]):
                for n in range(p["N"]):
                    t = bias[n] + sum(a[m * p["K"] + k] * b[k * p["N"] + n]
                                      for k in range(p["K"]))
                    self.assertEqual(
                        requantize(t, p["mult"], p["shift"], p["relu"]),
                        out[m * p["N"] + n])


if __name__ == "__main__":
    unittest.main()
