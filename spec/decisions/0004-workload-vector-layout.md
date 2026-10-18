# 0004: Workload vector layout (conv draw order, file format)

Status: accepted on merge. Clarifies spec section 8; relaxes nothing and
changes no committed vector.

## Problem

Section 8 pins the generator (SplitMix64, draw order "`A` row-major, `B`
row-major, then `bias`") but not what `A` is for `conv-*` workloads (the input
tensor `H x W x C`, or the im2col matrix `M x K`), nor the format of the five
files it names. The RTL testbench and the `asap7-npu` port could each read the
committed vectors differently and still believe they are bit-exact.

## Decision

This records what the generator already does (`verification/golden/workloads.py`,
PR #20). Every item below was checked against that code and against a
regeneration of all four workloads, which is byte-identical to the committed
files.

1. **Draw order.**
   - `mm-*`: `A` (`M x K`, row-major), `B` (`K x N`, row-major, `b[k][n]`),
     `bias` (`N` draws). Unchanged.
   - `conv-*`: input tensor `x[H][W][C]` (row-major, `C` fastest), then
     weights as a flat `K x F` block `flat[k][f]` with
     `k = (i*KW + j)*C + c` (`i` kernel row, `j` kernel column, `c` input
     channel), then `bias` (`F` draws). `K = KH*KW*C`.
2. **GEMM operands in the files.** `a.hex` always holds the GEMM operand `A`,
   and `b.hex` the operand `B` (`K x N`). For `conv-*`, `A` is the im2col matrix
   (`M x K`), not the input tensor: row `m = oh*OW + ow`, columns ordered
   `(i, j, c)` with `c` fastest, and positions that fall in the padding are
   written as `00`. `B` is the flat `K x F` weight block from item 1
   (`N = F`). `expected_out.hex` is `M x N`, row-major.
3. **`.hex` format.** One value per line, row-major, two's complement,
   lowercase hex, each line ending in `\n` (including the last). Two digits for
   `a.hex`, `b.hex` and `expected_out.hex`; eight digits for `bias.hex`. The
   files hold exactly `M*K`, `K*N`, `N` and `M*N` values, with no padding to a
   multiple of `ARRAY_N`; padding is a tile-time concern.
4. **`params.json` keys.** A JSON object with sorted keys, 2-space indent and a
   trailing newline. Every workload has `id`, `kind` (`matmul` or `conv`), `M`,
   `K`, `N`, `mult`, `shift`, `relu` and `seed` (the integer value of the
   generator seed). `conv` workloads add `H`, `W`, `C`, `KH`, `KW`, `stride`,
   `pad` and `F`. `matmul` workloads have no other keys.

Worked check, `conv-3x3-edge` (`H=W=14, C=8, 3x3, stride 1, pad 1, F=20`):
`M=196`, `K=72`, `N=20`; `a.hex` has 14112 lines (196 x 72), `b.hex` 1440
(72 x 20), `bias.hex` 20, `expected_out.hex` 3920 (196 x 20).

## Consequences

- The testbench and the port read `a.hex` and `b.hex` as GEMM operands directly
  and never re-run im2col.
- A port that regenerates vectors must reproduce the item 1 draw order, or the
  committed vectors will not match.
- No generator, vector, golden-model or `K_MAX` change.
