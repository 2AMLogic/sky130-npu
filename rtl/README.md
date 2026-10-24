# rtl

Synthesizable RTL of the NPU, written from the ratified [spec](../spec/npu.md)
with no spec change. Plain Verilog with `generate`; Icarus is run with `-g2012`.

**Status: elaborates and lints; functional correctness is not claimed here.**
Bit-exactness against the golden model is the testbench issue's gate (#12).
Nothing in this directory is a timing, area or throughput result.

## Files

| File | Block |
|---|---|
| `npu_top.v` | Top: parameter legality, wiring, operand capture, drain select |
| `npu_host.v` | Wishbone B4 classic slave and the register file (spec section 6) |
| `npu_ctrl.v` | START checks (`ERR_CODE` 1..4), run-config latch, tile FSM, `PERF_CYCLES` |
| `npu_banks.v` | Bank instances, bank mux, RW-port arbitration |
| `npu_array.v` | `ARRAY_N x ARRAY_N` PE grid and the edge skew |
| `npu_pe.v` | One PE: INT8 x INT8 -> INT32 accumulate, output-stationary |
| `npu_requant.v` | Drain datapath: bias, multiply, round-half-up shift, ReLU, saturate |
| `pdk/sky130/npu_sram_bank.v` | **The PDK seam** (below) |
| `check.sh` | Icarus + Yosys elaboration at N = 8 and N = 4, negative cases |
| `synth/` | Synthesis request, generic Yosys estimate script, recorded estimates |

## Parameters

`ARRAY_N` on `npu_top` is the only size parameter. Everything else is derived.

| Parameter | Legal values | Default |
|---|---|---|
| `ARRAY_N` | 4 (fallback), 8 (target) | 8 |

| Derived | `ARRAY_N = 4` | `ARRAY_N = 8` | Where |
|---|---|---|---|
| `NBANKS` | 2 | 4 | `npu_top` |
| `BANK_BYTES` | 2048 | 4096 | `npu_top` |
| `DEPTH_WORDS` (per bank) | 512 | 1024 | `npu_banks` |
| words per k-vector | 1 | 2 | `npu_banks` |
| result words per tile | 4 | 16 | `npu_ctrl` |
| `K_MAX` | 256 | 256 | `npu_top` (fixed) |
| host access to an active bank while BUSY | outside the operand and result ranges only (decision 0001 addendum) | never | `npu_host` |

Any other `ARRAY_N` fails at elaboration, in Icarus, Yosys and Verilator, by
instantiating a module whose name is the message
(`ERROR_ARRAY_N_must_be_4_or_8__...`). `ARRAY_N = 16` is legal in spec section
1 but is **deliberately not implemented**: its two-banks-per-operand interleave
is not designed (CLAUDE.md: stretch must not drive the architecture), so it
fails the same way instead of building something silent. Adding it is a change
to `npu_banks` and the bank-role map, not to the other blocks.

## Interface

`clk`, synchronous active-high `rst`; Wishbone B4 classic slave
`wb_{cyc,stb,we}_i`, `wb_adr_i[15:0]` (byte address), `wb_dat_i`, `wb_sel_i`,
`wb_dat_o`, `wb_ack_o`, `wb_err_o`; level `irq`.

Choices the spec leaves to the RTL (none relaxes a spec row):

- Every response is registered: ACK/ERR arrives at least one cycle after the
  request, and a bank-window access waits for the port grant.
- Bank windows sit at `0x1000 + 0x1000*b`; an offset past the bank size or a
  bank index `>= NBANKS` returns `ERR`. Register space (`0x0000-0x0FFF`),
  including reserved offsets and `BIAS[n >= ARRAY_N]`, reads 0 and ignores
  writes with ACK. A bank-window access that is denied (section 5.3) returns
  `ERR` and does not set `STATUS.ERR`.
- Run configuration (`K`, `BANKS`, offsets, `REQ_*`) is latched at an accepted
  `START`; later writes do not affect the running tile. `BIAS` is read while
  draining, so a `BIAS` write during BUSY is dropped (ACKed, not stored).
- `CTRL` writes set `IRQ_EN` from bit 2 every time byte 0 is written.
  `SOFT_RESET` returns the FSM to idle, clears `STATUS` and `PERF_CYCLES`, and
  leaves the configuration registers and `BIAS` alone. Banks already written stay written.
- When several `START` checks fail, the lowest `ERR_CODE` is reported.
  `A_BANK == B_BANK` is `ERR_CODE` 2 (one bank cannot feed both operands).
  `START` while BUSY sets `ERR_CODE` 5 and `STATUS.ERR` and leaves the running
  tile untouched.
- `PERF_CYCLES` counts the cycles BUSY is high for the last accepted operation.
- Bank roles are not wired: `A_BANK`, `B_BANK` and `OUT_BANK` pick any banks
  per tile, so ping-pong is the host alternating them (spec section 2).

## Microarchitecture (spec leaves it to the RTL)

Stall-then-drain, no shadow accumulator (spec sections 2 and 9):

1. FEED, `K` cycles: one k-vector per cycle from the A and B banks. Bank data is
   registered once (`a_vec`/`b_vec`), then skewed (row `m` by `m` cycles, column
   `n` by `n`), so PE `(m, n)` sees step `k` at cycle `k + m + n`.
2. WAIT, `2 * ARRAY_N` cycles: the last PE finishes.
3. DRAIN, `ARRAY_N^2 / 4` cycles: four accumulators per cycle go through
   `npu_requant` (three register stages: bias add, multiply, shift/saturate); one
   result word per cycle is written to `OUT_BANK` through its RW port.
4. TAIL, 3 cycles: the requantizer pipeline empties, then DONE.

Idle cycles feed zeros, which add nothing, so PEs need no valid bit; only a
clear at the start of a tile.

## The PDK seam

The seam is `pdk/sky130/` and nothing else (spec section 10). It holds one
module, `npu_sram_bank`, and nothing outside that directory names a sky130
macro, a cell or a Liberty file.

```
npu_sram_bank #(DEPTH_WORDS, WORD_BITS)
  clk
  rw_en, rw_we[WORD_BITS/8-1:0], rw_addr, rw_wdata, rw_rdata   // RW port; rw_we == 0 is a read
  r_en, r_addr, r_rdata                                        // R port, read only
```

Timing contract: both ports are synchronous; read data appears the cycle after
the address; `rw_we[i]` enables byte `i` (byte 0 = bits `[7:0]`); a same-cycle
read and write of one word on different ports is never issued by the NPU.

`pdk/sky130/npu_sram_bank.v` holds two bodies: the **behavioral simulation
model** (default, what `check.sh` compiles) and, under `-DNPU_SRAM_MACRO`, a
wrapper over the pinned OpenRAM macro. The pin is `reuse.lock.json`; view
inventory, the read-hold finding and the evidence are in `pdk/sky130/README.md`
and decision 0005. Only the 512 x 32 macro is pre-generated upstream; the
1024 x 32 macro is a pinned generator config with no views imported. The wrapper
keeps this port list and one-cycle read latency. Slow and fast Liberty views are
still missing (spec gaps G1, G2); nothing here says whether a macro's access time
fits a 50 MHz cycle.

To port to another PDK, replace `pdk/sky130/`; no other file changes.

## Checks

```
./rtl/check.sh            # N = 8 and N = 4 elaborate; N = 6 and N = 16 are rejected
./rtl/synth/synth.sh 8 core   # generic Yosys estimate, see rtl/synth/README.md
```
