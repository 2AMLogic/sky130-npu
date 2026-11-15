# Work Plan

Roadmap generated from GitHub label state by the Guide triage agent. Only the
region between the markers is machine-generated.

<!-- guide:plan-body:start -->
## Operator Attention: Merge-Risk-Hold Pileup

Judge-approved PRs under a hold (`loom:blocked` or `loom:operator`) — only a human merge decision is missing.

_None._

## Very Important

`loom:very-important` (one counts per workspace); every stage takes these first.

- **#43**: T1 item 2 (layout): routed npu_top GDS from a committed klt place-and-route flow with the four OpenRAM macros placed

## Important

`loom:important`; taken before unlabelled work.

- **#46**: T1 item 5 (corner verification): klt functional-verification of the bit-exact suite plus multi-corner klt sta at 50 MHz

## Ready

Human-approved issues ready for implementation (`loom:issue`).

- **#162**: Pin NPU_SEED in functional-verification-request.json so the random test is reproducible from committed evidence

## In Progress

Issues currently being built (`loom:building`).

- **#146**: Deduplicate the RTL source list and the mutation-control verdict: four hand-synced copies across rtl/ and verification/
- **#149**: Remove the dead LATENCY localparam in npu_requant.v: the requantizer pipeline depth is spelled three ways, one of them unreachable
- **#160**: Deduplicate tile setup in test_bitexact.py: test_reset_mid_run hand-rolls load_tile, and pack_a/pack_b is imported locally four times
- **#163**: package.json check:all / check:ci are named for the full gate but run 2 of CI's 8 steps, skipping both negative controls
- **#164**: flow/sram/setup.sh: --config record path is hardcoded and --macro-config validates late

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

- **#150**: docs: roadmap as of 2026-11-13
- **#156**: refactor: source the RTL file set and the mutation verdict from two libraries
- **#169**: fix: record repo-relative config path and validate --macro-config before destructive rm in sram setup
- **#170**: test(verification): deduplicate tile setup — retrofit test_reset_mid_run onto load_tile, hoist pack_a/pack_b imports

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

- **#167**: build: make pnpm check:ci run the full CI gate via verification/check-all.sh

## Proposed

Issues carrying `loom:curated`.

- **#4**: Track the gap to T1 (klayout-tools design-evidence-tiers.md) *(curated)*
- **#43**: T1 item 2 (layout): routed npu_top GDS from a committed klt place-and-route flow with the four OpenRAM macros placed *(curated)*
- **#46**: T1 item 5 (corner verification): klt functional-verification of the bit-exact suite plus multi-corner klt sta at 50 MHz *(curated)*
- **#157**: Two more zero-reference localparams: AW in npu_ctrl.v and OW in npu_host.v *(curated)*
- **#162**: Pin NPU_SEED in functional-verification-request.json so the random test is reproducible from committed evidence *(curated)*
- **#164**: flow/sram/setup.sh: --config record path is hardcoded and --macro-config validates late *(curated)*

## Proposed (Architect / Hermit)

_None._

## Epics

_None._

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Very important | 1 |
| Important | 1 |
| Ready (`loom:issue`) | 1 |
| In Progress (`loom:building`) | 5 |
| PRs awaiting review | 4 |
| Approved PRs awaiting merge | 1 |
| Curated | 6 |
| Architect / Hermit proposals | 0 |
| Active epics | 0 |
<!-- guide:plan-body:end -->
