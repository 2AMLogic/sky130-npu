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

_None._

## In Progress

Issues currently being built (`loom:building`).

- **#146**: Deduplicate the RTL source list and the mutation-control verdict: four hand-synced copies across rtl/ and verification/
- **#149**: Remove the dead LATENCY localparam in npu_requant.v: the requantizer pipeline depth is spelled three ways, one of them unreachable

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

_None._

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

- **#156**: refactor: source the RTL file set and the mutation verdict from two libraries
- **#158**: refactor(rtl): delete the dead LATENCY localparam and measure REQ_LAT against the real requantizer pipeline

## Proposed

Issues carrying `loom:curated`.

- **#4**: Track the gap to T1 (klayout-tools design-evidence-tiers.md) *(curated)*
- **#43**: T1 item 2 (layout): routed npu_top GDS from a committed klt place-and-route flow with the four OpenRAM macros placed *(curated)*
- **#46**: T1 item 5 (corner verification): klt functional-verification of the bit-exact suite plus multi-corner klt sta at 50 MHz *(curated)*
- **#157**: Two more zero-reference localparams: AW in npu_ctrl.v and OW in npu_host.v *(curated)*
- **#173**: verification/README.md fv example command fails on a clean host and clobbers concurrent runs (-o /tmp/fv151) *(curated)*

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
| Ready (`loom:issue`) | 0 |
| In Progress (`loom:building`) | 2 |
| PRs awaiting review | 0 |
| Approved PRs awaiting merge | 2 |
| Curated | 5 |
| Architect / Hermit proposals | 0 |
| Active epics | 0 |
<!-- guide:plan-body:end -->
