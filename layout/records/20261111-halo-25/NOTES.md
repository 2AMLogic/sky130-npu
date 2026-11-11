# 20261111-halo-25 -- lever 3 (halo): NO EFFECT, the request field is ignored

**Provenance of congestion counts: NOT RE-DERIVED.** The figures below were read
from the OpenROAD/GRT console during the run. The logs and
`npu_top_route_metrics.json` lived under `layout/build/` (not committed); the surviving local copy holds no route-stage counts, and
`par.json`/`par.err` in this record carry no counts (only
`GRT-0116`). Treat every count as an unverified reading, not evidence; the only
sourced fact here is that the run did not route (`GRT-0116`, no GDS).

Result: NOT routed (`GRT-0116`), and the run is **not evidence about halo**.

Lever changed vs `20261111-wider-channel`: `macros[].halo` 5 -> 25 (all four).
Congestion total is identical to the previous record (3229 cells, max H/V 3/3,
same usage). Cause: klt 0.8.0 (the pin) accepts `halo` in `macros[]` but does not
carry it into the validated macro record (`place_and_route_request.py`
`_validate_macros` emits instance/lef/cell_name/x_um/y_um/orientation/gds only),
and the generated `pnr_npu_top_route.tcl` contains no halo. A halo cannot be set
through the request. Likewise global placement density is a fixed constant in
`place_and_route_script.py` (lever 4 not settable). Gap filed as
2AMLogic/klayout-tools#5300. `halo` is dropped from the request in later records.
