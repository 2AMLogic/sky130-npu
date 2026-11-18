# 0006: The weight-streaming MVM architecture is evaluated and not adopted

Status: accepted on merge. An adopt-or-record decision under the fleet's reuse rule (a block is
designed once), applied to an external design instead of a sibling repo. It records the outcome of
evaluating three lessons that a review of `jwkim04/tesseract-npu` proposed for the next
generation of this block. It edits no spec row, imports no code and adds nothing to
`reuse.lock.json`.

## Source and method

- Evaluated commit: `93a57db9a060399dd6cba813f31b216fa0c4ae71` of `jwkim04/tesseract-npu`.
  Every claim about it carries a cite `[Tn]` into the table at the end, as `file:line` at that
  commit. The files were read as text from a pinned-commit archive; nothing from it was built,
  run or copied.
- What was read: `README.md`, `docs/spec.md` (overview, structure, MVM cluster, ISA, control
  core) and `docs/rtl-mvm.md` (sections 1 to 7, 9 and 15). What was not: the RTL sources, the
  software stack, and the attention, KV-cache and vector-unit documents. The cites are to the
  design's own documentation; whether its RTL matches was not checked.
- Figures about this repo are tagged **measured (simulated)** (read from a committed record),
  **derived** (arithmetic on spec or record numbers) or **inferred** (a reading of geometry, not
  a result). No simulation, synthesis or layout was run for this record.

## What tesseract-npu does

1. **Per-channel weight streaming.** One MVM cluster of 128 MAC lanes [T7] per DDR4 channel. Cluster
   `c` reads weights only from channel `c`, which holds a contiguous share of the weight rows
   [T2][T3][T4]. The cluster requests its rows back to back into a 512-beat weight FIFO sized
   by Little's law to cover the DDR round trip [T5]. The stated aim is an unbroken beat supply,
   not more MACs [T1]. Each cluster keeps a full private copy of the activation vector [T8].
2. **Dual weight streams per channel.** One stream is a 64 B beat per cycle, 12.8 GB/s at
   200 MHz, and a DDR4-2400 channel peaks at 19.2 GB/s. So when the token count `T` is at most
   half of `T_MAX`, a cluster reads a second stream, the other half of its rows, through a
   read-only port of its own [T1][T9][T10][T11][T13].
3. **Tile-op execution model.** The host lowers a graph to an op list. An on-chip RISC-V core
   issues 256-bit tile ops asynchronously to one in-order queue per unit (DMA, activation
   quantizer, MVM, vector unit); tickets, joins and fences order work across units
   [T15][T16][T17][T18][T19]. A unit may overlap the tail of one op with the start of the
   next when they are independent [T20].

## The sky130 analogue of a channel

The analogue of a DDR4 channel is one OpenRAM macro instance: a 1rw1r, 32-bit bank
([0002](0002-sram-source.md)) with its own two ports, read in one cycle ([0005](0005-sram-pin-owner.md)).

| | tesseract-npu | sky130-npu |
|---|---|---|
| Unit | DDR4 channel, one 512-bit AXI port per stream [T1][T21] | one 4 KB macro, two 32-bit ports |
| Rate | 64 B per cycle per stream, 12.8 GB/s at 200 MHz [T1] | 8 B per cycle, 0.4 GB/s at the 50 MHz target (derived; the clock is unverified, G1) |
| Read latency | hundreds of cycles; FIFO sized for about 440 [T5] | one cycle (0005) |
| Memory rate over one consumer's rate | 19.2 / 12.8 = 1.5 (derived) [T1] | 8 / 8 = 1.0: a bank "sustains exactly one operand stream" (`npu.md:61-62`) |
| Reuse of a byte read | a weight serves only the `T` tokens that share its beat [T6], `T` at most 4 in the release image [T8]; at `T = 1`, at most 1 to 2 MACs per streamed byte (derived, meta beats ignored) [T1][T7] | each operand byte feeds 8 PEs ([0001](0001-dataflow.md)); 64 MACs per 16 B, 4 per byte (derived) |
| Where weights come from | streamed from DRAM | host writes the bank windows, one word per bus cycle; bus-master DMA is deferred (`npu.md:231-234`, `npu.md:341`) |

Upstream has no SoC or ASIC realization to compare against: it provides only the FPGA pieces,
and its SoC column leaves the core parameters open and fixes the RTL to a 512-bit beat and 128
lanes [T21]. What is evaluated here is therefore the lessons, as the issue framed them, and not
a result of the design on SRAM macros.

The two designs are both supply-bound, but in different regimes. Upstream streams weights that
each serve only a few tokens, from a memory that has headroom. sky130-npu is an 8-way-reuse array
that sits exactly at its bank-port ceiling, and its open problem is macro pins and routing, not
memory rate
(`layout/records/20261111-macro-pin-geometry/NOTES.md`, `ROADMAP.md` "Blocked and waiting").

