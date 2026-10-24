# 0005: Who owns the SRAM macro pin, and the macro read contract

Status: accepted on merge. Corrects decision 0002 "Pin" and the spec rows that
name issue #6 as the pin owner; it does not change any spec table value.

## Context

Decision 0002, spec section 9 (`spec/npu.md`) and `spec/floorplan-sketch.md`
name #6 as the owner of `reuse.lock.json`. #6 closed as the PDK/toolchain
bring-up and shipped no macro. Issue #25 imports the pin.

## Decision

- **#25 owns the macro pin.** Read every "#6 owns the pin" pointer in
  `spec/decisions/0002-sram-source.md` ("Pin"), `spec/npu.md` and
  `spec/floorplan-sketch.md` as #25. Those files are not edited; this record
  supersedes the pointer.
- The first pin is `reuse.lock.json`: OpenRAM generator configs from
  `VLSIDA/sky130_sram_macros` @ `965df150c754fe2b3f93a0bd1f9883eb114279b2`.
  1024 x 32 is **not** pre-generated upstream, so its generator config hashes
  are pinned and no views are imported. 512 x 32 is pre-generated and its views
  are pinned with sha256. See `rtl/pdk/sky130/README.md`.
- **Read latency is one cycle at the consumer's capturing edge**, as the
  contract requires, so no controller change is needed. The macro does not hold
  its output past that edge, so the wrapper holds it with a register per port.
  Its output is valid only in the second half of the cycle; the half-cycle budget
  is an STA question, not decided here.

## Still open

- G1/G2: no slow or fast Liberty view exists for any macro here (only TT).
- The 1024 x 32 macro has not been generated, so its access time against the
  20 ns cycle is unknown. If it misses, the reaction stays as in decision 0002.
