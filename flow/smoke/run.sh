#!/usr/bin/env bash
#
# flow/smoke/run.sh -- toolchain smoke: the whole klt digital flow on a
# throwaway counter, single local typical corner (tt_025C_1v80).
#
#   ./flow/smoke/run.sh                 # run, scratch under flow/build/smoke/
#   ./flow/smoke/run.sh --record ID     # same, then copy requests + envelopes
#                                       # to flow/smoke/records/ID/ (append-only)
#
# Steps, in order: klt synthesize, klt place-and-route (sky130hd PDN preset),
# klt drc, klt extract + klt lvs (gate-level-verilog reference = the as-built
# netlist), klt erc, klt sta (routed DEF). Every step runs to the end even
# when an earlier gate fails, so the record shows all of it; the exit status
# is non-zero if any gate did not pass.
#
# Cold start: needs only the pinned klt (run through uvx, never a host
# install), yosys, openroad, iverilog, jq and sky130A at the open_pdks commit
# in flow/pdk.json (PDK_ROOT). The pin checks and the record preamble are
# shared with the other flow runners in flow/runner-lib.sh.
#
# This is toolchain evidence, not block evidence: nothing from it is cited in
# a block manifest. Single-unit runs only -- no corner grid, no Monte Carlo.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/../.." && pwd)"
. "${REPO_ROOT}/flow/runner-lib.sh"

OUT="${REPO_ROOT}/flow/build/smoke"
TOP=counter
CELL_LIB=sky130_fd_sc_hd
CORNER=tt_025C_1v80
CLOCK_PERIOD_NS=20.0

runner_parse_record "${HERE}/records" "$@"
runner_require_tools yosys openroad
runner_check_pins

# klt lvs has no --pdk flag; $PDK is the only way to pick the variant when the
# search roots hold several families (gf180mcuA wins otherwise).
export PDK="${PDK_VARIANT}"

rm -rf "${OUT}"
mkdir -p "${OUT}"
cp "${HERE}/counter.v" "${HERE}/synth-request.json" "${HERE}/erc-spec.json" "${OUT}/"
cd "${OUT}"

echo "== klt synthesize =="
klt synthesize synth-request.json --pdk "${PDK_VARIANT}" --format json > synth.json 2> synth.err
RUN_ID="$(jq -r '.run_id' synth.json 2>/dev/null)"
NETLIST=".klt/synthesize/${RUN_ID}/${TOP}_synth.v"
[ "$(jq -r '.status' synth.json 2>/dev/null)" = "ok" ] && [ -f "${NETLIST}" ] || fail "synthesize"

cat > par-request.json <<JSON
{
  "schema": "klt.place_and_route.request/1",
  "engine": "openroad",
  "netlist": "${NETLIST}",
  "hdl_toplevel": "${TOP}",
  "pdk": { "cell_library": "${CELL_LIB}", "corner": "${CORNER}" },
  "floorplan": { "method": "utilization", "utilization_pct": 20, "aspect_ratio": 1.0, "core_margin_um": 2.0, "site": "unithd" },
  "io": { "layer_h": "met3", "layer_v": "met2" },
  "power": { "preset": "sky130hd" },
  "constraints": { "clock_port": "clk", "clock_period_ns": ${CLOCK_PERIOD_NS} },
  "seed": 1,
  "target_stage": "route"
}
JSON
echo "== klt place-and-route =="
klt place-and-route par-request.json --pdk "${PDK_VARIANT}" --format json > par.json 2> par.err
GDS="$(jq -r '.gds_path // empty' par.json 2>/dev/null)"
DEF="$(jq -r '.def_path // empty' par.json 2>/dev/null)"
VLOG="$(jq -r '.verilog_path // empty' par.json 2>/dev/null)"
# Requests reference outputs relative to this directory (resolved against the request file).
rel() { printf '%s' "${1#"${OUT}"/}"; }
[ "$(jq -r '.stage_reached' par.json 2>/dev/null)" = "route" ] && [ -f "${GDS}" ] && [ -f "${DEF}" ] && [ -f "${VLOG}" ] || fail "place-and-route"

