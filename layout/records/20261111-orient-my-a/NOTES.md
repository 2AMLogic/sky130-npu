# 20261111-orient-my-a -- lever 1 (orientation): A banks mirrored MY

Result: NOT routed. `stage_reached` < route; `GRT-0116 Global routing finished
with congestion`. No GDS.

Lever changed vs `20261107-route-congestion` attempt 2: macros `g_bank[0]` and
`g_bank[1]` (A banks, west) orientation `R0` -> `MY` so the macro's west-edge
pins face the array. Nothing else changed (die 2700 x 1410, halo 5, seed 1).

| Attempt | Lever | Total GRT congestion cells | Max H / Max V |
|---|---|---|---|
| 20261107 attempt 2 | baseline (all R0) | 4464 | n/a |
| this | A banks MY | 4666 | 6 / 9 |

Conclusion: mirroring the A banks does not reduce congestion (4666 vs 4464, a
4 % increase, within what a placement change can do). Reverted in the next attempt.
