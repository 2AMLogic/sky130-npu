# Floorplan sketch (first, pre-RTL)

Not to scale. A sketch to fix topology and bus widths early; macro sizes are
placeholders until the pinned macro LEF is read (spec gap G1 region, issue #6).

Target: `ARRAY_N = 8`, 4 banks. A feeds the array from the west edge, B from
the north edge; results go back to an A bank (the idle one).

```
          B0 (4 KB)          B1 (4 KB)
        +-----------+      +-----------+
        |  macro    |      |  macro    |
        +-----+-----+      +-----+-----+
              |  64 b (B read, 2 ports x 32)  per active bank
              +----------+---------+
                         v         v  (one of B0/B1 active, mux in logic)
   A0 +--------+     +-------------------+
 (4KB)|        | 64b |  8 x 8 PE array   |   results: 32 b write
      | macro  +---->|  (west edge: A,   +------+
      +--------+     |   north edge: B)  |      |
   A1 +--------+     +---------+---------+      |
 (4KB)|        | 64b           |  8 x INT32     |
      | macro  +---->(mux)     v  drain         |
      +----^---+       +---------------+         |
           |           | bias, requant |         |
           +-----------+  (INT8 out)   +---------+
                       +-------+-------+
                               |
                       +-------+-------+
                       | controller,   |   Wishbone: 32 b data,
                       | regs, WB slave|<-- 32 b address, SEL, 1 irq
                       +---------------+
```

Bus widths (target):

| Bus | Data | Address | Notes |
|---|---|---|---|
| Active A bank -> array | 64 b (both ports read) | 2 x 10 b word address | one bank at a time, ping-pong |
| Active B bank -> array | 64 b | 2 x 10 b | same |
| Array/requant -> A bank | 32 b write + 4 b mask | 10 b | RW port, priority over host |
| Host <-> each bank | 32 b | 10 b | RW port when the bank is idle |
| Host Wishbone | 32 b | 32 b | |

About 170 operand data and address wires (2 x (64 + 20)) cross between the
active macros and the array, plus about 45 for the result write bus and the host buses. Stretch (`N = 16`) doubles the operand buses.

## SRAM fraction of die area (estimate, unmeasured)

- Macros: 16 KB. The planning assumption is on the order of 0.2 mm^2 per KB
  for a 1 KB OpenRAM sky130 macro, so about 3 mm^2 for 16 KB if it scales
  linearly. This figure comes from recollection of published macro sizes and
  must be replaced by the LEF size once the macro is pinned.
- Logic: 64 PEs (8 x 8 multiplier, 32-bit accumulator, skew registers) at a
  planning figure of about 5000 um^2 each is about 0.3 mm^2; requantizer,
  controller, registers and bias file about 0.2 mm^2.
- Estimate: SRAM is roughly 85 percent of cell area (range 75 to 90 percent).
  The floorplan is therefore dominated by macro placement and the channels
  between macros and array.

## Congestion note

- All four macros want to be adjacent to the array's west or north edge; A0/A1
  and B0/B1 each need a 64-bit bus to the same array edge, so edge length of
  the array, not area, is the limiting resource. The sketch splits A and B
  across two edges for this reason.
- Macro pins are on fixed sides and layers set by the macro LEF; the wide buses
  must reach them through channels between macros. Channel width is a decision
  for the first placement run; expect OpenROAD macro placement to be weak here
  (CLAUDE.md), and file gaps found at that point against klayout-tools.
- Macro power rings and blockages on the routing layers the macro uses reduce
  the channel capacity; unknown until the LEF is read.
- Utilization of the standard-cell region around the macros is the lever if
  routing fails; the target size is not allowed to drive the stretch design.
