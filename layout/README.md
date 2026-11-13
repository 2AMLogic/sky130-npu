# layout

Place-and-route of `npu_top` (`ARRAY_N = 8`, four OpenRAM 4 KB macros).

- `par-request.json`: the `klt place-and-route` request. Macros A0/A1 (banks 0, 1)
  west, B0/B1 (banks 2, 3) north, per `spec/floorplan-sketch.md`; abstract LEF
  for placement, full GDS for stream merge. `macros[].instance` is a hierarchical
  path **into the netlist being routed**, so it is coupled to the synthesis record:
  the four paths here end in `genblk1.g_macro.u_macro`, the macro instance name in
  the current (20261111) netlist. A mismatch is loud, not silent — OpenROAD stops
  the floorplan stage with `[ERROR MPL-0020] Couldn't find a macro named ...`.
- `run.sh`: cold-start runner (pinned klt via `uvx`, PDK pin check, inputs staged
  into `layout/build/`). The netlist it stages is whichever record
  `rtl/synth/synth-request.json` points at, resolved by `rtl/synth/current-netlist.sh`
  — no record id is written down here. `./layout/run.sh --record ID` copies the
  result to `records/ID/` (append-only; failed runs are recorded too), and that
  record's `tool-versions.txt` names the netlist it routed and its sha256.
- `records/20261107-route-congestion/`: first attempt. **Not routed**: reaches
  CTS, global routing fails with `GRT-0116`. No routed GDS is committed and
  T1 item 2 is not cited. See that directory's `NOTES.md`.
- `records/20261111-*`: floorplan iterations (orientation, channel width, halo,
  wider channel). None routes; lowest unverified reading is 3229 global-routing
  congestion cells (counts not re-derived, logs not committed) (`20261111-wider-channel`, which `par-request.json` now holds).
  Halo and placement density cannot be set through the klt 0.8.0 request.
- klt pin: `layout/run.sh` reads `flow/toolchain.json` (the single pin, 0.9.1;
  halo and `placement_density` exist from 0.9.0).
- `records/20261111-klt091-*`: the same floorplan under klt 0.9.1, with
  **sourced** counts (OpenROAD logs and route metrics committed). Baseline 3229
  congestion cells; `placement_density` 0.45 gives 4383 and 0.75 gives 6096
  (both worse than the 0.6 default). Halo is unusable on this netlist
  (`PDN-0217`, klayout-tools#5302). Still no routed GDS.

- `records/20261111-macro-pin-geometry/`: analysis, no run. The macro LEF puts
  port 0 data pins (`din0`, `dout0`) on the south edge and port 1's data output
  (`dout1`) on the north edge (address pins are split per bit, see the
  record), and both ports carry array traffic, so no orientation faces both
  at the logic. Also
  gives the die/SRAM fraction (macros 1.9 mm^2, 48 % of the 3.95 mm^2 die).

Liberty for the macros is TT-only analytical (`reuse.lock.json`).
