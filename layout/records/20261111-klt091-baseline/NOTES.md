# 20261111-klt091-baseline -- the wider-channel floorplan re-run under klt 0.9.1

Result: NOT routed (`GRT-0116`); no GDS. **Counts here are sourced**: the
OpenROAD stdout logs (`openroad-*-stdout.log.gz`) and `npu_top_route_metrics.json`
are committed alongside.

Change vs `20261111-wider-channel`: only the tool. klt 0.8.0 -> 0.9.1
(`layout/klt-pin.json`; `flow/toolchain.json` is unchanged and still pins
synthesis/smoke), and macro `instance` is now the literal db name
(`g_bank\[0\]`, one backslash): 0.9.x passes it to `place_macro` as-is and the
0.8.0 three-backslash spelling gives `MPL-0020`. Floorplan otherwise identical.

Final GRT congestion (from the committed log): met1 1617, met2 1451, met3 102,
met4 59, met5 0; Total 3229 cells, max H/V 3/3, 20.06% usage. This reproduces,
and now sources, the 3229 reading previously recorded as unverified.
