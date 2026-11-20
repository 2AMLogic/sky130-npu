# Wider-channel baseline with klt 0.9.2

OpenROAD finished clock-tree synthesis and stopped in global routing with
`GRT-0116`. The final total overflow was **3,229**. The layout runner exited
1 and produced no routed GDS. [Route error](par.err) · [Route log](openroad-8170efdb6f8f4747887221aced9cf36c-stdout.log.gz)

`./layout/run.sh --record 20261120-klt092-baseline` used the request from
`main` at `4c6525b` byte-for-byte. The die is 2800 × 1410 µm, all four
macros are R0, and the request sets neither a halo nor a keep-out. The
netlist, OpenROAD version and open_pdks revision are recorded alongside the
request. [Request](par-request.json) · [Tool versions and netlist hash](tool-versions.txt)

## Per-layer overflow

These are the total congestion values in OpenROAD’s final `GRT-0096` table.
The total row reports max horizontal/vertical overflow of 3/3 and 20.06%
resource usage. The raw report contains 3,220 directional GCell records.
Nine have overflow 2 and 3,211 have overflow 1, which sums to 3,229.
[Route log](openroad-8170efdb6f8f4747887221aced9cf36c-stdout.log.gz) · [Raw GCell report](npu_top_route_congestion.rpt)

| Layer | Total overflow |
|---|---:|
| li1 | 0 |
| met1 | 1,617 |
| met2 | 1,451 |
| met3 | 102 |
| met4 | 59 |
| met5 | 0 |
| **Total** | **3,229** |

## Worst 20 GCells

The fatal exit left `par.json` empty. The error names the worst layer and the
total, but supplies no `overflow_regions` or `congestion.null_reasons`. The
list below was recovered by running klt 0.9.2’s `parse_congestion_report` on
the saved raw report with the four `MPL-0035` macro boxes from the floorplan
log and zero margins. It ranks by decreasing overflow and keeps file order
for ties. Every raw entry says `on Layer -`, so an individual GCell’s metal
layer is unavailable. [Raw GCell report](npu_top_route_congestion.rpt) · [Floorplan log](openroad-3023f947648e4b80a6b40b296a0b9eab-stdout.log.gz) · [Upstream failure-reporting issue](https://github.com/2AMLogic/klayout-tools/issues/6952)

**20/20** centers are `inside_footprint` (12 in bank 0 and 8 in bank 1),
**0/20** are `keepout_band`, and **0/20** are unattributed. Among the nine
highest-overflow entries, four are nearest bank 0’s south edge facing the
die boundary. Two are nearest bank 1’s south edge facing the channel above
bank 0, and three are nearest bank 1’s west edge facing the die boundary.
The cell centered at (548.55, 707.25) µm crosses bank 1’s south edge at
y = 705 µm. Its center lies 2.25 µm inside the macro. The other eleven
entries are the first eleven of the 3,211 records tied at overflow 1.
[Raw GCell report](npu_top_route_congestion.rpt) · [Placed macro bounds](openroad-3023f947648e4b80a6b40b296a0b9eab-stdout.log.gz)

| Rank | Center (x, y) in µm | Direction | Overflow | Bank |
|---:|---|---|---:|---:|
| 1 | 638.25, 44.85 | horizontal | 2 | 0 |
| 2 | 583.05, 727.95 | horizontal | 2 | 1 |
| 3 | 631.35, 44.85 | horizontal | 2 | 0 |
| 4 | 548.55, 707.25 | horizontal | 2 | 1 |
| 5 | 624.45, 37.95 | horizontal | 2 | 0 |
| 6 | 51.75, 900.45 | vertical | 2 | 1 |
| 7 | 514.05, 65.55 | vertical | 2 | 0 |
| 8 | 17.25, 928.05 | vertical | 2 | 1 |
| 9 | 17.25, 934.95 | vertical | 2 | 1 |
| 10 | 596.85, 424.35 | horizontal | 1 | 0 |
| 11 | 286.35, 438.15 | horizontal | 1 | 0 |
| 12 | 596.85, 493.35 | horizontal | 1 | 0 |
| 13 | 672.75, 741.75 | horizontal | 1 | 1 |
| 14 | 624.45, 631.35 | horizontal | 1 | 0 |
| 15 | 610.65, 231.15 | horizontal | 1 | 0 |
| 16 | 631.35, 79.35 | horizontal | 1 | 0 |
| 17 | 258.75, 514.05 | horizontal | 1 | 0 |
| 18 | 44.85, 879.75 | horizontal | 1 | 1 |
| 19 | 534.75, 886.65 | horizontal | 1 | 1 |
| 20 | 603.75, 148.35 | horizontal | 1 | 0 |

## Comparison with the 0.9.1 baseline

Both records report 3,229 total overflow and the same per-layer totals.
This is **not a tool-only comparison**. The earlier runner selected
`20261027-sky130-hd` (netlist SHA-256 prefix `e43b49aa`), with SRAM instances
ending in `.u_bank/u_macro`. This run resolves the netlist from
`rtl/synth/synth-request.json` via `rtl/synth/current-netlist.sh` and routes
`20261115-sky130-hd` (`0eef5aff`), with instances ending in
`.u_bank/genblk1.g_macro.u_macro`. [Earlier baseline](../20261111-klt091-baseline/NOTES.md) · [Earlier runner](https://github.com/2AMLogic/sky130-npu/blob/59248b0/layout/run.sh#L26) · [Current inputs](tool-versions.txt)