## Lesson 1: per-channel weight streaming. Verdict: reject

Mapping: the macros that hold `B` play the channels. Split the 8 output columns of `B` over four
of them (2 columns each), give each its own private cluster, and broadcast `A` to all.

- **No DDR channel decides it.** The FIFO is what makes streaming work upstream, and it exists
  to hide DRAM latency [T5]. Here the read latency is one cycle (0005) and weights arrive by
  host writes. A FIFO of the upstream shape is 512 x 64 B = 32 KiB per cluster (derived from
  [T5]); one cluster alone is twice the 16 KB data store (`npu.md:26`). The one place a stream
  could matter is refilling the banks: at `K = 256` one `A` tile and one `B` tile are 2 x 512
  words (`npu.md:194-195`), 1024 bus cycles at one word per cycle (`npu.md:231-234`), against 291
  array cycles (derived; not every tile is loaded fresh, so the real ratio is lower, and it is
  unmeasured). That path is the deferred bus-master DMA row (`npu.md:234`, `npu.md:341`).
- **Partitioning columns does not remove the shared operand.** Output-stationary needs every
  `A` byte at every column. Upstream pays for that with a private activation copy per cluster
  [T8]. The sky130 equivalent is an `A` tile of 8 x 256 = 2 KiB per cluster (`npu.md:194-195`),
  8 KiB over four, half the data store; or one 64-bit `A` bus fanned out to four clusters,
  which is the wide-bus problem the floorplan already has (`spec/floorplan-sketch.md:65-68`).
- **The recorded congestion cause is pin geometry, which partitioning does not change.** Port
  0's data pins are on a macro's south edge and port 1's data output on its north edge, and
  both ports carry array traffic (NOTES, "Signal pin edges"). A per-bank cluster changes which
  logic faces which edge, not that a bank's two data edges are opposite. A macro is
  699.89 x 677.565 um, about 95 PEs of the 5000 um^2 planning figure
  (`spec/floorplan-sketch.md:56-58`), so a 16-PE cluster would sit beside a macro six times its
  size. Inferred, not measured: the gain from locality is bounded by the macro footprint.

Reopen when an external memory or DMA path is un-deferred (see below).

## Lesson 2: dual weight streams per channel. Verdict: reject

Upstream needs two things: memory with headroom over one stream (the 1.5 above [T1]) and idle
token slots, which exist when `T <= T_MAX / 2` [T9][T10]. Neither exists here.

- **No headroom.** A 1rw1r macro gives 2 words per cycle and one operand needs 2 words per
  cycle, "both its ports are busy" (`npu.md:61-62`). The second port is already read every cycle
  to build the 64-bit k-vector (`spec/floorplan-sketch.md:41-42`). In sky130 the two ports
  double the width, not the rate. At the fallback the spare port is the host's fill port
  (`npu.md:64-68`, `npu.md:216-221`), so it is not free either.
- **No idle slot.** There is no token dimension: `M` is spatial. Once the skew has filled, every
  PE does a MAC each cycle (`npu.md:41-44`). The idle PE-cycles are the fill and drain of that
  skew, which wait on the dataflow and not on data supply, so a second stream could not use
  them (inferred from the dataflow, not measured).
- **The cost is large for a gain capped at 1.5x (derived).** Upstream adds a second front end
  with its own 512-beat FIFO [T5][T11], a read-only port that bypasses the arbiter [T13],
  duplicated activations per token slot and a second weight register [T12], and a second row
  assembler with a job merge [T14].

## Lesson 3: tile-op execution model. Verdict: reject as a model; one narrow part deferred

Mapping: the host already lowers the work (im2col and the tile loops, `npu.md:28`,
`npu.md:160-169`), and `START` plus seven configuration registers is already a fixed-format
tile op, one in flight (`npu.md:246-264`). What upstream adds is an on-chip core, per-unit
queues, tickets and an op list.

- **There are no units to order.** The model exists to sequence DMA, quantizer, MVM and vector
  units around one scratchpad [T16][T17][T18]. sky130-npu has one compute unit and folds bias,
  requantization and ReLU into its drain (`npu.md:44-46`).
- **The control core is out of proportion and out of scope.** Its two memories alone are
  128 + 64 = 192 KiB [T19], 12 times the 16 KiB data store (derived). A processor is out of
  scope (`CLAUDE.md:26-31`, `ROADMAP.md` "Not planned").
