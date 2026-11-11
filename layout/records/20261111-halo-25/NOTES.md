# 20261111-halo-25 -- lever 3 (halo): NO EFFECT, the request field is ignored

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
