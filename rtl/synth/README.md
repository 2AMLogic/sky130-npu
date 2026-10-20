# rtl/synth

Synthesis of the NPU at the target size (`ARRAY_N = 8`, the default).

| File | What |
|---|---|
| `synth-request.json` | `klt synthesize` request for the target size, mapped to `sky130_fd_sc_hd` at `tt_025C_1v80`, behavioral SRAM model included. **Not run for this PR**: the model turns 16 KB of SRAM into about 131 k flops (131 330 enabled flops) (see below), too heavy for the shared worker. Nothing is recorded from it. |
| `synth.sh` | Generic Yosys `synth` (no cell library): `./synth.sh 8 core` or `full` |
| `records/20261020-yosys-generic/` | `stat` output of three runs, append-only |

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
