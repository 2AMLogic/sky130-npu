"""Reference workload generator (spec/npu.md section 8) and file I/O.

Run ``python -m verification.golden.workloads`` from the repo root to
regenerate ``verification/workloads/<id>/``. File formats: ``*.hex`` hold one
value per line, row-major, two's complement, lowercase hex: two
digits for ``a``, ``b`` and ``expected_out``, eight for ``bias``. For conv
workloads ``a.hex`` is the im2col matrix (M x K) and ``b.hex`` the weights
reshaped to K x N, i.e. exactly the GEMM operands the DUT sees.
"""

import json
import sys
from pathlib import Path

from . import conv2d_int8, gemm_int8, im2col, reshape_weights

MASK64 = (1 << 64) - 1
ROOT = Path(__file__).resolve().parent.parent / "workloads"

# id -> (kind, params)
WORKLOADS = {
    "mm-smoke": ("matmul", dict(M=8, K=64, N=8)),
    "mm-fc": ("matmul", dict(M=64, K=256, N=64)),
    "conv-3x3-a": ("conv", dict(H=16, W=16, C=16, KH=3, KW=3, stride=1,
                                pad=1, F=32)),
    "conv-3x3-edge": ("conv", dict(H=14, W=14, C=8, KH=3, KW=3, stride=1,
                                   pad=1, F=20)),
}


class SplitMix64:
    def __init__(self, seed):
        self.state = seed & MASK64

    def next(self):
        self.state = (self.state + 0x9E3779B97F4A7C15) & MASK64
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK64
        return z ^ (z >> 31)


def seed_of(wid):
    return int.from_bytes(wid.encode("ascii")[-8:], "big")


def _int8(rng):
    v = rng.next() & 0xFF
    return v - 256 if v >= 128 else v


def generate(wid):
    """Returns (params dict, a, b, bias, acc, out) for the GEMM operands."""
    kind, p = WORKLOADS[wid]
    rng = SplitMix64(seed_of(wid))
    if kind == "matmul":
        m, k, n = p["M"], p["K"], p["N"]
        a = [[_int8(rng) for _ in range(k)] for _ in range(m)]
        b = [[_int8(rng) for _ in range(n)] for _ in range(k)]
        x = w = None
    else:
        x = [[[_int8(rng) for _ in range(p["C"])] for _ in range(p["W"])]
             for _ in range(p["H"])]
        k = p["KH"] * p["KW"] * p["C"]
        flat = [[_int8(rng) for _ in range(p["F"])] for _ in range(k)]
        w = [[[flat[(i * p["KW"] + j) * p["C"] + c] for c in range(p["C"])]
              for j in range(p["KW"])] for i in range(p["KH"])]
        a = im2col(x, p["KH"], p["KW"], p["stride"], p["pad"])
        b = reshape_weights(w)
        m, n = len(a), p["F"]
    bias = [(rng.next() & 0xFFFF) - 32768 for _ in range(n)]
    mult = 40000 if kind == "conv" else 1
    relu = 1 if kind == "conv" else 0
    t_max = max(abs(v) for row in gemm_int8(a, b, bias, 1, 0, 0)[0]
                for v in row)
    shift = max(0, (t_max * mult).bit_length() - 7)
    if kind == "conv":
        acc, out = conv2d_int8(x, w, bias, p["stride"], p["pad"], mult, shift,
                               relu)
    else:
        acc, out = gemm_int8(a, b, bias, mult, shift, relu)
    params = dict(id=wid, kind=kind, M=m, K=k, N=n, mult=mult, shift=shift,
                  relu=relu, seed=seed_of(wid), **{
                      q: v for q, v in p.items() if q not in ("M", "K", "N")})
    return params, a, b, bias, acc, out


def _hex(values, digits):
    mask = (1 << (4 * digits)) - 1
    return "".join(f"{v & mask:0{digits}x}\n" for v in values)


def files(wid):
    """Map file name -> exact text for one workload."""
    params, a, b, bias, _acc, out = generate(wid)
    flat = lambda mat: [v for row in mat for v in row]
    return {
        "a.hex": _hex(flat(a), 2),
        "b.hex": _hex(flat(b), 2),
        "bias.hex": _hex(bias, 8),
        "params.json": json.dumps(params, indent=2, sort_keys=True) + "\n",
        "expected_out.hex": _hex(flat(out), 2),
    }


def write_all(root=ROOT):
    for wid in WORKLOADS:
        d = Path(root) / wid
        d.mkdir(parents=True, exist_ok=True)
        for name, text in files(wid).items():
            (d / name).write_text(text, newline="\n")


if __name__ == "__main__":
    write_all(Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT)
