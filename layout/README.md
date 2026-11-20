# layout

Place-and-route of `npu_top` (`ARRAY_N = 8`, four OpenRAM 4 KB macros).

- `par-request.json`: the `klt place-and-route` request. Macros A0/A1 (banks 0, 1)
  west, B0/B1 (banks 2, 3) north, per `spec/floorplan-sketch.md`; abstract LEF
  for placement, full GDS for stream merge. `macros[].instance` is a hierarchical
  path **into the netlist being routed**, so it is coupled to the synthesis record:
  the four paths here end in `genblk1.g_macro.u_macro`, the macro instance name in
  the netlist selected by `rtl/synth/current-netlist.sh`. A mismatch is loud, not silent — OpenROAD stops
  the floorplan stage with `[ERROR MPL-0020] Couldn't find a macro named ...`.
- `run.sh`: cold-start runner (inputs staged into `layout/build/`). The record
  id, the pinned klt via `uvx`, both pin checks and the host-path scrub come
  from `flow/runner-lib.sh`, shared with the other flow runners. The netlist it
  stages is whichever record `rtl/synth/synth-request.json` points at, resolved
  by `rtl/synth/current-netlist.sh` — no record id is written down here.
  `./layout/run.sh --record ID` copies the result to `records/ID/` (append-only;
  failed runs are recorded too), and that record's `tool-versions.txt` names the
  netlist it routed and its sha256.
- `sta/`: standalone **pre-route** STA reads of the committed netlist
  (netlist mode, no DEF — `geometry_source: "netlist_estimate"`). `sta/run.sh`
  runs the pinned `klt sta` plus a direct OpenROAD `report_checks` probe for
  the worst paths through a macro pin (`klt sta` itself cannot select paths
  through an internal pin — only top-level ports; gap filed at
  klayout-tools#5754). Informational readings, never closure: ideal clock, no
  wire-load model, tt only, analytical macro delay model; post-route
  multi-corner STA is #46.
  - `sta/records/20261114-pre-route-tt-20ns/`: first read, tt, 20 ns.
    Headline: 20 ns does **not** close (worst slack -0.984 ns, 1984 setup
    violations, hold clean) but the binding path is control-to-array — zero
    macro pins in the violator set. Macro read access time 0.335 ns; worst
    macro-pin slack +16.21 ns in / +8.77 ns out; `dout` launches on `clk0`'s
    **falling edge**, so the wide read buses have a half-cycle (10 ns)
    budget. See that directory's `NOTES.md`.
- `records/20261107-route-congestion/`: first attempt. **Not routed**: reaches
  CTS, global routing fails with `GRT-0116`. No routed GDS is committed and
  T1 item 2 is not cited. See that directory's `NOTES.md`.
- `records/20261111-*`: floorplan iterations (orientation, channel width, halo,
  wider channel). None routes; lowest unverified reading is 3229 global-routing
  congestion cells (counts not re-derived, logs not committed) (`20261111-wider-channel`, which `par-request.json` now holds).
  Halo and placement density cannot be set through the klt 0.8.0 request.
- `flow/runner-lib.sh` reads the klt 0.9.2 pin from `flow/toolchain.json`.
  This release supports placement-only macro keep-outs and GCell overflow reporting.
- `records/20261111-klt091-*`: the same floorplan under klt 0.9.1, with
  **sourced** counts (OpenROAD logs and route metrics committed). Baseline 3229
  congestion cells; `placement_density` 0.45 gives 4383 and 0.75 gives 6096
  (both worse than the 0.6 default). Halo is unusable on this netlist
  (`PDN-0217`, klayout-tools#5302). Still no routed GDS.

- The [klt 0.9.2 wider-channel baseline](records/20261120-klt092-baseline/NOTES.md)
  reached global routing and stopped at `GRT-0116` with total overflow 3,229.
  The worst 20 GCell centers are inside bank 0 (12) and bank 1 (8). This run
  uses the `20261115-sky130-hd` netlist.

- `records/20261111-macro-pin-geometry/`: analysis, no run. The macro LEF puts
  port 0 data pins (`din0`, `dout0`) on the south edge and port 1's data output
  (`dout1`) on the north edge (address pins are split per bit, see the
  record), and both ports carry array traffic, so no orientation faces both
  at the logic. Also
  gives the die/SRAM fraction (macros 1.9 mm^2, 48 % of the 3.95 mm^2 die).

Liberty for the macros is TT-only analytical (`reuse.lock.json`).
