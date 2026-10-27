# rtl/synth

Synthesis of the NPU at the target size (`ARRAY_N = 8`, the default).

| File | What |
|---|---|
| `synth-request.json` | `klt synthesize` request for the target size (`ARRAY_N = 8`, set in `parameters`), mapped to `sky130_fd_sc_hd` at `tt_025C_1v80`. It lists `pdk/sky130/npu_sram_bank_bb.v` instead of `npu_sram_bank.v`: the SRAM macro is a `(* blackbox *)` instance, not the behavioral model (requests have no defines key, so the `ifdef` wrapper cannot be selected). Run with `--pdk sky130A`. |
| `synth.sh` | Generic Yosys `synth` (no cell library): `./synth.sh 8 core` or `full` |
| `records/20261020-yosys-generic/` | `stat` output of three runs, append-only |
| `records/20261027-sky130-hd/` | the `klt synthesize` run of `synth-request.json`: gate-level netlist `npu_top_synth.v`, envelope `synth-report.json`, scripts and logs, `tool-versions.txt`. Append-only |

## Recorded sky130 netlist (`records/20261027-sky130-hd/`)

`klt synthesize --pdk sky130A --format json rtl/synth/synth-request.json`
(klt 0.8.1.dev55, Yosys 0.67+post, open_pdks `f6eeac7` from `~/.ciel`,
`sky130_fd_sc_hd__tt_025C_1v80`), one local run, 235 s. 70 823 instances,
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
records/20261027-sky130-hd/synth-report.json synth-request.json` re-hashes the
request's RTL and the Liberty and exits 3 when the RTL changed without a new
netlist (no Yosys run). It is the `check` of the item-1 inventory
(`manifests/inventories/item-1.json`). After an RTL change, make a new dated
record and re-attest; do not edit this one.

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
