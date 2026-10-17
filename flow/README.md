# flow/ — pinned PDK, pinned toolchain, and the klt smoke run

This directory pins what the digital flow runs on and holds one committed run
that shows the whole `klt` flow works on sky130 `sky130_fd_sc_hd`, before any
NPU RTL exists.

**It is toolchain evidence, not block evidence.** The fixture is a throwaway
8-bit counter. It chooses no array size, dataflow, arithmetic or SRAM source,
and nothing from it may be cited in a block manifest.

| File | What it pins |
|---|---|
| `pdk.json` | `open_pdks` commit (full SHA), variant `sky130A`, library `sky130_fd_sc_hd`, smoke corner |
| `toolchain.json` | klayout-tools commit (full SHA, recorded once), Yosys, OpenROAD, Icarus versions |
| `smoke/` | fixture RTL, request JSONs, ERC stackup spec, `run.sh` |
| `smoke/records/<id>/` | envelopes from one run. Append-only: `run.sh` refuses an existing id |

`toolchain.json` is the single place the klt pin lives. Anything else that
needs a klt pin (for example the signoff workflow in #5) should read it from
here rather than carry a second copy.

## Cold start

From a clean clone, with the pinned PDK and tools installed:

```bash
# 1. klt at the pinned commit (a throwaway tool env, not a host-wide install)
uvx --from "git+https://github.com/2AMLogic/klayout-tools.git@$(jq -r .klayout_tools.commit flow/toolchain.json)" klt --version
#    -> must report 0.7.1.dev1754+g81ac4d3915c1
# 2. the PDK: open_pdks commit from flow/pdk.json (klt resolves ~/.ciel, then ~/.volare)
klt pdk find --pdk sky130A --format json | jq -r .version
#    -> must report open_pdks f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7
# 3. yosys, openroad, iverilog on PATH, at the versions in flow/toolchain.json
# 4. run it
./flow/smoke/run.sh                      # scratch under flow/build/smoke/ (gitignored)
./flow/smoke/run.sh --record <id>        # also copy requests + envelopes to flow/smoke/records/<id>/
```

`run.sh` checks the `klt` build and the resolved PDK against the two JSON
files and exits `2` before running anything if either differs. After the
steps it exits non-zero if any gate failed; every step still runs so the
record shows all of them. If `PDK_ROOT` is unset and several PDK roots are
installed, set it to the root that holds the pinned commit. The script exports
`PDK=sky130A` because `klt lvs` has no `--pdk` flag (klayout-tools#3852).

It runs single-unit, one local corner (`tt_025C_1v80`). It is not a corner
grid and does not use the batch fleet. The clock period (20 ns) is arbitrary:
it only gives `klt sta` something to time against. It is not a target.

## What each step proves

| Step | Command | Proves | Does not prove |
|---|---|---|---|
| 1 | `klt synthesize` | Yosys + ABC map RTL onto `sky130_fd_sc_hd` | Functional correctness (no testbench here; `verification/` owns that) |
| 2 | `klt place-and-route` (`power.preset: sky130hd`) | OpenROAD reaches `route` with a PDN, tapcells and fillers; reports GDS, DEF and the as-built netlist | Timing closure at any clock |
| 3 | `klt drc --deck sky130` | The routed GDS passes the curated sky130 deck, within the `coverage` below | Foundry-signoff DRC |
| 4 | `klt extract` + `klt lvs` (`gate-level-verilog`) | The routed layout's connectivity equals the as-built netlist, and supplies match | Device-level (transistor) LVS: standard cells are black boxes |
| 5 | `klt erc` | Antenna ratios and ERC findings over the declared stackup | Supply-net continuity or well ties: no `nets[]`/`ties[]` are declared, hence `clean_partial` |
| 6 | `klt sta` on the routed DEF | OpenSTA runs on routed geometry (`geometry_source: "routed"`) with propagated clock | Any timing claim about the NPU |

## The committed run: `smoke/records/20261017-tt-baseline/`

Tools as reported by the envelopes (also in `tool-versions.txt`): klt
`0.7.1.dev1754+g81ac4d3915c1`, Yosys `0.67+post`, OpenROAD `26Q3-1510-g6cb3f2b704`,
open_pdks `f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7`.

| Step | Result |
|---|---|
| synthesize | `ok`, 28 cells, 284.02 µm² |
| place-and-route | `stage_reached: route`, antenna violations 0, route DRC violations 0, PDN `complete` |
| drc | `status: clean`, `violation_count: 0` |
| lvs | `status: match`, `error_count: 0`, `power_connectivity.status: match` |
| erc | `status: clean_partial`: `erc_status: clean`, 0 findings; antenna 273 levels `pass`, 364 `unchecked` |
| sta | `status: ok`, `timing_status: constrained`, deck `sky130_fd_sc_hd__tt_025C_1v80` |

### DRC `coverage` (quoted from `drc.json`)

`known: true`, `unchecked_rules: []`, `nothing_checked: false`.

- `rules_checked`: 102 rules over 20 layers (`layers_checked`).
- `rules_skipped`: 48. Every one is listed under `inapplicable` with reason
  `no_applicable_geometry` (the counter draws no `dnwell`, `hvi`, `capm`,
  `rpm`, `pad` or similar).
- `unmodeled_rules`: 17 (`difftap.8`–`.11`, `m1.5`, `m2.5`, `n/psdm.5a`–`.10b` (all eight),
  `npc.4`, `via.5a`, `via2.5`, `via3.5`). The curated deck does not model
  these, so a `clean` verdict says nothing about them.

"Clean" here means clean for the 102 checked rules, not for the foundry
deck as a whole.

### Liberty file used by `klt sta`

The `klt sta` envelope names the deck (`sky130_fd_sc_hd__tt_025C_1v80`) and its
content hash, not a file path (klayout-tools#3785). The file is
`libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib` under the
pinned PDK, `sha256:8e78e14442062dba34d414fca6490b2f6b96038d4510d1438ca44fee31487135`.
`run.sh` hashes that file and fails if it differs from the envelope's
`provenance.deck.content_hash`, so the name above is checked rather than assumed.

## Records contain no host paths

`klt place-and-route` and `klt lvs` write some output paths absolute
(klayout-tools#3798, #3820). When recording, `run.sh` replaces this checkout's
root with `<repo>` and the PDK root with `<pdk-root>` with `sed`, then runs
`klt env-provenance lint-envelope` over the result. Nothing else in an
envelope is edited.

## Tool gaps filed

- klayout-tools#3852: `klt lvs` has no `--pdk`/`--pdk-root`; it resolved
  the wrong PDK family on this host (found in this run).
- klayout-tools#3785: `klt sta` does not name the Liberty file it read.
- klayout-tools#3798, #3820: absolute host paths in `place-and-route` / `lvs` envelopes.
- klayout-tools#3814: PDK resolution is ambiguous when several variants are installed.
