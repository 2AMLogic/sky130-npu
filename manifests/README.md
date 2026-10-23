# manifests

This block's **graded** gap-to-T1 state, from `klt signoff`
([klayout-tools](https://github.com/2AMLogic/klayout-tools)).

- **`sky130-npu.json`**: the block manifest. `block: sky130-npu`,
  `kind: digital`. Item 6 is discharged by a recorded `not_applicable`
  statement (below). Item 10 cites `attestations/item-10.json`; every other
  item is still uncited and grades `unmet`, so `tier` is `null`. Items 1 and 9
  are attested the same way once there is something to inventory.
- **`spec-rows.json`**: the ratified target spec for item 6, one `id` per row
  of `spec/npu.md` section 1 (a slug of the Parameter column, since the table
  has no id column).
- **`item6-na-statement.json`**: exactly one `{id, class, reason}` per spec
  row, saying why that row is not statistical. The ratified spec has no
  accuracy, offset or matching row, so item 6 is `not_applicable`, never
  omitted.
- **`inventories/`** and **`attestations/`**: the item-10 inventory (README,
  LICENSE, both workflows, plus the golden-model tests) and the envelope
  `klt signoff --attest 10` produced from it. Regenerate after any edit to an
  inventoried file, with the pinned klt as below:
  `klt signoff --attest 10 --inventory manifests/inventories/item-10.json -o manifests/attestations/item-10.json`,
  then update the cited `content_hash` in the manifest and re-render the
  report. CI runs the same command with `--check`.
- **`sky130-npu.signoff.json`**: the committed output of
  `klt signoff --manifest manifests/sky130-npu.json --format json`, verbatim.
  This is the verdict of record for the block's gap to T1.

## Keeping item 6 in step with the spec

`spec-rows.json` **must change whenever `spec/npu.md` section 1 gains or loses
a row**, and `item6-na-statement.json` must then gain or lose the matching
entry. Then update the two `content_hash` values in `sky130-npu.json`
(`sha256sum` of each file) and regenerate the report. Editing either document
without updating its hash grades item 6 `unmet` / `stale_evidence`; a statement
that does not match the spec rows is rejected by the grader.

## Regenerate

Use the klt commit pinned in `KLT_SHA` in `.github/workflows/signoff.yml`
(the only place the pin is recorded), in a throwaway environment rather than a
host-wide install:

```
uvx --from "klayout-tools @ git+https://github.com/2AMLogic/klayout-tools@<KLT_SHA>" \
  klt signoff --manifest manifests/sky130-npu.json --format json \
  > manifests/sky130-npu.signoff.json
```

Exit 3 is expected while any item is unmet and exit 0 means T1. Exit 1 or 2
is a failure.

`.github/workflows/signoff.yml` runs the same command on every push to `main`
and every pull request, and fails if the result differs from the committed
report.

## Bumping the klt pin

A change to `KLT_SHA` lands together with a regenerated
`sky130-npu.signoff.json` in the same PR, because the pinned klt's bundled
checklist text is part of the report.
