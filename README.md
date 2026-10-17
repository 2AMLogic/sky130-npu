# sky130-npu

A small edge neural-network accelerator on
[SkyWater sky130](https://github.com/google/skywater-pdk), the 130 nm open
PDK — an INT8 multiply-accumulate array fed by banked SRAM — designed by AI
agents driving [klayout-tools](https://github.com/2AMLogic/klayout-tools) and
the open-source cocotb + Icarus, Yosys and OpenROAD flow.

**Status: specification ratified.** No RTL or golden model yet.

**Built agent-native.** Every specification, decision record, testbench, and
line of documentation here is produced by AI agents working from a ratified
spec and an append-only evidence trail — not human-authored work that agents
merely assisted with. Verification is the product: every claim traces to a
recorded result. Where the agents hit friction with the open-source tooling —
most often [klayout-tools](https://github.com/2AMLogic/klayout-tools) — that
friction is filed as a public issue against the tool itself, so the fix
benefits everyone using sky130, not just this repo.

## Why this block, on this node

An accelerator like this is **SRAM-bound**: the MAC array is small, regular
logic, and the hard part is keeping it fed. Several SRAM banks have to sit
close to the array, each with enough ports and bandwidth to supply weights
and activations every cycle, and the wiring between banks and array is wide.
That makes the floorplan the design — macro placement, wide buses between
macros and logic, and routing congestion around them are the tool surface
this canary exists to stress.

It is also the origin of a port: `asap7-npu` scales the same architecture
up on a predictive PDK to stress DRC at size. The architecture, golden model
and testbenches are designed here once.

## Scope

- **In scope**: the MAC array (INT8 operands, INT32 accumulation), the
  dataflow controller, banked SRAM placement and its interface, a host-side
  register and DMA-style load/store interface, and the physical design and
  timing closure of the whole.
- **Not in scope**: designing a bitcell or SRAM macro (the macro source is an
  adopt-or-record decision: the OpenRAM-generated sky130 macros, the fleet's
  `sky130-sram-compiler` canary once it delivers, or standard-cell RAM), a
  processor (the host is external), floating point, and training.

## Target specification (ratified — see [spec/npu.md](spec/npu.md))

| Parameter | Target | Fallback | Stretch |
|---|---|---|---|
| MAC array | 8 x 8 (64 MACs), INT8 x INT8 → INT32 | 4 x 4 | 16 x 16 |
| Dataflow | output-stationary ([decision](spec/decisions/0001-dataflow.md)) | same | same |
| On-chip SRAM | 4 banks, 16 KB total | 2 banks, 4 KB | 8 banks, 64 KB |
| Operations | matrix multiply, 2-D convolution via im2col (host-side), bias, requantize, ReLU | matrix multiply | depthwise convolution (deferred) |
| Signoff clock (post-route STA, slow corner) | 50 MHz | 25 MHz | 100 MHz |
| Numerical correctness | bit-exact against the integer golden model | — | — |
| Signoff | DRC + LVS clean, STA closed at every ratified corner that has all its views | — | — |

The macro source is [OpenRAM sky130](spec/decisions/0002-sram-source.md); its
slow-corner Liberty view is an open gap, so the 50 MHz figure is unverified.

Throughput is a derived figure — MACs per cycle times the signoff clock — and
is only quoted together with the array utilization observed in simulation on
a stated workload.

Maturity ladder: spec ratified → golden model and RTL bit-exact on the
reference workloads → synthesized with timing met → placed and routed with
the SRAM banks, DRC/LVS-clean → post-route multi-corner STA closed →
shuttle seat → measured silicon. **Current position: spec ratified; golden model, harness and RTL not started.**

## Repo layout

```
spec/          ratified spec + decision records
rtl/           MAC array, controller, SRAM bank interface
verification/  golden model, cocotb testbenches, workload runs
layout/        GDS + DRC/LVS reports + STA reports (klayout-tools driven)
measurements/  silicon characterization (empty until tape-out)
```

## License

Apache License 2.0 — see [LICENSE](LICENSE).
