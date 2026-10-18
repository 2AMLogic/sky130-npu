# golden

The bit-exact integer golden model for `spec/npu.md` sections 3 and 4. Every
RTL result is compared to it with `==`; there is no tolerance anywhere.

**PDK-independent, stamped into `asap7-npu`.** Nothing here references sky130,
a simulator or an RTL signal. `asap7-npu` pins it by commit via
`reuse.lock.json`. Do not fork it there; change it here.

- Plain Python `int` only: no numpy, no floats, no dependencies.
- `__init__.py`: `gemm_acc`, `requantize`, `gemm_int8`, `im2col`,
  `conv2d_int8`, `pack_a`, `pack_b` (spec section 4), plus `conv2d_direct`
  (nested-loop reference used by tests) and `reshape_weights`.
  `ARRAY_N` is a parameter of `pack_a`/`pack_b` only.
- `workloads.py`: SplitMix64 generator for the four reference workloads
  (spec section 8) and the writer for `verification/workloads/<id>/`.

Regenerate the committed vectors from the repo root (a test checks they are
byte-identical to the committed files):

```sh
PYTHONPATH=. python3 -m verification.golden.workloads
```

Vector files: one value per line, row-major, two's complement lowercase hex
(two digits for `a`, `b`, `expected_out`; eight for `bias`). For conv
workloads `a.hex` is the im2col matrix (M x K), generated from the input
tensor drawn row-major, and `b.hex` is the weights reshaped to K x N.

Tests: `python3 -m unittest discover -s verification/tests -p 'test_golden.py'`.
