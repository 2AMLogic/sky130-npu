# sky130-npu specification

Status: **ratified on merge** of the PR that introduces this file (decision
record: [0001](decisions/0001-dataflow.md), [0002](decisions/0002-sram-source.md)).
"Ratified" here means the spec PR passed Judge review and merged; every row
below is either a decided value or `deferred` with a reason and an owner. If a
human ratifier is wanted, that is a reading change to be recorded in `spec/decisions/`.

Rules that bind this document:

- Changes go through a new decision record under `spec/decisions/`. No agent
  relaxes a row to make a result pass.
- A figure marked **estimate** is derived and unmeasured. Nothing here is a
  measured result.
- Throughput is quoted only as `MACs/cycle x clock`, with the utilization
  observed in simulation on a named workload (section 8) and the corner the
  clock came from.

## 1. Parameters

| Parameter | Target | Fallback | Stretch | Status |
|---|---|---|---|---|
| MAC array `ARRAY_N` | 8 (8 x 8, 64 MACs) | 4 | 16 | Decided. RTL parameter, legal values {4, 8, 16}. |
| Operand / accumulator | INT8 x INT8 -> INT32, both signed two's complement | same | same | Decided (section 3). |
| Dataflow | **output-stationary** | same | same | Decided, [0001](decisions/0001-dataflow.md). Changes the README draft ("weight-stationary"). |
| SRAM banks (total) | 4 banks x 4 KB = 16 KB | 2 banks x 2 KB = 4 KB | 8 banks x 8 KB = 64 KB | Decided (section 5). |
| SRAM macro port | 1rw1r, 32-bit word, byte write mask | same | same | Decided. Source: [0002](decisions/0002-sram-source.md). |
| Operations | GEMM; 2-D convolution lowered to GEMM by im2col (done by the host); per-tile bias, requantize, ReLU | GEMM only | adds depthwise convolution | Target and fallback decided. Depthwise: `deferred` (section 9). |
| Maximum reduction depth `K_MAX` | 256 | 256 | 256 | Decided. Larger K is `deferred` (section 9). |
| Host interface | Wishbone B4 classic, 32-bit, slave only | same | same | Decided (section 6). |
| Signoff clock, post-route STA, slow corner | 50 MHz | 25 MHz | 100 MHz | Decided as the target. Reachability is unverified, see gap G1 (section 7). |
| Numerical correctness | bit-exact vs the integer golden model | same | same | Decided (section 3, 4). |
| Signoff | DRC + LVS clean, STA closed at every corner in section 7 that has all its views | same | same | Decided. A corner with a missing view is reported as a gap, never as closed. The 50 MHz target is not met until the slow-corner macro view exists (G1): `tt` alone closing does not satisfy it. |

The 16 x 16 / 100 MHz / 64 KB column is recorded as parameter ranges only.
Nothing in this spec is designed for it (CLAUDE.md: stretch does not drive the
architecture).

## 2. Array and dataflow

`ARRAY_N x ARRAY_N` processing elements. PE (m, n) holds one INT32
accumulator and computes `acc += A[m][k] * B[k][n]` once per cycle for
`k = 0 .. K-1`. Operands are skewed so that PE (m, n) sees step k at cycle
`k + m + n`; A moves west to east, B moves north to south. After K steps the
accumulators are drained, biased, requantized and written as INT8. The skew
and drain latency are microarchitecture, fixed in the RTL issue, not here.
Results must not depend on tile order or skew: integer addition is exact and
associative (section 3.1), so any schedule gives identical bits.

Per cycle the array consumes one `ARRAY_N`-byte A vector and one `ARRAY_N`-byte
B vector (`A[0..N-1][k]` and `B[k][0..N-1]`).

Bandwidth at 8 x 8, per cycle, in steady state:

| Stream | Bytes | 32-bit words |
|---|---|---|
| A read | 8 | 2 |
| B read | 8 | 2 |
| Output write (INT8, once per tile of K cycles) | 64 B / K | 16 words / K |

