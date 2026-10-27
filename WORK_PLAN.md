# Work Plan

Roadmap generated from GitHub label state by the Guide triage agent. Only the
region between the markers is machine-generated.

<!-- guide:plan-body:start -->
## Operator Attention: Merge-Risk-Hold Pileup

Judge-approved PRs under a hold (`loom:blocked` or `loom:operator`) — only a human merge decision is missing.

_None._

## Very Important

`loom:very-important` (one counts per workspace); every stage takes these first.

_None._

## Important

`loom:important`; taken before unlabelled work.

_None._

## Ready

Human-approved issues ready for implementation (`loom:issue`).

_None._

## In Progress

Issues currently being built (`loom:building`).

- **#42**: T1 item 1 (design sources): synthesize npu_top to sky130_fd_sc_hd with SRAM macros black-boxed, and attest the netlist
- **#46**: T1 item 5 (corner verification): klt functional-verification of the bit-exact suite plus multi-corner klt sta at 50 MHz
- **#51**: Generate and pin the 4 KB (1024x32) OpenRAM macro views: LEF, GDS, Verilog, Liberty

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

- **#55**: feat(synth): commit sky130 gate-level netlist with SRAM black boxes and attest T1 item 1

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

- **#54**: test(verification): add klt functional-verification request and ARRAY_N=8 envelope

## Proposed

Issues carrying `loom:curated`.

- **#4**: Track the gap to T1 (klayout-tools design-evidence-tiers.md) *(curated)*
- **#8**: Track the RTL, integer golden model and testbenches the ports pin *(curated)*

## Proposed (Architect / Hermit)

- **#18**: Remove vacuous package.json stub scripts (check:ci/check:all/test/lint always exit 0) *(hermit)*

## Epics

_None._

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Very important | 0 |
| Important | 0 |
| Ready (`loom:issue`) | 0 |
| In Progress (`loom:building`) | 3 |
| PRs awaiting review | 1 |
| Approved PRs awaiting merge | 1 |
| Curated | 2 |
| Architect / Hermit proposals | 1 |
| Active epics | 0 |
<!-- guide:plan-body:end -->
