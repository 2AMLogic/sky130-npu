# records (results ledger)

One directory per run: `records/<UTC-timestamp>-<id>/record.json`, created by
`runner.py`. **Append-only**: a run only ever adds a new directory; existing
records are never rewritten, renamed or deleted, and the runner opens the file
exclusively so it cannot overwrite one. Corrections go in a new record that
refers to the old one.

`record.json` fields: `id`, `utc`, `toplevel`, `sources`, `parameters`,
`test_module`, `cocotb`, `simulator` (the `iverilog -V` version string),
`passed`, `tests`, `failures`.

`tests` counts the cases that **executed**. A `--testcase` / `TESTCASE` filter
leaves the unselected tests in cocotb's results XML as `<testcase>` elements
with a `<skipped>` child; those are excluded, so a filtered run records what it
ran and not the size of the suite. `failures` likewise counts only executed
cases, and `passed` is `tests > 0 and failures == 0`, so a filter matching
nothing records `tests: 0`, `passed: false` rather than a vacuous pass.

Records written before that fix (issue #128) count skipped cases as run. One
such record is in this ledger: `20261111T075128Z-4613a4c7` reports `tests: 11`
with `testcase: "test_workload_mm_smoke"` — 11 was the suite size, and that run
executed 1 test. The ledger is append-only, so that record is left as written;
this note is the correction.

Added with the bit-exact suite (earlier records simply lack them): `seed`
(random-test seed), `testcase` (the single test function run, or `null`),
`rtl_commit` (`git rev-parse HEAD` at run time), `sources_last_commit` (last
commit touching the source files), `sources_dirty` (uncommitted changes in the
sources), and `results`: what the tests hand back, with every entry labelled
`"basis": "simulated"`: `workload:<id>` (`array_n`, `M`, `K`, `N`,
`perf_cycles`, `u_array`, `mismatches`), `random` (`seed`, `gemms`,
`mismatches`) and `requant_latency` (`array_n`, `measured_cycles`,
`req_lat`, `result_words`: the requantizer's measured `in_vld` to
`out_vld` delay and the `REQ_LAT` the drain FSM counted, which
`test_requant_latency_matches_req_lat` requires to be equal).
`u_array = M*K*N / (perf_cycles * ARRAY_N^2)`.