A 1rw1r macro offers 2 word accesses per cycle, so one bank sustains exactly one
operand stream and both its ports are busy. That forces **ping-pong double
buffering**: while the array reads bank X on both ports, the host fills the
partner bank. Bank count follows: `2 operands x 2 (ping-pong) = 4` at
`N = 8`. At `N = 4` an operand needs 1 word/cycle, one port suffices, the other
port is free for host fill, and no bank-level ping-pong is needed: `2` banks. The
host fills the next tile at a different offset in the same bank (section 5.3).
That overlap has a capacity limit: the current A tile, the next A tile and the
result tile need `2 x (K x 4) + 16 = 8K + 16` bytes in a 2 KB bank, so it holds
only for `K <= 254` (`8 x 254 + 16 = 2048`; at `K = 255`, 2056 B; at `K = 256`,
2064 B). For `K` of 255 or 256 the host loads the next tile only after the
current tile's compute has finished (serialized; correctness unchanged).
Decision record: [0003](decisions/0003-fallback-overlap-limit.md). At `N = 16`
an operand needs 4 words/cycle, so two banks interleaved, doubled for
ping-pong: `8`. These are the README's 2 / 4 / 8.

Answer to "does the macro sustain the array or is double buffering required":
bandwidth is sustained only with double buffering at `N >= 8`, and only if the
macro's read cycle fits the clock. The latter is unverified (gap G1).

Utilization cost the spec accepts and does not hide: with no shadow
accumulator, drain and requantization of tile *t* stall the array before tile
*t+1* starts. Overlapping them is an RTL decision; the achieved utilization is
what section 8 defines and measures.

## 3. Arithmetic

### 3.1 Accumulation

- `A`, `B`: INT8, range -128..127 (-128 allowed).
- Product: INT16. `acc[m][n] = sum_{k<K} A[m][k]*B[k][n]` computed exactly.
- Bound: `|acc| <= K_MAX * 128 * 128 = 2^22`. The accumulator is INT32 and
  cannot overflow.
- `bias[n]`: INT32, **required** to lie in `[-2^30, 2^30)`, so
  `t[m][n] = acc[m][n] + bias[n]` also fits INT32 without wrapping. Out of
  range bias is outside the contract (no hardware check).

### 3.2 Requantization

Inputs: `t` (INT32), `mult` (UINT16, 0..65535), `shift` (0..47), `relu` (bool).
Per tile operation, one `mult` and one `shift` apply to all outputs (per-channel
parameters are `deferred`, section 9). Zero point is 0 (symmetric); asymmetric
quantization is `deferred`.

```
p = t * mult                                 # exact integer, |p| < 2^47
r = (p + (1 << (shift - 1))) >> shift        # shift > 0; arithmetic (floor) shift
r = p                                        # shift == 0
if relu: r = max(r, 0)
out = min(max(r, -128), 127)                 # saturate to INT8
```

Rounding is round-half-up: ties go toward +infinity (`-1.5 -> -1`, `1.5 -> 2`).
This is **not** round-half-away-from-zero. ReLU is applied after rounding and
before saturation; since saturation is monotonic this equals ReLU after
saturation. Order of bias, then multiply, then shift, is fixed.

Worked examples (checked with an exact-integer throwaway script; not committed):

