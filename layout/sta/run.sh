#!/usr/bin/env bash
#
# layout/sta/run.sh -- standalone pre-route STA read of npu_top from the
# committed gate-level netlist, single local typical corner, at the clock
# period the request pins (20 ns: the 50 MHz target's cycle). Answers one
# question before a routed layout exists (#154): does the SRAM macro read
# access time fit the cycle at all, and what actually binds at 20 ns.
#
#   ./layout/sta/run.sh                 # run, scratch under layout/sta/build/
#   ./layout/sta/run.sh --record ID     # same, then copy report + probe + logs
#                                       # to layout/sta/records/ID/ (append-only)
#
# Two sources, kept apart in the record:
#   1. `klt sta` in verilog (netlist) mode -- the committed response, whose
#      `worst_setup_path` is always the GLOBAL worst path (the generated Tcl
#      asks for one path per check type; `constraints.report_ports` cannot
#      select an internal pin). Labelled `netlist_estimate` by the tool.
#   2. `macro-paths.tcl`, a direct OpenROAD `report_checks` probe over the
#      same decks -- the only way to get the worst path through a macro pin
#      (klayout-tools has no through/from/to selector for sta; the gap is
#      filed upstream, see the record's NOTES.md). Its output is labelled as
#      coming from the probe, never presented as `klt sta` output.
#
# Cold start: needs only the pinned klt (run through uvx, never a host
# install), openroad, jq and sky130A at the open_pdks commit in flow/pdk.json
# (PDK_ROOT). The pin checks and the record preamble are shared with the
# other flow runners in flow/runner-lib.sh. Inputs are staged into scratch as
# inputs/ so the committed sta-request.json runs byte-for-byte unchanged:
#   inputs/npu_top_synth.v  <- the current synthesis record, resolved by
#                              rtl/synth/current-netlist.sh (never a record id here)
#   inputs/macro.lef        <- rtl/pdk/sky130/macro/.../*.lef (abstract view)
#   inputs/macro_tt.lib     <- the same directory's TT Liberty, the view
#                              reuse.lock.json pins (OpenRAM analytical model)
# Single unit: one STA run, local, ideal clock, no wire-load model, tt only.
# Not a corner grid, not post-route STA (#46), and no Fmax claim.
# Result is informational, not closure: CLAUDE.md "Throughput honesty".

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/../.." && pwd)"
. "${REPO_ROOT}/flow/runner-lib.sh"

OUT="${HERE}/build"
MACRO_DIR="${REPO_ROOT}/rtl/pdk/sky130/macro/sky130_sram_4kbyte_1rw1r_32x1024_8"
MACRO=sky130_sram_4kbyte_1rw1r_32x1024_8
MACRO_LIB_TT="${MACRO}_TT_1p8V_25C.lib"   # the view reuse.lock.json pins (TT only; ss/ff is #153)

runner_parse_record "${HERE}/records" "$@"
runner_require_tools openroad sha256sum

# Which netlist: rtl/synth/current-netlist.sh resolves the current synthesis
# record from rtl/synth/synth-request.json, so a new record moves this runner
# at once instead of leaving a stale record id behind here.
NETLIST_SRC="$("${REPO_ROOT}/rtl/synth/current-netlist.sh")" || exit 2
NETLIST_REL="$("${REPO_ROOT}/rtl/synth/current-netlist.sh" --relative)" || exit 2

runner_check_pins

# Clock and corner come from the committed request, so the probe (and the
# std-cell deck lookup below) stay in sync with it -- one source, not two.
CLOCK_PORT="$(jq -r '.constraints.clock_port' "${HERE}/sta-request.json")"
CLOCK_PERIOD_NS="$(jq -r '.constraints.clock_period_ns' "${HERE}/sta-request.json")"
CORNER="$(jq -r '.pdk.corner' "${HERE}/sta-request.json")"
CELL_LIB="$(jq -r '.pdk.cell_library' "${HERE}/sta-request.json")"

