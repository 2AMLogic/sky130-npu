# records (results ledger)

One directory per run: `records/<UTC-timestamp>-<id>/record.json`, created by
`runner.py`. **Append-only**: a run only ever adds a new directory; existing
records are never rewritten, renamed or deleted, and the runner opens the file
exclusively so it cannot overwrite one. Corrections go in a new record that
refers to the old one.

`record.json` fields: `id`, `utc`, `toplevel`, `sources`, `parameters`,
`test_module`, `cocotb`, `simulator` (the `iverilog -V` version string),
`passed`, `tests`, `failures`.
