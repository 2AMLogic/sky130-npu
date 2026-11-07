# 20261107-route-congestion -- npu_top P&R reached `route`, global routing failed

Result: NOT routed. `stage_reached` is `cts`; `klt place-and-route` failed in the
`route` stage with `GRT-0116 Global routing finished with congestion`. No GDS.

Request: `par-request.json` (this directory), die 2700 x 1410 um, four macros
(abstract LEF; GDS merge not reached). Floorplan, macro placement (A0/A1 west,
B0/B1 north), tapcells, PDN, global placement, CTS all completed (~12 min).

Two attempts, both `GRT-0116`:

| Attempt | Die (um) | Total GRT congestion cells | met1 / met2 usage |
|---|---|---|---|
| 1 | 2160 x 1410 | 23889 | 57.4 % / 60.7 % |
| 2 (this request) | 2700 x 1410 | 4464 | 36.3 % / 28.5 % |

Widening the logic region cut overflow ~5x but did not clear it. A
`global_route -congestion_report_file` rerun on the attempt-2 CTS database
(17576 report lines) shows the remaining hotspots at macro pin edges and over
macro footprints where routing capacity is 0 (the OpenRAM LEF obstructs
met1-met4): bank read/write buses (`g_bank[n].rw_addr`, `dout0/1`,
`rw_wdata`) and one clock net. This is the macro-pin channel congestion the
floorplan sketch predicted. Untried levers: macro orientation/mirroring so pins
face the array, a wider A/B-to-array channel, per-macro halo, lower density.

Treatment of the macros: abstract LEF for place and route, full GDS supplied via
`macros[].gds` for stream merge (not reached). Liberty is TT-only analytical.