# The decks the probe needs, resolved the same way the generated klt sta Tcl
# resolves them (checked, not assumed: a missing deck must stop the run here,
# not fail deep inside openroad).
STD_TLEF="${PDK_ROOT_RESOLVED}/${PDK_VARIANT}/libs.ref/${CELL_LIB}/techlef/${CELL_LIB}__nom.tlef"
STD_LEF="${PDK_ROOT_RESOLVED}/${PDK_VARIANT}/libs.ref/${CELL_LIB}/lef/${CELL_LIB}.lef"
STD_LIB="${PDK_ROOT_RESOLVED}/${PDK_VARIANT}/libs.ref/${CELL_LIB}/lib/${CELL_LIB}__${CORNER}.lib"
for F in "${STD_TLEF}" "${STD_LEF}" "${STD_LIB}"; do
  [ -f "${F}" ] || { echo "error: ${F} not found under the pinned PDK" >&2; exit 2; }
done

# Inputs staged beside the request (a macros[] path that resolves outside the
# request's directory can fail under the sandboxed openroad), and the probe
# template instantiated with the deck paths -- openroad runs in a container
# whose wrapper mounts $PWD and $PDK_ROOT, so no environment crosses the
# boundary and the paths have to be written into the generated script.
rm -rf "${OUT}"
mkdir -p "${OUT}/inputs"
cp "${NETLIST_SRC}" "${OUT}/inputs/npu_top_synth.v"
cp "${MACRO_DIR}/${MACRO}.lef" "${OUT}/inputs/macro.lef"
cp "${MACRO_DIR}/${MACRO_LIB_TT}" "${OUT}/inputs/macro_tt.lib"
cp "${HERE}/sta-request.json" "${OUT}/sta-request.json"
sed -e "s#@STA_STD_LIB@#${STD_LIB}#" \
    -e "s#@STA_STD_TLEF@#${STD_TLEF}#" \
    -e "s#@STA_STD_LEF@#${STD_LEF}#" \
    -e "s#@STA_CLK_PERIOD@#${CLOCK_PERIOD_NS}#" \
    -e "s#@STA_CLK_PORT@#${CLOCK_PORT}#" \
    "${HERE}/macro-paths.tcl" > "${OUT}/macro-paths-run.tcl"
cd "${OUT}"

echo "== klt sta (pre-route, netlist mode) =="
klt sta sta-request.json --pdk "${PDK_VARIANT}" --format json > sta.json 2> sta.err
jq -e '.status' sta.json >/dev/null 2>&1 || fail "sta (no parseable response: $(tail -1 sta.err 2>/dev/null))"
[ "$(jq -r '.geometry_source' sta.json 2>/dev/null)" = "netlist_estimate" ] || fail "sta geometry_source is not netlist_estimate"
[ "sha256:$(sha256sum "${NETLIST_SRC}" | cut -d' ' -f1)" = "$(jq -r '.provenance.input.content_hash' sta.json 2>/dev/null)" ] || fail "sta report's netlist hash differs from the netlist current-netlist.sh resolved"

# The macro must have been TIMED, not blackboxed: request.macros[] with a lef
# but no lib is legal and still exits 0, timing the instance as an untimed
# blackbox -- a vacuous result that looks plausible. STA-0198 is OpenSTA's
# "creating black box" warning; the committed generated-sta.tcl is the proof
# the macro Liberty was loaded (AC3b).
if grep -q 'STA-0198' .klt/sta/openroad-logs/*/stdout.log .klt/sta/openroad-logs/*/stderr.log 2>/dev/null; then
  fail "STA-0198 (black box) in the OpenROAD log: the macro was timed as an untimed blackbox; the timing is vacuous"
fi

echo "== macro-pin probe (report_checks) =="
openroad -no_init -exit macro-paths-run.tcl > macro-paths-report.txt 2> macro-paths.err \
  || fail "macro-paths probe exit=$?"
grep -q 'PROBE macro instances found: 4' macro-paths-report.txt || fail "probe: expected 4 macro instances"
for M in PROBE_SETUP_INTO_MACRO_END PROBE_SETUP_OUT_OF_MACRO_END PROBE_SETUP_VIOLATORS_END; do
  grep -q "===${M}===" macro-paths-report.txt || fail "probe: marker ${M} missing"
done
# Honesty gate: if a macro pin ever lands in the violator set, the headline
# below ("the binding path is not the macro") would be false -- fail loudly.
if sed -n '/PROBE_SETUP_VIOLATORS_BEGIN/,/PROBE_SETUP_VIOLATORS_END/p' macro-paths-report.txt \
     | grep -q "${MACRO}"; then
  fail "probe: a macro pin appears in the setup-violator listing"
