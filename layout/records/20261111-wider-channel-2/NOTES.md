# 20261111-wider-channel-2 -- lever 2 pushed further

Result: NOT routed (`GRT-0116`); no GDS.

Lever changed vs `20261111-wider-channel` (halo field removed, it is ignored by
klt 0.8.0): B banks `x_um` 760 -> 800 and 1560 -> 1750, die 2800 -> 3000 um wide.

| Attempt | Lever | Total GRT congestion cells | Max H / Max V |
|---|---|---|---|
| 20261107 attempt 2 | baseline | 4464 | n/a |
| 20261111-orient-my-a | A banks MY | 4666 | 6 / 9 |
| 20261111-wider-channel | B channels 2800 wide | 3229 | 3 / 3 |
| 20261111-halo-25 | halo (ignored by klt) | 3229 | 3 / 3 |
| this | B channels 3000 wide | 3335 | 5 / 3 |

Wider is not monotonic: the best controllable result is 3229 cells and the
overflow sits at macro pin edges where the LEF obstructs met1-met4. Orientation
and channel width are exhausted; halo and placement density cannot be set
through the klt 0.8.0 request. Routing is not closed.
