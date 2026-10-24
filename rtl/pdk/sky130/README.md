# pdk/sky130: SRAM macro pin, views and wrapper evidence

The pin is `reuse.lock.json` at the repo root (decision 0002, decision 0005).
Source: VLSIDA `sky130_sram_macros` @ `965df150c754fe2b3f93a0bd1f9883eb114279b2`
(OpenRAM-generated, 1rw1r, 32-bit words, byte write mask).

## Which macro, and what is actually imported

| Bank | Macro | Pre-generated upstream | Views imported |
|---|---|---|---|
| 1024 x 32 (target) | `sky130_sram_4kbyte_1rw1r_32x1024_8` | No: only the generator config exists | None. Config hashes pinned. |
| 512 x 32 (fallback) | `sky130_sram_2kbyte_1rw1r_32x512_8` | Yes | Verilog, LEF, GDS, TT Liberty: sha256 in the lock |

Nothing from the upstream repo is copied into this repo; the lock records
where each file comes from and its hash.

## Liberty / LEF view inventory (spec gaps G1, G2)

| View | 512 x 32 | 1024 x 32 |
|---|---|---|
| Liberty TT 1.8 V 25 C | shipped with the macro | not generated |
| Liberty slow (ss) | **missing: G1 stays open** | not generated: G1 stays open |
| Liberty fast (ff) | **missing: G2 stays open** | not generated: G2 stays open |
| LEF | shipped with the macro | not generated |

The shipped 512 x 32 Liberty reports `minimum_period` 1.956 ns and a `dout0`
delay of 0.383 to 0.529 ns, TT only. That says nothing about a 20 ns slow-corner
cycle. No timing claim is made from it. A timing result through a macro must
name the view's origin: here "shipped with the 512 x 32 macro, TT only".
To close G1/G2 the generator must be run with multiple corners
(`nominal_corner_only = False`); not done here.

## Read latency finding (decision 0005)

The macro samples its inputs at the rising edge and drives `dout` from the
falling edge of the same cycle (+ its delay), and clears it to X shortly after
the next rising edge. So a consumer flop capturing at the next rising edge sees
the data: one cycle, matching the contract. But the macro does **not** hold the
data after that edge, which the behavioral model does. `npu_sram_bank` under
`-DNPU_SRAM_MACRO` therefore adds a per-port hold register; latency stays one
cycle, so no controller change is needed. The macro output is only valid for the
second half of the cycle, which is half-cycle budget for whatever reads
`rw_rdata`/`r_rdata` combinationally; the floorplan/STA work must check it.

## Evidence (simulation, not measured silicon)

`tb_macro_wrapper.v` drives write (full and masked), read on both ports, idle
cycles and a repeat read at 512 x 32, and prints what a capturing flop sees each
cycle. Run against the behavioral model and against the wrapper over the pinned
macro Verilog, the non-X lines are identical (2026-10-24):

```
iverilog -g2012 -o s.vvp tb_macro_wrapper.v npu_sram_bank.v && vvp s.vvp
iverilog -g2012 -DNPU_SRAM_MACRO -o m.vvp tb_macro_wrapper.v npu_sram_bank.v macro.v && vvp m.vvp
```

`macro.v` is the pinned `..._32x512_8.v` with the `mem` declaration moved above
its first use: the upstream file uses `mem[...]` in a `$display` before declaring
it, which Icarus rejects ("Scope index expression is not constant"). Yosys
`hierarchy -check` passes on the wrapper at 512 (with that file) and at 1024
(with a blackbox for the not-yet-generated macro). Not checked: the 1024 x 32
macro itself, its timing, power pins (`USE_POWER_PINS`), or P&R.
