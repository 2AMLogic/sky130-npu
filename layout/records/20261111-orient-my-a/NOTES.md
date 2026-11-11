# 20261111-orient-my-a -- lever 1 (orientation): A banks mirrored MY

**Provenance of congestion counts: NOT RE-DERIVED.** The figures below were read
from the OpenROAD/GRT console during the run. The logs and
`npu_top_route_metrics.json` lived under `layout/build/` (not committed); the surviving local copy holds no route-stage counts, and
`par.json`/`par.err` in this record carry no counts (only
`GRT-0116`). Treat every count as an unverified reading, not evidence; the only
sourced fact here is that the run did not route (`GRT-0116`, no GDS).

Result: NOT routed. `stage_reached` < route; `GRT-0116 Global routing finished
with congestion`. No GDS.

Lever changed vs `20261107-route-congestion` attempt 2: macros `g_bank[0]` and
`g_bank[1]` (A banks, west) orientation `R0` -> `MY` so the macro's west-edge
pins face the array. Nothing else changed (die 2700 x 1410, halo 5, seed 1).

| Attempt | Lever | Total GRT congestion cells | Max H / Max V |
|---|---|---|---|
| 20261107 attempt 2 | baseline (all R0) | 4464 | n/a |
| this | A banks MY | 4666 | 6 / 9 |

Conclusion (unverified counts, see provenance note): mirroring the A banks did
not visibly reduce congestion (reading 4666 vs 4464). Reverted in the next attempt.
