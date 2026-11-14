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
- **#151**: Re-run the klt functional-verification envelope on the 14-test bit-exact suite
- **#153**: Attempt slow- and fast-corner Liberty views for the pinned 4 KB OpenRAM macro (spec gaps G1, G2)

## Ready

Human-approved issues ready for implementation (`loom:issue`).

_None._

## In Progress

Issues currently being built (`loom:building`).

- **#144**: Remove the second item-10 citation: signoff.yml hard-codes an attestation path the manifest already names
- **#145**: Remove the stamp-list file enumeration in verification/README.md: a copy of the directory listing that has drifted twice
- **#146**: Deduplicate the RTL source list and the mutation-control verdict: four hand-synced copies across rtl/ and verification/

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

- **#147**: docs: state the verification stamp set as a rule, not a file list
- **#148**: ci: read the item-10 attestation path from the manifest, not a literal
- **#150**: docs: roadmap as of 2026-11-13

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

_None._

## Proposed

Issues carrying `loom:curated`.

- **#4**: Track the gap to T1 (klayout-tools design-evidence-tiers.md) *(curated)*
- **#43**: T1 item 2 (layout): routed npu_top GDS from a committed klt place-and-route flow with the four OpenRAM macros placed *(curated)*
- **#46**: T1 item 5 (corner verification): klt functional-verification of the bit-exact suite plus multi-corner klt sta at 50 MHz *(curated)*

## Proposed (Architect / Hermit)

- **#149**: Remove the dead LATENCY localparam in npu_requant.v: the requantizer pipeline depth is spelled three ways, one of them unreachable *(hermit)*

## Epics

_None._

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Very important | 1 |
| Important | 3 |
| Ready (`loom:issue`) | 0 |
| In Progress (`loom:building`) | 3 |
| PRs awaiting review | 3 |
| Approved PRs awaiting merge | 0 |
| Curated | 3 |
| Architect / Hermit proposals | 1 |
| Active epics | 0 |
<!-- guide:plan-body:end -->
