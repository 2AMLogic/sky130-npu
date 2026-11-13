# 20261111-sandwich -- the one settled attempt: logic band between two macro rows

Result: NOT routed. `stage_reached` < route; `GRT-0116 Global routing finished
with congestion` (`par.json`, `par.err`). No GDS. Single local run, klt 0.9.1,
OpenROAD 26Q3-1510-g6cb3f2b704 (`tool-versions.txt`).

## Lever (vs `20261111-wider-channel-2`, the previous committed request)

Floorplan only; everything else (halo 5, seed 1, default density, clock 20 ns) unchanged.

- Die 1520 x 1950 um, core 10..1510 x 10..1940.
- Bottom row (banks 0, 1 = A): MX, lower-left at (20, 40) and (780, 40). MX puts
  the port 0 data pins (south edge in R0) on the north edge, facing the band.
- Top row (banks 2, 3 = B): R0, lower-left at (20, 1232) and (780, 1232). The R0
  south edge (port 0 data) faces the band.
- Logic band y = 718 .. 1232 um (514 um high). `dout1` (north edge in R0) faces the
  die edge on the top row and, after MX, the south die edge on the bottom row,
  with a 40 um margin to the die edge.
- Macro footprint 699.89 x 677.565 um (LEF `SIZE`, see `20261111-macro-pin-geometry`).

## Global-route overflow by layer (final congestion report, GRT-0096)

Source: `openroad-90857ef6934748cc981b2d681223db53-stdout.log.gz` (this record).

| Layer | Usage | Max H / Max V | Total congestion |
|---|---|---|---|
| met1 | 55.25 % | 4 / 1 | 6871 |
| met2 | 74.88 % | 1 / 9 | 23282 |
| met3 | 23.07 % | 3 / 1 | 610 |
| met4 | 32.56 % | 1 / 5 | 1780 |
| met5 | 6.14 % | 2 / 1 | 567 |
| total | 49.43 % | 11 / 17 | **33110** |

Wirelength 4801999 um, 582730 vias, 69555 nets. The detailed route was not reached.
Also in the log: `GRT-0281` clk fanout 4858; `GRT-0273` NDR disabled on clk nets;
many `PDN-0110` (no met4-met5 via) warnings along the macro edges at y = 718 and 1914.

## Die and SRAM fraction

- Die 1520 x 1950 = 2.964 mm^2; four macros = 4 x 0.4742 = 1.897 mm^2 -> 64.0 %
  of the die (64.5 % of the 1500 x 1930 core).

## Reading

33110 congestion cells here is far above the 4464 recorded for
`20261107-route-congestion` attempt 2 (an unverified console reading, 2700 x 1410
die, different macro rows). Met2 (vertical) carries most of it. This is
a single run and the cause is not isolated; the die is also 25 % smaller than that
attempt, so the comparison is not one lever. Per issue #43's decision block this
was the last attempt; routing is not closed, item 2 stays unmet, no further lever
is tried here.