if [ -f "${GDS}" ]; then
  echo "== klt drc =="
  klt drc "${GDS}" --deck sky130 --pdk "${PDK_VARIANT}" --format json > drc.json 2> drc.err
  [ "$(jq -r '.status' drc.json 2>/dev/null)" = "clean" ] || fail "drc status=$(jq -r '.status' drc.json 2>/dev/null)"

  echo "== klt extract + klt lvs (gate-level-verilog reference) =="
  klt extract "${GDS}" --deck sky130 --abstract-cells "${CELL_LIB}__*" --def-net-names \
    -o layout.gate.spice --format json > extract.json 2> extract.err
  ETOP="$(jq -r '.top' extract.json 2>/dev/null)"
  cat > lvs-request.json <<JSON
{
  "schema": "klt.lvs.request/1",
  "engine": "klayout",
  "layout": { "netlist": "layout.gate.spice", "top": "${ETOP}" },
  "reference": { "netlist": "$(rel "${VLOG}")", "top": "${TOP}", "form": "gate-level-verilog", "library": "${CELL_LIB}" }
}
JSON
  klt lvs lvs-request.json --format json > lvs.json 2> lvs.err
  [ "$(jq -r '.status' lvs.json 2>/dev/null)" = "match" ] || fail "lvs status=$(jq -r '.status' lvs.json 2>/dev/null)"

  echo "== klt erc =="
  klt erc "${GDS}" erc-spec.json --pdk sky130 --deck sky130 --top "${TOP}" --format json > erc.json 2> erc.err
  ERC_RC=$?
  [ "${ERC_RC}" = 0 ] || fail "erc exit=${ERC_RC} status=$(jq -r '.status // .erc_status' erc.json 2>/dev/null)"
fi

if [ -f "${DEF}" ]; then
  cat > sta-request.json <<JSON
{
  "schema": "klt.sta.request/1",
  "def": "$(rel "${DEF}")",
  "hdl_toplevel": "${TOP}",
  "pdk": { "cell_library": "${CELL_LIB}", "corner": "${CORNER}" },
  "constraints": { "clock_port": "clk", "clock_period_ns": ${CLOCK_PERIOD_NS}, "propagated_clock": true },
  "geometry_source": "routed"
}
JSON
  echo "== klt sta =="
  klt sta sta-request.json --pdk "${PDK_VARIANT}" --format json > sta.json 2> sta.err
  jq -e '.provenance.deck.name' sta.json >/dev/null 2>&1 || fail "sta"
fi

LIB="${PDK_ROOT_RESOLVED}/${PDK_VARIANT}/libs.ref/${CELL_LIB}/lib/${CELL_LIB}__${CORNER}.lib"
LIB_SHA="$(sha256sum "${LIB}" | cut -d' ' -f1)"
[ "sha256:${LIB_SHA}" = "$(jq -r '.provenance.deck.content_hash' sta.json 2>/dev/null)" ] || fail "sta liberty hash does not match ${CELL_LIB}__${CORNER}.lib"
{
  echo "liberty ${CELL_LIB}__${CORNER}.lib sha256:${LIB_SHA}"
  echo "yosys $(yosys -V)"
  echo "openroad $(openroad -version)"
  echo "icarus $(iverilog -V 2>/dev/null | head -1)"
  echo "klt ${KLT_VERSION}"
} > tool-versions.txt

echo "== summary =="
jq -r '"synth:  \(.status) \(.instance_count) cells \(.area_um2) um2"' synth.json 2>/dev/null
jq -r '"pnr:    \(.stage_reached) antenna=\(.antenna_violation_count) route_drc=\(.route_drc_violation_count)"' par.json 2>/dev/null
jq -r '"drc:    \(.status) violations=\(.violation_count) rules_checked=\(.coverage.rules_checked|length) rules_skipped=\(.coverage.rules_skipped|length) unmodeled=\(.coverage.unmodeled_rules|length)"' drc.json 2>/dev/null
jq -r '"lvs:    \(.status) errors=\(.error_count) power_connectivity=\(.power_connectivity.status // "absent")"' lvs.json 2>/dev/null
jq -r '"erc:    \(.status // .erc_status)"' erc.json 2>/dev/null
jq -r '"sta:    \(.provenance.deck.name) geometry=\(.geometry_source)"' sta.json 2>/dev/null

if [ -n "${RECORD_ID}" ]; then
  DEST="${HERE}/records/${RECORD_ID}"
  mkdir -p "${DEST}"
  # Envelopes are copied verbatim except for scrub()'s host-path replacement,
  # so the record carries no host path (`klt env-provenance lint-envelope` is
  # run over the result below).
  for f in synth.json par.json drc.json lvs.json erc.json sta.json extract.json \
           par-request.json lvs-request.json sta-request.json tool-versions.txt; do
    scrub "$f" > "${DEST}/$f"
  done
  klt env-provenance lint-envelope "${DEST}"/*.json || FAIL=1
  echo "recorded -> flow/smoke/records/${RECORD_ID}/"
fi
exit "${FAIL}"
