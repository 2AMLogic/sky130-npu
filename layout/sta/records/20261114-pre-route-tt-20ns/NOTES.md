# 20261114-pre-route-tt-20ns -- pre-route STA read through the SRAM macro at tt, 20 ns

**Headline**: at tt, pre-route, the 20 ns cycle does **not** close
(`worst_slack_ns` -0.98389, `fmax_mhz` 47.6556, 1984 setup violations, hold
clean) -- and **the binding path is control-to-array, not the macro**. This
does not by itself argue against the spec's 50 MHz row or for the 25 MHz
fallback: the macro read path has large positive slack, and what fails is
`u_ctrl` driving the PE array.

This answers the open question spec section 7 (G1) records -- "whether the
macro read access time fits a 20 ns cycle with the surrounding logic" -- for
tt, pre-route: **yes, with room to spare**. Everything here is informational;
#46 owns post-route multi-corner STA.

## What was run

`klt sta` 0.9.1, verilog (netlist) mode over the current synthesis record
(`rtl/synth/records/20261111-sky130-hd`, resolved by
`rtl/synth/current-netlist.sh`, sha256 `0eef5aff...` -- equal to the report's
`provenance.input.content_hash`), corner `tt_025C_1v80`, clock period 20 ns on
`clk`, no `propagated_clock` (no CTS exists in netlist mode). The response is
self-labelled `geometry_source: "netlist_estimate"`; `clock_mode: "ideal"`,
`clock_skew_ns: 0`, `wire_load_model: null`.

Plus one auxiliary probe, `macro-paths.tcl`: the same decks (same Liberty
pair, LEFs, netlist, clock) re-loaded in a direct OpenROAD session that asks
`report_checks` for the macro-pin paths explicitly. **Its output is not
`klt sta` output** -- `klt sta` cannot make this query (see "Tool gap" below).

## Two sources, kept apart

### (a) Global worst setup path -- from the `klt sta` response (`sta.json`)

- `worst_slack_ns` **-0.98389**, `total_negative_slack_ns` -1458.52,
  `setup_violation_count` 1984, `hold_violation_count` 0
  (`worst_hold_slack_ns` +0.30959), `timing_status: "constrained"`.
- Worst setup path: `u_ctrl/_1992_/Q` -> `u_array/g_row[0].g_col[0].u_pe/_1470_/D`
  -- a control-to-array path. **No macro pin appears anywhere in the
  violator set** (1984 endpoints, all PE-array / control flops; see the
  violator listing inside `macro-paths-report.txt`'s
  `PROBE_SETUP_VIOLATORS` block and in `openroad-klt-sta-stdout.log.gz`).
- `fmax_mhz` 47.6556: OpenSTA's analytic estimate from the setup aggregate at
  this artificial 20 ns constraint. **No Fmax claim is made from this run**
  (CLAUDE.md "Throughput honesty"); the field is quoted only because the
  response carries it.

### (b) Worst paths through a macro pin -- from the `report_checks` probe (`macro-paths-report.txt`)

Probe inventory: 4 macro instances (one master,
`sky130_sram_4kbyte_1rw1r_32x1024_8`, instantiated per bank), 244 macro input
pins, 256 macro output pins.

- Worst setup path **into** a macro pin: **+16.211 ns (MET)**, endpoint
  `u_banks/g_bank[0].u_bank/genblk1.g_macro.u_macro/addr0[9]`
  (macro library setup time 0.103 ns).
- Worst setup path **out of** a macro pin: **+8.768 ns (MET)**,
  `.../g_bank[0].../u_macro/dout0[7]` -> `_2099_/D`.
- **Macro read access time 0.335 ns**: the `clk0` -> `dout0[7]` arc delay in
  that path's table.