| t | mult | shift | relu | p | out | Case |
|---|---|---|---|---|---|---|
| 100 | 1 | 1 | 0 | 100 | 50 | exact |
| 3 | 1 | 1 | 0 | 3 | 2 | tie, +1.5 rounds up |
| -3 | 1 | 1 | 0 | -3 | -1 | tie, -1.5 rounds up |
| -1 | 1 | 1 | 0 | -1 | 0 | tie, -0.5 rounds up |
| 5 | 3 | 2 | 0 | 15 | 4 | 3.75 -> 4 |
| -5 | 3 | 2 | 0 | -15 | -4 | -3.75 -> -4 |
| 1000 | 40000 | 20 | 0 | 40000000 | 38 | 38.15 -> 38 |
| 10000 | 1 | 4 | 0 | 10000 | 127 | 625 saturates high |
| -10000 | 1 | 4 | 0 | -10000 | -128 | -625 saturates low |
| -10000 | 1 | 4 | 1 | -10000 | 0 | ReLU clamps before saturation |
| 2147483647 | 65535 | 0 | 0 | 140735340806145 | 127 | INT32 max, no shift |
| -2147483648 | 65535 | 0 | 0 | -140735340871680 | -128 | INT32 min, no shift |
| 2147483647 | 65535 | 47 | 0 | 140735340806145 | 1 | INT32 max, widest shift |
| -2147483648 | 65535 | 47 | 0 | -140735340871680 | -1 | INT32 min, widest shift |

The last four rows are reachable only by calling `requantize` directly;
with the section 3.1 bias bound they cannot occur from `gemm`, and they stay in
the test set because the function is specified for all INT32 inputs.

## 4. Golden model interface

