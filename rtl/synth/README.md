# rtl/synth

Synthesis of the NPU at the target size (`ARRAY_N = 8`, the default).

| File | What |
|---|---|
| `synth-request.json` | `klt synthesize` request for the target size (`ARRAY_N = 8`, set in `parameters`), mapped to `sky130_fd_sc_hd` at `tt_025C_1v80`. It sets `defines.NPU_SRAM_MACRO` so `npu_sram_bank.v` selects its macro wrapper, and declares the 1024 x 32 macro in `macros` (LEF only, no `lib`), so klt generates the `(* blackbox *)` declaration from the LEF pin list. Needs klt 0.9.1 or newer (`request.defines`). Run with `--pdk sky130A`. |
| `synth.sh` | Generic Yosys `synth` (no cell library): `./synth.sh 8 core` or `full` |
| `current-netlist.sh` | prints the path of `npu_top_synth.v` in the record `synth-request.json` writes to (`.outputs.dir`). The single owner of "which recorded netlist is current": `layout/run.sh`, `verification/check_mutation_gl.sh` and the gate-level command in `verification/README.md` all ask it instead of naming a record id, so a new record moves every consumer at once. `--relative` prints the repo-relative path |
| `records/20261020-yosys-generic/` | `stat` output of three runs, append-only |
| `records/20261027-sky130-hd/` | first `klt synthesize` run (klt 0.8.1.dev55), from the former hand-written blackbox file `npu_sram_bank_bb.v` (since removed). Append-only, superseded by the next row. No runner or request reads it any more (#121); it is cited only by records and by `manifests/attestations/item-1.json`, the superseded item-1 attestation, itself kept as append-only evidence (the manifest cites `manifests/attestations/item-1-klt091.json`, which attests the next row) |
| `records/20261111-sky130-hd/` | the `klt synthesize` run of the current `synth-request.json`: gate-level netlist `npu_top_synth.v`, envelope `synth-report.json`, generated macro blackbox, scripts and logs, `tool-versions.txt`. Append-only |

## Recorded sky130 netlist (`records/20261111-sky130-hd/`)

`klt synthesize --pdk sky130A --format json rtl/synth/synth-request.json`
(klt 0.9.1, Yosys 0.67+post, open_pdks `f6eeac7` from `~/.ciel`,
`sky130_fd_sc_hd__tt_025C_1v80`), one local run, 217 s. 70 823 instances,
the four `npu_sram_bank` instances each holding one
`sky130_sram_4kbyte_1rw1r_32x1024_8` black box (envelope `blackbox_modules`).
Read it with these limits:

- **Blackbox area is excluded from `area_um2`.** The macros contribute no
  area here; the figure is NPU logic and the bank hold registers only.
- **No timing is claimed.** `clock_period_ns` is null; the envelope's
  `timing.critical_path_ps` is ABC's internal estimate, not STA, and there is
  no macro Liberty view behind it.
- Not a P&R, area or signoff result.

**Freshness**: `klt synthesize --pdk sky130A --check
records/20261111-sky130-hd/synth-report.json synth-request.json` re-hashes the
request's RTL and the Liberty and exits 3 when the RTL changed without a new
netlist (no Yosys run). It is the `check` of the item-1 inventory
(`manifests/inventories/item-1.json`). After an RTL change, make a new dated
record and re-attest; do not edit this one.

The 20261111 run reproduces the 20261027 run's `instance_count` (70 823), `area_um2`,
`sequential_area_um2`, per-cell-type counts and `blackbox_modules` exactly; only the
blackbox's origin differs (generated from the LEF, with `vccd1`/`vssd1` power pins, instead
of a hand-written declaration). The envelope also gains `defines` and `macros`.

The two netlists are **not** interchangeable downstream, though: the macro
instance inside `npu_sram_bank` is named `u_macro` in the 20261027 netlist and
`\genblk1.g_macro.u_macro` in this one, so the hierarchical paths in
`layout/par-request.json` (`macros[].instance`) differ. Pointing P&R at the
wrong one is not silent — OpenROAD stops with `[ERROR MPL-0020] Couldn't find a
macro named ...`.

## Recorded estimate (`records/20261020-yosys-generic/`)

Yosys 0.67+post (`b8e7da6`), `synth -flatten`, generic gate library. These are
**estimates**: Yosys-internal gate counts, not sky130 cells, not area, not timing,
not signoff, and not a measurement.

| Run | Cells | Flip-flops | Note |
|---|---|---|---|
| N = 8, behavioral SRAM model included | 799 023 | 135 776 | Completes in 345 s, 2.3 GB. About 131 k of the flops are the 16 KB of SRAM. |
| N = 8, `npu_sram_bank` as a black box (4 instances) | 67 262 | 4 448 | NPU logic only; completes in 280 s, 340 MB. |
| N = 4, `npu_sram_bank` as a black box (2 instances) | 31 796 | 1 664 | NPU logic only; completes in 223 s, 170 MB. |

Reading it: the SRAM as flops dominates and says nothing about the macro; the
logic-only row is the one to compare across sizes. Mapping to sky130 cells and
any area figure wait on the `klt synthesize` run and on a macro view.