- **The read is a half-cycle path**: the macro's OpenRAM Liberty launches
  `dout0` from `clk0`'s **falling** edge (the path starts "clock clk (fall
  edge)" at 10.000 ns) and the capture is the next rising edge at 20.000 ns.
  The read data therefore has a **10 ns** budget, not 20 ns -- the wide
  `dout` buses are exactly the nets the P&R congestion work flags, and their
  routing delay eats a half-cycle, not a full cycle. Not obvious from the
  spec; the floorplan work (#43) should know it.
- Zero macro pins among the violators (checked by the runner: the violator
  listing contains no occurrence of the macro master name).

## The macro was timed, not blackboxed (AC3b)

- `generated-sta.tcl` (the Tcl klt generated for this run) reads the macro
  Liberty: `read_liberty <repo>/layout/sta/build/inputs/macro_tt.lib` on the
  line after the std-cell Liberty. The staged file is the view
  `reuse.lock.json` pins (`..._TT_1p8V_25C.lib`, sha256 `6331177b...`,
  OpenRAM analytical delay model -- not SPICE characterization).
- `STA-0198` ("creating black box") appears **zero** times in the retained
  OpenROAD log (`openroad-klt-sta-stdout.log.gz` / `-stderr.log.gz`); the
  runner fails the run if it ever appears. A `macros[]` entry with a `lef`
  but no `lib` is legal and would time the macro as an untimed blackbox while
  still exiting 0 -- this check is what separates a real result from a
  vacuous one.

## Labelling (AC3c)

Pre-route (netlist only, no DEF), **no wire-load model applied**
(`wire_load_model: null`), ideal clock (`clock_mode: "ideal"`, skew 0),
**tt only** (ss/ff macro Liberty does not exist; #153 owns that gap), and the
macro delays come from OpenRAM's **analytical** delay model. Informational,
not closure; not measured; no Fmax claim. Post-route multi-corner STA is #46.

## Tool gap

`klt sta` cannot produce (b): its only path selector, `constraints.report_ports`,
takes top-level design ports, and the generated Tcl extracts exactly one path
per check type -- so `worst_setup_path` is always the global worst. Filed
generically (no design detail from this repo) at
`2AMLogic/klayout-tools#5754`; this record links it per the friction protocol.

## Provenance (`tool-versions.txt`)

| What | Value |
|---|---|
| Netlist | `rtl/synth/records/20261111-sky130-hd/npu_top_synth.v`, sha256 `0eef5aff70680d5da761fdf0adf85eef81d7e7970ae14761209ad53e88a04fef` (current per `rtl/synth/synth-request.json`; equals the report's `provenance.input.content_hash`) |
| Macro Liberty | `..._TT_1p8V_25C.lib`, sha256 `6331177b66740e12cf677351ee8d767c0027f9ffc6ad73fb306907b7b4819364` (pinned in `reuse.lock.json`; generated in-repo by `flow/sram/gen_4kb_1rw1r_32x1024.py` from the OpenRAM 1.2.50 pin, commit `2f7b3866418ac1ce17ad959207a1489033d8c577`, config `configs/sky130_sram_4kbyte_1rw1r_32x1024_8.py` sha256 `ff0b70cc...`, `nominal_corner_only = True` -- see `reuse.lock.json`'s `views_note`) |
| Macro LEF | sha256 `ff569537793e7618b05bf02bac6705607ea173ba532d071308c50f1c84b39997` (pinned in `reuse.lock.json`) |
| Std-cell deck | `sky130_fd_sc_hd__tt_025C_1v80.lib`, sha256 `8e78e14442062dba34d414fca6490b2f6b96038d4510d1438ca44fee31487135` (equals the report's `provenance.deck.content_hash`) |
| Tools | klt 0.9.1 (`4d0d29be4fd991f499d59e783a908082d5e24c56`), OpenROAD `26Q3-1510-g6cb3f2b704`, open_pdks `f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7` |

## What this leaves open

- The -0.98 ns `u_ctrl` -> PE path at 20 ns is **not** fixed here (out of
  scope; file separately if it matters). Whether it survives post-route
  delay is #46's question.
- ss/ff corners need the missing macro Liberty views: gaps G1/G2, #153.
- The 50 MHz row stays where it is: this run supports "macro read fits the
  cycle at tt" and nothing more.