The golden model is written once in this repo (target path
`verification/golden/`, the seam created by issue #7) and is committed by a
later issue. **No model code is committed by this spec.** Python, exact
integers (Python `int` or `numpy.int64`; never floating point), no dependency
on the RTL.

```
gemm_acc(a, b, bias)                 -> acc  : int32[M][N]
requantize(t, mult, shift, relu)     -> out  : int8[...]       # elementwise, section 3.2
gemm_int8(a, b, bias, mult, shift, relu) -> (acc, out)
im2col(x, kh, kw, stride, pad)       -> a    : int8[M][K]
conv2d_int8(x, w, bias, stride, pad, mult, shift, relu) -> (acc, out)
pack_a(a_tile, n) / pack_b(b_tile, n) -> bytes   # bank images, section 5.2
```

Shapes and layouts:

- `a`: `int8[M][K]`, row-major. `b`: `int8[K][N]`, row-major. `bias`: `int32[N]`.
  `1 <= K <= K_MAX`; `M` and `N` are arbitrary positive integers.
- Edge tiles: the host zero-pads `M` and `N` up to multiples of `ARRAY_N`. The
  golden model is defined on the unpadded shapes; padded rows and columns of
  hardware output are ignored. Zero-padded bias entries are 0.
- `im2col`: input `x` is `int8[H][W][C]`, zero padding value 0 (zero point 0).
  Row `m = oh * OW + ow`; column `k = (i * KW + j) * C + c` for kernel offset
  `(i, j)` and channel `c`, with `OH = (H + 2*pad - KH)//stride + 1` (same for
  OW). Weights `w`: `int8[KH][KW][C][F]` reshape to `b[k][f]` with the same
  `k`. Output `out[m][f]` reads as `O[oh][ow][f]`.
- Required property, tested bit-for-bit against RTL: `conv2d_int8` equals
  `gemm_int8(im2col(x), reshape(w), ...)`, and equals a direct nested-loop
  convolution.
- Every RTL result is compared to `out` (and `acc` where observable) bit for
  bit. "Close enough" is a failure.

## 5. SRAM

### 5.1 Banks

| | Target | Fallback | Stretch |
|---|---|---|---|
| Banks | 4 | 2 | 8 |
| Bank size | 4 KB (1024 x 32) | 2 KB (512 x 32) | 8 KB (2048 x 32) |
| Port | 1rw1r, 32-bit, 8-bit write granularity | same | same |
| Roles | bank 0, 1: A ping-pong; bank 2, 3: B ping-pong | bank 0: A; bank 1: B | A: 4 banks (2 interleaved x 2 ping-pong); B: same |

Macro source: [0002](decisions/0002-sram-source.md).

### 5.2 Bank image

Operand data is stored as `K` consecutive **k-vectors** of `ARRAY_N` bytes.
A k-vector for A has byte `i` = `A[i][k]`; for B, byte `j` = `B[k][j]`. Byte 0 is
the least significant byte of the first 32-bit word (little endian). Vector
stride is `ARRAY_N` bytes. At `N = 8` one operand tile of `K_MAX` takes
`256 x 8 = 2 KB`, half of a bank; the rest of an A bank holds result tiles and
the rest of a B bank is unused in this spec (a second weight tile is
`deferred`, section 9).

Result tile: `ARRAY_N x ARRAY_N` INT8, row-major (byte `m*N + n`), written at
`OUT_OFF` in `OUT_BANK`. `OUT_BANK` may equal `A_BANK` or `B_BANK` only if the
result range `[OUT_OFF, OUT_OFF + N*N)` overlaps neither operand range in that
bank (`[A_OFF, A_OFF + K*N)`, `[B_OFF, B_OFF + K*N)`). At the target the result
goes to the idle A ping-pong bank; at the fallback (no idle bank) it goes to
bank 0 beside the A tile: a 1 KB operand tile (`K_MAX x 4`) plus a 16 B result
tile fit a 2 KB bank. That counts one operand tile only. With the next A tile
also resident for fill/compute overlap (section 2) the bank needs
`8K + 16 <= 2048`, i.e. `K <= 254`. At `K` of 255 or 256 the next tile is loaded
after the current tile's compute finishes (serialized; results unchanged), and
any fallback utilization figure quoted at `K >= 255` must come from simulation
with that serialized load (section 8). `K_MAX`, `CAP` and the golden model
interface are unchanged, see [0003](decisions/0003-fallback-overlap-limit.md).
Decision record: [0001](decisions/0001-dataflow.md), addendum.

### 5.3 Access rules

- While BUSY, a host access to the active A bank or active B bank returns bus
  error; all other banks are host-accessible (that is the ping-pong). Exception,
  `ARRAY_N = 4` only: the array reads each operand through the read port alone,
  so the host may access an active bank through the RW port outside the active
  operand range and outside the result range (that is how the next tile is
  filled in the fallback). A host access inside either range returns bus error.
- Result writes use the macro's RW port and take priority over host writes
  on that bank; the host access waits.
- Bank sizes and port count are fixed by this spec; port **timing** at the
  signoff clock is gap G1.

## 6. Host interface

Wishbone B4 classic, 32-bit data, byte-addressed, `SEL[3:0]` honored,
slave only. `ACK` for registers within 1 cycle; for a bank window when the
macro port is granted; `ERR` per section 5.3. One level interrupt `irq`
(DONE or ERR, gated by `IRQ_EN`). No bus-master DMA: "DMA-style load/store" is
satisfied by the bank window below (host burst writes, one word per bus cycle).
A bus-master DMA and pipelined Wishbone are `deferred`.

Address map (offsets from the block base):

| Range | Contents |
|---|---|
| `0x0000-0x00FF` | control / status registers |
| `0x0100-0x013C` | `BIAS[0..15]`, INT32; entries `>= ARRAY_N` reserved, read 0 |
| `0x1000 + 0x1000*b` | bank `b` window (target: `b` = 0..3, 4 KB each). Fallback: 2 KB banks at the same bases. |

Registers (reset value 0 unless noted):

| Offset | Name | Access | Fields |
|---|---|---|---|
| `0x00` | `ID` | RO | `0x4E505530` |
| `0x04` | `SPEC` | RO | `[7:0]` spec version (1) |
| `0x08` | `CAP` | RO | `[7:0]` `ARRAY_N`; `[15:8]` bank count; `[23:16]` log2 bank bytes; `[31:24]` log2 `K_MAX` |
| `0x0C` | `CTRL` | W | bit0 `START` (self-clearing); bit1 `SOFT_RESET`; bit2 `IRQ_EN` (RW) |
| `0x10` | `STATUS` | RW1C | bit0 `BUSY` (RO); bit1 `DONE`; bit2 `ERR`; `[11:8]` `ERR_CODE` |
| `0x14` | `K` | RW | `[8:0]` reduction depth, 1..`K_MAX` |
| `0x18` | `BANKS` | RW | `[7:0]` `A_BANK`; `[15:8]` `B_BANK`; `[23:16]` `OUT_BANK` |
| `0x1C` | `A_OFF` | RW | byte offset in `A_BANK`, multiple of `ARRAY_N` |
| `0x20` | `B_OFF` | RW | byte offset in `B_BANK`, multiple of `ARRAY_N` |
| `0x24` | `OUT_OFF` | RW | byte offset in `OUT_BANK`, multiple of 4 |
| `0x28` | `REQ_MULT` | RW | `[15:0]` `mult` |
| `0x2C` | `REQ_CTRL` | RW | `[5:0]` `shift` (0..47); bit8 `RELU` |
| `0x30` | `PERF_CYCLES` | RO | cycles from `START` accepted to `DONE`, saturating; last operation |

`ERR_CODE`: 1 = `K` out of range; 2 = misaligned or out-of-bank offset or bank
index; 3 = the result range overlaps the `A` or `B` operand range in a shared bank (section 5.2); 4 = `shift > 47`; 5 = `START`
while BUSY. On ERR no bank is written.

## 7. PVT corners and STA

Corner names are taken from the original issue; library file names follow the
skywater-pdk convention `sky130_fd_sc_hd__<corner>.lib`. **None of these were
checked against an installed PDK**: no PDK is pinned yet (issue #6 pins it and
confirms the names).

| Corner | Std-cell Liberty | Use | SRAM macro Liberty view |
|---|---|---|---|
| `ss_100C_1v60` | `sky130_fd_sc_hd__ss_100C_1v60.lib` | setup signoff (the 50 MHz figure) | **not known to exist** (gap G1) |
| `tt_025C_1v80` | `sky130_fd_sc_hd__tt_025C_1v80.lib` | informational | expected (OpenRAM's default characterization is typical 1.8 V 25 C); name unverified |
| `ff_n40C_1v95` | `sky130_fd_sc_hd__ff_n40C_1v95.lib` | hold signoff | **not known to exist** (gap G2) |

Gaps, stated rather than assumed:

- **G1**: the macro's Liberty at the slow corner. Without it the 50 MHz
  claim cannot be closed through a macro at the slow corner. Resolution path:
  issue #6 inventories the macro views from the pinned source. If only a typical
  view exists, the spec records that STA through the macro is closed at that
  corner only; the 50 MHz target is then reported "closed at tt, unverified at
  ss", never "closed". Also unknown: whether the macro read access time fits a
  20 ns cycle with the surrounding logic. The fallback (25 MHz) exists for this.
- **G2**: the same for the fast corner (hold).
- Where a macro Liberty view comes from must be recorded next to every timing
  result that passes through it (source, commit, generator config).

## 8. Reference workloads and utilization

Named by layer shape. All use `ARRAY_N = 8` for tile counts; shapes are
independent of `ARRAY_N`.

| Id | Kind | Shape | Notes |
|---|---|---|---|
| `mm-smoke` | matmul | M=8, K=64, N=8 | one tile |
| `mm-fc` | matmul | M=64, K=256, N=64 | 64 tiles, `K = K_MAX` |
| `conv-3x3-a` | conv via im2col | input 16x16x16, kernel 3x3, stride 1, pad 1, F=32 | M=256, K=144, N=32 |
| `conv-3x3-edge` | conv via im2col | input 14x14x8, kernel 3x3, stride 1, pad 1, F=20 | M=196, K=72, N=20: M, N not multiples of 8 |

Inputs are generated, not hand-written. Generator: SplitMix64, 64-bit state,
seed = the workload id's ASCII bytes read as a big-endian integer (truncated to
64 bits by keeping the **last** 8 bytes). Draw order: `A` row-major, `B` row-major
(`b[k][n]`), then `bias`; for `conv-*` the draws are the input tensor
`H x W x C`, then the flat `K x F` weights, then `bias`, and `a.hex` holds the
im2col matrix (decision 0004). Each int8 is the low 8 bits of one draw interpreted as
two's complement; each bias is `(draw & 0xFFFF) - 32768`. `mult` is 40000 for
`conv-*` and 1 for `mm-*`. `shift = max(0, bit_length(max|t| * mult) - 7)`
over the workload's full `t`, `relu = 1` for `conv-*` and 0 for `mm-*`.
The committed integer inputs and expected outputs live under
`verification/workloads/<id>/` (created with the golden model, the #7 harness;
files `a.hex`, `b.hex`, `bias.hex`, `params.json`, `expected_out.hex`; their
format and the `params.json` keys are pinned in
`spec/decisions/0004-workload-vector-layout.md`).

Utilization is a quantity to be observed in simulation, never assumed:

```
U_array = (M * K * N) / (cycles(START..DONE, summed over tiles) * ARRAY_N^2)
U_e2e   = same numerator over cycles including host loads of the bank windows
```

where `cycles` is `PERF_CYCLES` summed over tile operations, and a tile padded
at the edges counts only its useful `M*K*N` MACs in the numerator.
Peak throughput = `ARRAY_N^2 x clock`; quoted throughput = peak `x U_array`,
named workload and clock-corner attached. Nothing here is measured.

## 9. Deferred rows

Owner issues that do not exist yet are marked "to file"; the first issue that
needs the row files it.

| Item | Reason | Owner |
|---|---|---|
| Depthwise convolution (stretch) | Needs a different tile mapping; not required before the target closes | to file (stretch tier, tracked from #4) |
| `K > K_MAX` | Needs an INT32 partial-sum spill path | to file; hit by RTL issue if a workload needs it |
| Per-channel `mult`/`shift`, nonzero zero point | Not needed by reference workloads | to file |
| Bus-master DMA, hardware im2col address generator, pipelined Wishbone | Host-side lowering is enough to verify the datapath | to file |
| Second weight tile resident in a B bank | Capacity left in the B bank is unused | to file |
| Macro Liberty views at ss/ff (G1, G2) | Pinned PDK/macro source not yet available | #6 |
| Exact macro pin in `reuse.lock.json` | File does not exist yet; see [0002](decisions/0002-sram-source.md) | #6 creates it with the first pin |
| Drain / requantization overlap with next tile | Microarchitecture; measured by `U_array` | RTL issue (T1 item 6, tracked in #4) |

## 10. PDK-independent vs PDK-specific files (the port seam)

`asap7-npu` is ported from this repo: the golden model, RTL and testbenches are
designed here and stamped into it. The seam is **one module boundary**: the SRAM
bank wrapper `npu_sram_bank` (ports `clk`, `rw` port, `r` port, byte mask,
parameters `DEPTH_WORDS`, `WORD_BITS`). Everything on the NPU side of it is
PDK-independent.

| PDK-independent (stamped) | PDK-specific (sky130 only) |
|---|---|
| `spec/` (except section 7 corner file names and 0002) | `rtl/pdk/sky130/` : `npu_sram_bank` wrapper over the macro; behavioral model for simulation lives next to it |
| `verification/golden/`, `verification/workloads/`, cocotb tests | synthesis constraints, floorplan, macro placement, `layout/` |
| `rtl/` array, PEs, controller, requantizer, Wishbone slave | STA corner lists, Liberty paths, `reuse.lock.json` macro pin |
| `ARRAY_N` and bank-count parameters | `klt` signoff manifest values tied to sky130 |

## 11. Floorplan

See [floorplan-sketch.md](floorplan-sketch.md): banks, array, bus widths, SRAM
area fraction (estimate) and a congestion note.
