# Work Log

Chronological record of merged PRs and closed issues. Maintained by the Guide
triage agent; entries are grouped by date, newest first.

### 2026-10-31

- **PR #71**: Bump Repo Skills 0.24.7 -> 0.25.1

### 2026-10-30

- **Issue #35** (closed): Tag rtl-v0.1.0 once #12 shows bit-exactness
- **PR #67**: test(verification): record passing bit-exact runs at ARRAY_N=4 and 8 on current rtl head
- **Issue #66** (closed): Re-run the bit-exact ledger (#12 suite) on current main so rtl-v0.1.0 can be tagged (#35)
- **PR #64**: build: parameterize harness RTL and PDK-seam directories for stamped ports
- **Issue #62** (closed): Parameterize the verification harness RTL and PDK-seam paths so stamped ports can run it

### 2026-10-27

- **PR #59**: build: pin klayout-tools to the 0.8.0 PyPI release
- **Issue #58** (closed): Bump klayout-tools pin 67e684ed9b2b → 0.8.0
- **PR #55**: feat(synth): commit sky130 gate-level netlist with SRAM black boxes and attest T1 item 1
- **PR #54**: test(verification): add klt functional-verification request and ARRAY_N=8 envelope
- **Issue #42** (closed): T1 item 1 (design sources): synthesize npu_top to sky130_fd_sc_hd with SRAM macros black-boxed, and attest the netlist
- **PR #53**: feat(manifests): attest T1 item 9 testbenches shipped
- **Issue #49** (closed): T1 item 9 (testbenches shipped): testbench inventory and klt signoff --attest 9

### 2026-10-24

- **PR #39**: fix(rtl): qualify BIAS decode with in_regs so bank writes never alias it
- **PR #38**: feat(verification): bit-exact cocotb suite for npu_top with mutation check and ledger records
- **PR #36**: feat(rtl): pin OpenRAM sky130 SRAM macros and add macro wrapper for npu_sram_bank
- **Issue #37** (closed): bug(rtl): bank-window write at offset 0x100-0x13F also writes BIAS
- **Issue #25** (closed): Pin the SRAM macro and write the npu_sram_bank wrapper (reuse.lock.json owner)
- **Issue #12** (closed): Bit-exact cocotb testbenches against the golden model
- **Issue #11** (closed): Parameterised NPU RTL with array size as one parameter

### 2026-10-23

- **PR #33**: docs(signoff): attest repo hygiene and extend README reproduction steps
- **PR #32**: feat: record item 6 not_applicable statement for the digital spec
- **Issue #31** (closed): T1 item 10: complete the README reproduction steps and attest repo hygiene with klt signoff --attest 10
- **Issue #30** (closed): T1 item 6: record the bound not_applicable statement for the digital spec (no statistical row)

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