fi

echo "== summary =="
jq -r '"sta:   \(.status) geometry=\(.geometry_source) clock=\(.clock_mode) wire_load=\(.wire_load_model) worst_slack_ns=\(.worst_slack_ns) setup_violations=\(.setup_violation_count) hold_violations=\(.hold_violation_count) fmax_mhz(estimate, no claim)=\(.fmax_mhz)"' sta.json 2>/dev/null
jq -r '"worst setup path (global, klt sta): \(.worst_setup_path.startpoint) -> \(.worst_setup_path.endpoint) \(.worst_setup_path.slack_ns) ns"' sta.json 2>/dev/null
INTO_SLACK="$(awk '/===PROBE_SETUP_INTO_MACRO_BEGIN===/{f=1} f && /slack \(/{print $1; exit}' macro-paths-report.txt)"
OUT_SLACK="$(awk '/===PROBE_SETUP_OUT_OF_MACRO_BEGIN===/{f=1} f && /slack \(/{print $1; exit}' macro-paths-report.txt)"
echo "worst setup into a macro pin (probe): ${INTO_SLACK:-n/a} ns"
echo "worst setup out of a macro pin (probe): ${OUT_SLACK:-n/a} ns"

LIB_SHA="$(sha256sum "${STD_LIB}" | cut -d' ' -f1)"
[ "sha256:${LIB_SHA}" = "$(jq -r '.provenance.deck.content_hash' sta.json 2>/dev/null)" ] || fail "sta liberty hash does not match ${CELL_LIB}__${CORNER}.lib"
{
  echo "openroad $(openroad -version)"
  echo "klt ${KLT_VERSION}"
  echo "open_pdks ${PDK_WANT}"
  # What was timed: netlist, macro Liberty + LEF (the views reuse.lock.json
  # pins) and the std-cell deck, each with its sha256 -- a result through a
  # macro is only as good as the view behind it (spec section 7).
  echo "netlist ${NETLIST_REL} sha256:$(sha256sum "${NETLIST_SRC}" | cut -d' ' -f1)"
  echo "macro-lib rtl/pdk/sky130/macro/${MACRO}/${MACRO_LIB_TT} sha256:$(sha256sum "${MACRO_DIR}/${MACRO_LIB_TT}" | cut -d' ' -f1)"
  echo "macro-lef rtl/pdk/sky130/macro/${MACRO}/${MACRO}.lef sha256:$(sha256sum "${MACRO_DIR}/${MACRO}.lef" | cut -d' ' -f1)"
  echo "std-cell-deck libs.ref/${CELL_LIB}/lib/${CELL_LIB}__${CORNER}.lib (PDK-root-relative) sha256:${LIB_SHA}"
} > tool-versions.txt

if [ -n "${RECORD_ID}" ]; then
  DEST="${HERE}/records/${RECORD_ID}"
  mkdir -p "${DEST}"
  # A failed run is recorded too (request, error, tool versions): a record
  # of "did not read, and why" is evidence, not clutter. scrub() keeps host
  # paths out; generated-sta.tcl (the Tcl klt generated for this run) is the
  # AC3b evidence that inputs/macro_tt.lib was read_liberty'd.
  scrub sta.json > "${DEST}/sta.json"
  scrub sta.err > "${DEST}/sta.err"
  scrub macro-paths-report.txt > "${DEST}/macro-paths-report.txt"
  scrub macro-paths.err > "${DEST}/macro-paths.err"
  scrub .klt/sta/sta_*.tcl > "${DEST}/generated-sta.tcl"
  cp "${HERE}/macro-paths.tcl" sta-request.json tool-versions.txt "${DEST}/" || fail "record copy"
  for L in .klt/sta/openroad-logs/*/stdout.log .klt/sta/openroad-logs/*/stderr.log; do
    [ -f "${L}" ] && scrub "${L}" | gzip -9n > "${DEST}/openroad-klt-sta-$(basename "${L}").gz"
  done
  klt env-provenance lint-envelope "${DEST}"/sta.json || FAIL=1
  echo "recorded -> layout/sta/records/${RECORD_ID}/"
fi
exit "${FAIL}"
