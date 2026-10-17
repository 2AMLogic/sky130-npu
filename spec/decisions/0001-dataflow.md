# 0001: Dataflow is output-stationary

Status: accepted on merge. Supersedes the README draft row "weight-stationary
systolic (to ratify)".

## Context

The block is SRAM-bound. The macros offered by the candidate source
([0002](0002-sram-source.md)) are 32-bit, 1rw1r. Candidates for the 8 x 8 array:
weight-stationary (WS), output-stationary (OS), row-stationary (RS).

## Bandwidth arithmetic at 8 x 8 (per cycle, steady state)

Word = 32 bit. The array does 64 MACs per cycle.

| Dataflow | SRAM reads | SRAM writes | Notes |
|---|---|---|---|
| WS | 8 B A (2 words) | INT32 partial sums: 8 columns x 4 B = 32 B (8 words) per cycle | Weights held in PEs, reloaded per K-tile of 8. With `K > 8`, partial sums are read-modify-written: another 8 words read per cycle. Total about 18 words/cycle. |
| OS | 8 B A + 8 B B = 4 words | INT8 outputs: 64 B per tile = 16 words per `K` cycles | Accumulators live in the PEs for all K; only the final tile result leaves. |
| RS | between the two | between the two | More control and a larger PE buffer; no bandwidth advantage over OS at this size. |

One 1rw1r 32-bit bank supplies 2 words/cycle. WS needs about 9 banks of
bandwidth just for partial sums, against a 4-bank budget. OS needs 4 words/cycle
for operands, which is exactly 2 banks, doubled to 4 for ping-pong
(spec section 2). OS also keeps the INT32 accumulator out of SRAM entirely, so
bank width is 32 bits and the output is already INT8 when it is written.

## Decision

Output-stationary. The array consumes one A vector and one B vector per cycle;
accumulators are drained, biased and requantized once per tile.

## Consequences

- The README's "weight-stationary" is replaced; the README target table is
  updated by the same PR.
- Cost accepted: there are no resident weights, so B is re-read per tile; this
  is paid for in the 4 words/cycle above, which the 4-bank plan covers.
- Cost accepted: drain stalls the array unless a shadow accumulator is added.
  Measured through `U_array` (spec section 8), decided in RTL.
- `K` is bounded by `K_MAX = 256` because accumulation does not leave the PE
  (spec section 9).
- Not measured: all numbers here are derived from port counts, not from a
  simulation or a macro datasheet.
