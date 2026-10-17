# 0002: SRAM macro source is OpenRAM-generated sky130 macros

Status: accepted on merge. This is an adopt-or-record decision under the
fleet's reuse rule (a block is designed once); this repo does not design a
macro.

## Options

| Option | State | Assessment |
|---|---|---|
| OpenRAM sky130 macros (OpenRAM generator, sky130 port) | Exists; published pre-generated macros are 1rw1r, 32-bit words, byte write mask | Adopt. Matches the port and word size the spec assumes. |
| `sky130-sram-compiler` sibling canary | Referenced by the README as "once it delivers"; not checked as delivered by this spec | Do not depend on it. Re-evaluate by a new decision record when it delivers. |
| Standard-cell (flop) RAM | Always available | Rejected at 16 KB: 131072 bits x about 20 um^2 per `dfxtp_1` flop (arithmetic from the cell area, to confirm in the pinned library) is about 2.6 mm^2 of storage before read muxes and clocking. Kept only as an emergency fallback for the 4 KB fallback size. |

## Decision

Adopt OpenRAM-generated sky130 macros, one macro instance per logical bank.
The bank geometries in the spec (1024 x 32 at target, 512 x 32 at fallback,
2048 x 32 at stretch) are generated with OpenRAM at the recorded config if a
pre-generated macro of that size is not available.

## What is not yet known (recorded, not assumed)

- Whether a pre-generated macro of exactly 4 KB (1024 x 32) exists. If not, the
  generator config is pinned instead of a pre-generated macro.
- The macro's Liberty and LEF views and their corners (spec gaps G1, G2).
  Whether the view is a file shipped with the pre-generated macro or output of
  the generator is recorded next to every timing result that uses it.
- Whether the read access time fits the 20 ns cycle (50 MHz).

## Pin

`reuse.lock.json` does not exist yet. The first PR that imports a macro
(issue #6 per spec section 9) creates it. The pin entry must record: source
repository, full 40-hex commit, macro/config name (or generator config file
hash), view files used with their sha256, and the date. Until then nothing is
imported and nothing is pinned.

## Consequences

- The only seam to the PDK-specific macro is `npu_sram_bank` (spec section 10).
- If the slow-corner view is missing or the access time misses 20 ns, the
  reaction is the 25 MHz fallback or a registered macro output stage, decided
  by a new decision record, not by editing the spec row.
