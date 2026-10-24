# records (results ledger)

One directory per run: `records/<UTC-timestamp>-<id>/record.json`, created by
`runner.py`. **Append-only**: a run only ever adds a new directory; existing
records are never rewritten, renamed or deleted, and the runner opens the file
exclusively so it cannot overwrite one. Corrections go in a new record that
refers to the old one.

`record.json` fields: `id`, `utc`, `toplevel`, `sources`, `parameters`,
`test_module`, `cocotb`, `simulator` (the `iverilog -V` version string),
`passed`, `tests`, `failures`.

Added with the bit-exact suite (earlier records simply lack them): `seed`
(random-test seed), `testcase` (the single test function run, or `null`),
`rtl_commit` (`git rev-parse HEAD` at run time), `sources_last_commit` (last
commit touching the source files), `sources_dirty` (uncommitted changes in the
sources), and `results`: what the tests hand back, with every entry labelled
`"basis": "simulated"`: `workload:<id>` (`array_n`, `M`, `K`, `N`,
`perf_cycles`, `u_array`, `mismatches`) and `random` (`seed`, `gemms`,
`mismatches`). `u_array = M*K*N / (perf_cycles * ARRAY_N^2)`.
