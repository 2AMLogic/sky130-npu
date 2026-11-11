# layout

Place-and-route of `npu_top` (`ARRAY_N = 8`, four OpenRAM 4 KB macros).

- `par-request.json`: the `klt place-and-route` request. Macros A0/A1 (banks 0, 1)
  west, B0/B1 (banks 2, 3) north, per `spec/floorplan-sketch.md`; abstract LEF
  for placement, full GDS for stream merge.
- `run.sh`: cold-start runner (pinned klt via `uvx`, PDK pin check, inputs staged
  into `layout/build/`). `./layout/run.sh --record ID` copies the result to
  `records/ID/` (append-only; failed runs are recorded too).
- `records/20261107-route-congestion/`: first attempt. **Not routed**: reaches
  CTS, global routing fails with `GRT-0116`. No routed GDS is committed and
  T1 item 2 is not cited. See that directory's `NOTES.md`.
- `records/20261111-*`: floorplan iterations (orientation, channel width, halo,
  wider channel). None routes; lowest unverified reading is 3229 global-routing
  congestion cells (counts not re-derived, logs not committed) (`20261111-wider-channel`, which `par-request.json` now holds).
  Halo and placement density cannot be set through the klt 0.8.0 request.

Liberty for the macros is TT-only analytical (`reuse.lock.json`).