- **The measured loss is inside the tile, where a queue cannot reach it.** Per tile, the array
  needs `K + 35` cycles from `START` to `DONE`, on all four reference workloads (measured
  (simulated), `ARRAY_N = 8`, RTL `46fd2bb15ac0afc63df662d7f3e7d5d248a1be08`, record
  `verification/records/20261115T162752Z-87819ff5/`; passed, 0 failures):

  | Workload | Tiles | `K` | Cycles, `START` to `DONE`, summed | Per tile | Per tile minus `K` | Boundary share `35/(K+35)` | `U_array` |
  |---|---|---|---|---|---|---|---|
  | `mm-smoke` | 1 | 64 | 99 | 99 | 35 | 35.4 % | 0.6465 |
  | `mm-fc` | 64 | 256 | 18624 | 291 | 35 | 12.0 % | 0.8797 |
  | `conv-3x3-a` | 128 | 144 | 22912 | 179 | 35 | 19.6 % | 0.8045 |
  | `conv-3x3-edge` | 75 | 72 | 8025 | 107 | 35 | 32.7 % | 0.5495 |

  Tile counts are `ceil(M/8) x ceil(N/8)` from the shapes in `npu.md:297-302` (derived); that
  all four rows give exactly 35 is the cross-check. The 35 is the RTL's stall-then-drain
  sequence after the `K` feed cycles: WAIT `2N` = 16, DRAIN `N^2/4` = 16, TAIL 3
  (`rtl/README.md:85-92`). The same sum at `ARRAY_N = 4` is 15, and the `ARRAY_N = 4` record
  `verification/records/20261115T163224Z-22a70065/` agrees (`mm-fc`: 69376 cycles over 256
  tiles is 271 = 256 + 15; derived). No record measures a host gap: the suite loads each tile,
  runs it and reads it back in series, and overlap is "not exercised"
  (`verification/README.md:55-61`). `U_e2e` has no data.

**The part deferred.** Upstream's as-if overlap of one op's tail with the next op's start hides
a fixed per-op fill cost [T20][T22], the same effect as the 35 cycles. Doing it here needs two
things the repo does not have: a shadow accumulator (the deferred row at `npu.md:345`, and
[0001](0001-dataflow.md) "Consequences"), and a controller that accepts the next `START` before
`DONE`; today `START` while `BUSY` is `ERR_CODE` 5 (`npu.md:262-264`, `rtl/README.md:75-76`). A
queue without the shadow accumulator could remove only what the host cannot already do while
`BUSY`. Run configuration is latched at `START`, so the next tile's registers can be written
during the current tile (`rtl/README.md:67-69`); only `START` and the `BIAS` writes, which are
dropped while `BUSY`, must wait. That is at most 1 + 8 register transfers per tile at `N = 8`
(derived from `npu.md:246-259`, unmeasured), and none of the 35 in-tile cycles.

## Decision

The next generation does not adopt the weight-streaming MVM architecture.

| Lesson | Verdict | Deciding sky130 constraint |
|---|---|---|
| Per-channel weight streaming | reject | no DDR channel and a one-cycle macro read, so the latency FIFO is pure cost; the shared operand and the macro pin geometry survive partitioning |
| Dual weight streams | reject | memory rate equals consumer rate (1.0, not 1.5); no idle token slot |
| Tile-op model | reject as a model; one part deferred | one compute unit, no processor in scope; the measured loss is inside the tile |

This is a written decision, not a spec change: no row of `spec/npu.md` is edited. Three reasons
the deferred part is not specified now:

1. Its gain is small by construction and unmeasured: at most 9 register transfers per tile, and
   no record times the host gap between `DONE` and the next `START`.
2. It cannot pay without the shadow accumulator, which is already a deferred row with an owner
   "to file" (`npu.md:345`).
3. The target has not routed (`README.md` status, `ROADMAP.md`), and the open routing ruling in
   #43 may change decision 0002 or move to the 4 x 4 fallback. The reasoning of `CLAUDE.md:45-47`,
   that stretch-size requirements do not drive the architecture before the target closes, is
   about array size; it is applied here by analogy to a later generation's features.

**Recorded for the owner of the overlap row (`npu.md:345`).** That issue should cover accepting
the next tile's configuration while the current tile drains. That changes the `ERR_CODE` 5 rule
and so needs its own decision record at that time. Nothing here relaxes a ratified row.

## Reopen conditions

- A bus-master DMA or any external memory path is un-deferred (`npu.md:234`, `npu.md:341`):
  re-evaluate lesson 1 with a per-bank streamer whose FIFO is sized from that path's round trip,
  and with a measured `U_e2e`.
- #43 is ruled to change the macro or its wrapper (decision 0002): per-bank locality can be
  re-examined against the new pin edges. This record does not pre-judge that ruling.
- A record measures the host gap between tiles: re-weigh the queued-issue part of lesson 3.

## Not decided here

