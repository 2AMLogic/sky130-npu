# 20261111-wider-channel -- lever 2: wider B-bank channels

**Provenance of congestion counts: NOT RE-DERIVED.** The figures below were read
from the OpenROAD/GRT console during the run. The logs and
`npu_top_route_metrics.json` lived under `layout/build/` (not committed); the surviving local copy holds no route-stage counts, and
`par.json`/`par.err` in this record carry no counts (only
`GRT-0116`). Treat every count as an unverified reading, not evidence; the only
sourced fact here is that the run did not route (`GRT-0116`, no GDS).

Result: NOT routed. `GRT-0116`; no GDS.

Lever changed vs `20261107-route-congestion` attempt 2 (orientation back to R0,
the MY attempt `20261111-orient-my-a` did not help): B banks moved apart,
`x_um` 725 -> 760 and 1440 -> 1560 (gap between B0 and B1 15 -> 100 um, B0 from
A banks 14 -> 49 um), die 2700 -> 2800 um wide.

| Attempt | Lever | Total GRT congestion cells | Max H / Max V |
|---|---|---|---|
| 20261107 attempt 2 | baseline | 4464 | n/a |
| 20261111-orient-my-a | A banks MY | 4666 | 6 / 9 |
| this | wider B channels | 3229 | 3 / 3 |

Congestion falls 28 % versus baseline; kept as the base for the next lever (halo).
