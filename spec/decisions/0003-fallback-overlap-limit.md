# 0003: Fallback fill/compute overlap is limited to K <= 254

Status: accepted on merge. Clarifies spec sections 2 and 5.2; relaxes nothing.

## Problem

At `ARRAY_N = 4` (2 banks x 2 KB) there is no ping-pong bank. The host fills
the next A tile at a different offset in the same bank while the array computes
(section 2), and the result tile sits in bank 0 beside the A tile (section 5.2).
The bank then holds the current A tile, the next A tile and the result tile:

    2 x (K x 4) + 16 = 8K + 16 bytes  <=  2048   ->   K <= 254

| K | bytes needed | fits 2048 B |
|---|---|---|
| 254 | 2048 | yes (exactly) |
| 255 | 2056 | no |
| 256 | 2064 | no |

Correctness is unaffected. Only fill/compute overlap, and so array
utilization, is.

## Options

| Option | Assessment |
|---|---|
| State the limit; serialize the load at `K` of 255 or 256 | Chosen. Spec text only. |
| Lower the fallback `K_MAX` to 254 | Rejected. `K_MAX` is shared with the target and with the golden model's `1 <= K <= K_MAX` contract; changing it for two K values is not worth that. |
| Add a bank or otherwise redesign fallback buffering | Out of scope; changes the ratified bank plan. |

## Decision

At the fallback, fill/compute overlap holds only for `K <= 254`. For `K` of 255
or 256 the host loads the next tile after the current tile's compute has
finished. Results are bit-identical. `K_MAX`, the `CAP` register and the golden
model interface are unchanged.

## Consequences

- Any fallback utilization figure quoted at `K >= 255` (for example a 4 x 4
  run of `mm-fc`, which has `K = K_MAX = 256`) must come from simulation with
  the serialized load, per the throughput-honesty rule (section 8).
- Target (`ARRAY_N = 8`) reference workloads are unaffected.