- The #43 routing ruling. None of the three lessons removes the need for a wide macro data path
  per operand, so this record adds no option to it.
- `asap7-npu`, which was not examined.
- Upstream's LLM-specific parts (Q4_K and Q8_0 formats, attention, KV cache, vector unit),
  which are outside this block's scope (no floating point, `CLAUDE.md:30-31`).

## Upstream cites

All cites are `file:line` at `jwkim04/tesseract-npu` commit
`93a57db9a060399dd6cba813f31b216fa0c4ae71`. Nothing is quoted; each row says what the lines
state.

| Id | Cite | States |
|---|---|---|
| T1 | `docs/spec.md:60-63` | one weight stream is 64 B per cycle, 12.8 GB/s at 200 MHz; a DDR4-2400 channel peaks at 19.2 GB/s, so a cluster reads two streams when `T <= T_MAX/2`; the goal is an unbroken beat supply, not more MACs |
| T2 | `docs/spec.md:64-66` | weight traffic stays per channel; cluster `c` reads only channel `c` |
| T3 | `docs/spec.md:168-170` | cluster `c` gets its weight streams from channel `c` only; the weight rows are split across the four channels |
| T4 | `docs/spec.md:513-517` | the requester reads a channel's contiguous row range back to back in bursts of 64 beats |
| T5 | `docs/rtl-mvm.md:169-173` | FIFO sizing: round trip plus 64 must fit in the FIFO; the default 512 beats covers a round trip of about 440 cycles; cost is a 512 x 512-bit memory per cluster |
| T6 | `docs/rtl-mvm.md:181-182` | the `T` tokens share every weight beat |
| T7 | `docs/spec.md:522-523`, `docs/spec.md:538-541`, `docs/spec.md:552-553` | 128 lanes per beat for Q4_K, 64 for Q8_0; 128 MACs per cycle per cluster at `T = 1`; at `T = 1` neither the weight nor `x` is shared, so nothing is packed |
| T8 | `docs/spec.md:543-550`, `docs/spec.md:559-561`, `docs/rtl-mvm.md:189-193` | each cluster holds a full activation buffer, 37,376 B per token at `K_MAX` 32768; the release image has `T_MAX` 4; the activation vector is copied to the local buffers of all clusters at the start of an MVM |
| T9 | `docs/rtl-mvm.md:642-645` | a cluster is bound by its own stream, not its DDR bank; with the dual stream the token slots at and above `T_MAX/2`, idle when `T` is at most half, carry the second stream |
| T10 | `docs/rtl-mvm.md:647-649` | the dual stream applies when the build enables it, the run-time input is on, the op is a weight MVM and `T <= T_MAX/2` |
| T11 | `docs/rtl-mvm.md:657-666` | the cluster's rows split into two halves, each with its own front end, paired beat by beat in lockstep |
| T12 | `docs/rtl-mvm.md:679-685` | activations are written again into the upper token slots; a second weight register feeds the MAC lanes |
| T13 | `docs/rtl-mvm.md:711-713` | stream B has a read-only memory port of its own that does not go through the arbiter |
| T14 | `docs/rtl-mvm.md:697-704` | a second row assembler per cluster, with the jobs of the two merged in front of the job path |
| T15 | `docs/spec.md:41-43` | the on-chip control core issues every tile op; the host loads firmware and launches kernels and runs no instruction programs |
| T16 | `docs/spec.md:108-111` | the op list, the 256-bit tile op, and the issue path with one in-order queue per unit; the ticket |
| T17 | `docs/spec.md:73-76` | strict sequential semantics inside a unit; across units only dependencies, joins and fences order tile ops |
| T18 | `docs/spec.md:739-743`, `docs/spec.md:776-784` | a tile op is a fixed 256 bits, issued by the control core; the instruction list has DMA ops (`LD`, `ST`, `KVST`), a quantizer op (`QACT`), `MVM` and vector-unit ops (`VOP`) |
| T19 | `docs/spec.md:1112-1114`, `docs/spec.md:1131-1135` | a simple in-order core that issues tile ops asynchronously; Ibex RV32IMC with a 128 KiB instruction memory and a 64 KiB data memory |
| T20 | `docs/spec.md:572-576` | consecutive MVMs may overlap when independent, which hides the 1 to 2 us (estimate) fill cost every MVM pays |
| T21 | `docs/spec.md:132-145` | the tree provides only the Alveo U200 pieces; the SoC column of the target table names SRAM macros as the tech wrapper, marks the platform adapter "Not provided" and leaves the core parameters "Open"; the RTL elaborates only at a 512-bit beat and 128 lanes, so other widths are a porting task |
| T22 | `docs/spec.md:1040-1042` | the fill, broadcast and tail inside an MVM are counted as a loss against the stream limit |
