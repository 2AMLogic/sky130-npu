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

- **#43**: T1 item 2 (layout): routed npu_top GDS from a committed klt place-and-route flow with the four OpenRAM macros placed

## In Progress

Issues currently being built (`loom:building`).

- **#68**: Remove orphaned test_bank_alias_bias.py: never run, duplicates test_bitexact and Bench

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

- **#92**: layout: add npu_top place-and-route request and runner with unrouted first record

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

_None._

## Proposed

Issues carrying `loom:curated`.

- **#4**: Track the gap to T1 (klayout-tools design-evidence-tiers.md) *(curated)*
- **#43**: T1 item 2 (layout): routed npu_top GDS from a committed klt place-and-route flow with the four OpenRAM macros placed *(curated)*
- **#46**: T1 item 5 (corner verification): klt functional-verification of the bit-exact suite plus multi-corner klt sta at 50 MHz *(curated)*
- **#68**: Remove orphaned test_bank_alias_bias.py: never run, duplicates test_bitexact and Bench *(curated)*

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
| In Progress (`loom:building`) | 1 |
| PRs awaiting review | 1 |
| Approved PRs awaiting merge | 0 |
| Curated | 4 |
| Architect / Hermit proposals | 0 |
| Active epics | 0 |
<!-- guide:plan-body:end -->
