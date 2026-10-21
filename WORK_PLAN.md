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

- **#11**: Parameterised NPU RTL with array size as one parameter
- **#12**: Bit-exact cocotb testbenches against the golden model
- **#25**: Pin the SRAM macro and write the npu_sram_bank wrapper (reuse.lock.json owner)

## Ready

Human-approved issues ready for implementation (`loom:issue`).

_None._

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
- **#11**: Parameterised NPU RTL with array size as one parameter *(curated)*

## Proposed (Architect / Hermit)

- **#18**: Remove vacuous package.json stub scripts (check:ci/check:all/test/lint always exit 0) *(hermit)*

## Epics

_None._

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Very important | 0 |
| Important | 3 |
| Ready (`loom:issue`) | 0 |
| In Progress (`loom:building`) | 0 |
| PRs awaiting review | 0 |
| Approved PRs awaiting merge | 0 |
| Curated | 2 |
| Architect / Hermit proposals | 1 |
| Active epics | 0 |
<!-- guide:plan-body:end -->
