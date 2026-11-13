# Work Log

Chronological record of merged PRs and closed issues. Maintained by the Guide
triage agent; entries are grouped by date, newest first.

### 2026-11-12

- **PR #118**: Bump Repo Skills 0.25.10 -> 0.26.1
- **PR #116**: refactor(rtl): remove hand-synced SRAM blackbox, use synthesize defines
- **Issue #101** (closed): Remove npu_sram_bank_bb.v: hand-synced copy of the macro wrapper, blocked on klt pin bump

### 2026-11-11

- **PR #114**: build: bump klt pin to 0.9.1 and unify on flow/toolchain.json
- **Issue #113** (closed): Bump the klayout-tools pin from 0.8.0 to the fleet version
- **PR #110**: layout: record macro pin-edge geometry as structural cause of routing congestion
- **PR #108**: layout: floorplan re-run on klt 0.9.1 with sourced counts; density worse, halo blocked by klt
- **PR #106**: layout: record four floorplan attempts, none routes (congestion counts not re-derived)
- **PR #105**: verify: gate-level run uses pinned OpenRAM macro Verilog, retire SRAM stand-in
- **Issue #104** (closed): Retire SRAM stand-in model: pinned macro Verilog now exists (#51 closed)
- **PR #92**: layout: add npu_top place-and-route request and runner with unrouted first record

### 2026-11-10

- **PR #100**: test: fold bank-window BIAS alias check into live bit-exact test
- **Issue #68** (closed): Remove orphaned test_bank_alias_bias.py: never run, duplicates test_bitexact and Bench
- **PR #95**: build: wire pnpm test/check scripts to the bit-exact verification runner
- **Issue #18** (closed): Remove vacuous package.json stub scripts (check:ci/check:all/test/lint always exit 0)

### 2026-11-07

- **PR #89**: feat(sram): generate and pin 1024x32 OpenRAM macro views
- **Issue #51** (closed): Generate and pin the 4 KB (1024x32) OpenRAM macro views: LEF, GDS, Verilog, Liberty
- **PR #87**: docs(flow): record cold re-run of setup.sh at final hash pins
- **Issue #74** (closed): Repo-local pinned fetch of sky130_fd_bd_sram cell views so OpenRAM runs without a worker change
- **PR #85**: Bump Repo Skills 0.25.1 -> 0.25.10

### 2026-11-06

- **PR #83**: verify: gate-level bit-exact run on the synthesized netlist with an SRAM stand-in
- **Issue #82** (closed): verification: run the bit-exact suite on the recorded sky130 gate-level netlist

### 2026-11-05

- **PR #79**: ci: run relocated-layout seam test in rtl-elaborate
- **Issue #78** (closed): CI never runs test_relocated_layout.py: wire it into rtl-elaborate
- **PR #77**: feat(flow): hash-pin OpenRAM toolchain wheels and libs.tech payload
- **Issue #76** (closed): Pin pip wheel hashes and ciel PDK payload hash for flow/sram/setup.sh
- **PR #75**: feat(flow): pinned repo-local OpenRAM toolchain and 16x32 probe run
- **Issue #8** (closed): Track the RTL, integer golden model and testbenches the ports pin

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
