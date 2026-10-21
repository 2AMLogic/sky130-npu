# Work Log

Chronological record of merged PRs and closed issues. Maintained by the Guide
triage agent; entries are grouped by date, newest first.

### 2026-10-21

- **PR #28**: Bump Repo Skills 0.24.3 -> 0.24.7

### 2026-10-20

- **PR #24**: feat(rtl): parameterised output-stationary NPU RTL for ARRAY_N 4 and 8
- **PR #20**: feat: add bit-exact integer golden model and reference workload vectors
- **PR #9**: ci: grade a committed klt signoff manifest on every push and PR
- **Issue #10** (closed): Integer golden model (INT8, INT32 accumulate, requantization)
- **Issue #5** (closed): T1 item 10: commit a klt signoff block manifest and a CI job that keeps it graded

### 2026-10-18

- **PR #22**: docs(spec): pin conv draw order and workload vector file format
- **PR #19**: docs(spec): state fallback overlap holds only for K <= 254
- **Issue #21** (closed): spec: pin conv workload operand layout and .hex file format in section 8
- **Issue #17** (closed): spec: fallback (N=4, K=256) cannot hold next A tile and result in one 2 KB bank

### 2026-10-17

- **PR #16**: feat: pin sky130 PDK and toolchain, add klt flow smoke run
- **PR #14**: feat: add cocotb + Icarus verification harness skeleton with CI
- **PR #13**: docs(spec): ratify target spec, output-stationary dataflow and SRAM-source decisions
- **PR #2**: chore(loom): commit the Loom merge-driver .gitattributes
- **PR #1**: chore(loom): Install Loom 0.19.1180
- **Issue #15** (closed): Ignore verification/sim_build and .venv in .gitignore
- **Issue #7** (closed): T1 item 9: cocotb + Icarus harness skeleton with CI, ahead of the golden model and RTL
- **Issue #6** (closed): PDK and toolchain bring-up: pin sky130 and klt, and commit a smoke run through synthesize, place-and-route, DRC, LVS, ERC and STA
- **Issue #3** (closed): Draft and ratify the target spec
