# 20261111-macro-pin-geometry -- why orientation cannot fix the macro-pin congestion

No P&R run in this record. It is analysis of committed inputs only, written after
the four levers in `20261107-*` / `20261111-*` all failed to route.

## Source of every figure

- Macro LEF: `rtl/pdk/sky130/macro/sky130_sram_4kbyte_1rw1r_32x1024_8/sky130_sram_4kbyte_1rw1r_32x1024_8.lef`
  (hash pinned in `reuse.lock.json`). `SIZE 699.89 BY 677.565` um; the one `OBS`
  block covers met1, met2, met3, met4.
- Pin edges: every RECT of every signal pin in that LEF, classified per bit by
  which macro edge it touches (R0 orientation, macro origin at 0,0; the power
  pins `vccd1`/`vssd1` are excluded).
- Port use: `rtl/pdk/sky130/npu_sram_bank.v` lines 65-68 and `rtl/npu_banks.v`
  (`rw_rdata` and the port-1 read both feed the array).

## Signal pin edges (R0)

| Pin | Layer | Edge |
|---|---|---|
| clk0, csb0, web0 | met3 | west (x = 0) |
| addr0[2:9] | met3 | west (x = 0) |
| addr0[0:1], wmask0[0:3], din0[0:31], dout0[0:31] | met4 | south (y = 0) |
| csb1 | met3 | east (x = 699.89) |
| addr1[2:6] | met3 | east (x = 699.89) |
| clk1, dout1[0:31], addr1[0:1] | met4 | north (y = 677.565) |
| addr1[7:9] | met4 | **south** (y = 0) |

Port 0 data pins (`din0`, `dout0`, `wmask0`) are on the south edge; port 1's
data output (`dout1`) is on the north edge. Address and control pins are split
per bit: `addr0` is west (bits 2-9) and south (bits 0-1); `addr1` is east
(bits 2-6), north (bits 0-1) and south (bits 7-9), so three `addr1` bits share
an edge with port 0's data pins. A macro with logic on one side can have at
most one of the two data edges facing it.

## Consequence for this design

Both ports carry operand or result traffic (`dout0` is the RW read data, `dout1`
the second read port, spec section 9). So for every placement, at least one
port's data pins face away from the logic or a neighbouring macro. Inferred from
pin geometry, not measured: those wires have to route around the 700 x 678 um
footprint (met1-met4 blocked by the OBS), or cross over it on met5 only. This
is consistent with the hotspots in `20261107-route-congestion/NOTES.md`
(`rw_addr`, `dout0/1`, `rw_wdata` at macro pin edges). Re-orienting a macro
(R0/MY/MX/R180) moves which edges face the logic but does not change that the
port 0 data pins (`din0`, `dout0`) and the port 1 data pins (`dout1`) are on
opposite edges. `20261111-orient-my-a` (4666 vs 4464, unverified reading) is
consistent with that.

## Die and SRAM fraction (final request, `layout/par-request.json`)

- Die 2800 x 1410 um = 3.948 mm^2; four macros = 4 x 0.4742 = 1.897 mm^2.
- SRAM macro area / die area = 48.0 % (49.1 % of the 2780 x 1390 um core).
- `spec/floorplan-sketch.md` estimated about 3 mm^2 of macros and about 85 %
  of cell area; the LEF gives 1.9 mm^2 (a macro is 0.47 mm^2, not 0.8). The
  die here is mostly routing channel, because it was widened to cut congestion.

## What this leaves open

Not tried, and each needs a decision rather than another blind attempt (12 min
per run):

1. A sandwich floorplan (logic band between macro rows, mixed R0/MX) so port 0
   faces the logic on one side of each macro and port 1 wraps; wire length and
   met5 demand are unknown.
2. A different bank macro or wrapper that exposes both ports on one edge
   (spec / decision 0002 change, not an agent call).
3. Reducing port-1 traffic (RTL/architecture change; out of scope for #43).

Routing is not closed; no routed GDS; item 2 stays unmet.
