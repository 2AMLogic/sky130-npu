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

- **#46**: T1 item 5 (corner verification): klt functional-verification of the bit-exact suite plus multi-corner klt sta at 50 MHz
- **#51**: Generate and pin the 4 KB (1024x32) OpenRAM macro views: LEF, GDS, Verilog, Liberty

## Ready

Human-approved issues ready for implementation (`loom:issue`).

- **#51**: Generate and pin the 4 KB (1024x32) OpenRAM macro views: LEF, GDS, Verilog, Liberty

## In Progress

Issues currently being built (`loom:building`).

_None._

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

_None._

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

_None._

## Proposed

Issues carrying `loom:curated`.

- **#4**: Track the gap to T1 (klayout-tools design-evidence-tiers.md) *(curated)*
- **#8**: Track the RTL, integer golden model and testbenches the ports pin *(curated)*
- **#46**: T1 item 5 (corner verification): klt functional-verification of the bit-exact suite plus multi-corner klt sta at 50 MHz *(curated)*
- **#51**: Generate and pin the 4 KB (1024x32) OpenRAM macro views: LEF, GDS, Verilog, Liberty *(curated)*

## Proposed (Architect / Hermit)

- **#18**: Remove vacuous package.json stub scripts (check:ci/check:all/test/lint always exit 0) *(hermit)*

## Epics

_None._

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Very important | 0 |
| Important | 2 |
| Ready (`loom:issue`) | 1 |
| In Progress (`loom:building`) | 0 |
| PRs awaiting review | 0 |
| Approved PRs awaiting merge | 0 |
| Curated | 4 |
| Architect / Hermit proposals | 1 |
| Active epics | 0 |
<!-- guide:plan-body:end -->
