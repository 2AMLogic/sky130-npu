#!/usr/bin/env bash
#
# layout/run.sh -- place and route npu_top (ARRAY_N = 8, four OpenRAM 4 KB
# macros) from the committed gate-level netlist, single local typical corner.
#
#   ./layout/run.sh                 # run, scratch under layout/build/
#   ./layout/run.sh --record ID     # same, then copy request + envelope + routed
#                                   # GDS/DEF/netlist to layout/records/ID/ (append-only)
#
# Cold start: needs only the pinned klt (run through uvx, never a host
# install), openroad, jq and sky130A at the open_pdks commit in flow/pdk.json
# (PDK_ROOT). Inputs are staged into scratch as inputs/ so the committed
# par-request.json runs byte-for-byte unchanged:
#   inputs/npu_top_synth.v  <- rtl/synth/records/20261027-sky130-hd/
#   inputs/macro.lef        <- rtl/pdk/sky130/macro/.../*.lef (abstract, used for placement/routing)
#   inputs/macro.gds        <- the same directory's .gds.gz, gunzipped (merged into the stream)
# Single unit: one P&R run, local. No corner grid.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/.." && pwd)"
OUT="${HERE}/build"
MACRO_DIR="${REPO_ROOT}/rtl/pdk/sky130/macro/sky130_sram_4kbyte_1rw1r_32x1024_8"
MACRO=sky130_sram_4kbyte_1rw1r_32x1024_8
NETLIST_SRC="${REPO_ROOT}/rtl/synth/records/20261027-sky130-hd/npu_top_synth.v"

RECORD_ID=""
if [ "${1:-}" = "--record" ]; then
  RECORD_ID="${2:?usage: run.sh --record ID}"
  [[ "${RECORD_ID}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || { echo "bad record id" >&2; exit 2; }
  [ ! -e "${HERE}/records/${RECORD_ID}" ] || { echo "record ${RECORD_ID} exists; records are append-only" >&2; exit 2; }
fi

for tool in uvx openroad jq gzip sha256sum; do
  command -v "${tool}" >/dev/null || { echo "error: ${tool} not on PATH" >&2; exit 2; }
done

# The pinned klt, via uvx (the host klt is not the pin and must not be changed).
# Layout has its own pin (layout/klt-pin.json, klt >= 0.9.0 for halo/density);
# flow/toolchain.json still pins synthesis and the smoke flow.
PIN_PYPI="$(jq -r '.pypi' "${HERE}/klt-pin.json")"
PIN_VERSION="$(jq -r '.reported_version' "${HERE}/klt-pin.json")"
klt() { uvx --from "${PIN_PYPI}" klt "$@"; }
KLT_VERSION="$(klt --version)"
[ "${KLT_VERSION}" = "klt ${PIN_VERSION}" ] || {
  echo "error: klt '${KLT_VERSION}' is not the pinned release (klt ${PIN_VERSION}); see layout/klt-pin.json" >&2; exit 2; }

PDK_WANT="$(jq -r '.open_pdks.commit' "${REPO_ROOT}/flow/pdk.json")"
PDK_VARIANT="$(jq -r '.variant' "${REPO_ROOT}/flow/pdk.json")"
PDK_GOT="$(klt pdk find --pdk "${PDK_VARIANT}" --format json | jq -r '.version')"
[ "${PDK_GOT}" = "open_pdks ${PDK_WANT}" ] || {
  echo "error: klt resolved '${PDK_GOT}', flow/pdk.json pins open_pdks ${PDK_WANT}; set PDK_ROOT" >&2; exit 2; }

# Inputs must match the hashes reuse.lock.json pins for the macro views.
rm -rf "${OUT}"
mkdir -p "${OUT}/inputs"
cp "${NETLIST_SRC}" "${OUT}/inputs/npu_top_synth.v"
cp "${MACRO_DIR}/${MACRO}.lef" "${OUT}/inputs/macro.lef"
gzip -dc "${MACRO_DIR}/${MACRO}.gds.gz" > "${OUT}/inputs/macro.gds"
cp "${HERE}/par-request.json" "${OUT}/par-request.json"
cd "${OUT}"

FAIL=0
fail() { echo "FAIL: $*" >&2; FAIL=1; }

echo "== klt place-and-route =="
klt place-and-route par-request.json --backend local --pdk "${PDK_VARIANT}" --format json > par.json 2> par.err
GDS="$(jq -r '.gds_path // empty' par.json 2>/dev/null)"
DEF="$(jq -r '.def_path // empty' par.json 2>/dev/null)"
VLOG="$(jq -r '.verilog_path // empty' par.json 2>/dev/null)"
[ "$(jq -r '.stage_reached' par.json 2>/dev/null)" = "route" ] && [ -f "${GDS}" ] && [ -f "${DEF}" ] && [ -f "${VLOG}" ] || fail "place-and-route"

PDK_ROOT_RESOLVED="$(klt pdk find --pdk "${PDK_VARIANT}" --format json | jq -r '.root')"
{
  echo "openroad $(openroad -version)"
  echo "klt ${KLT_VERSION}"
  echo "open_pdks ${PDK_WANT}"
} > tool-versions.txt
[ -f "${GDS}" ] && echo "routed gds sha256:$(sha256sum "${GDS}" | cut -d' ' -f1)" | tee -a tool-versions.txt

echo "== summary =="
jq -r '"pnr: \(.stage_reached) antenna=\(.antenna_violation_count) route_drc=\(.route_drc_violation_count)"' par.json 2>/dev/null

if [ -n "${RECORD_ID}" ]; then
  DEST="${HERE}/records/${RECORD_ID}"
  mkdir -p "${DEST}"
  # A failed run is recorded too (request, error, tool versions): a record
  # of "did not route, and why" is evidence, not clutter.
  sed -e "s#${REPO_ROOT}#<repo>#g" -e "s#${PDK_ROOT_RESOLVED}#<pdk-root>#g" par.json > "${DEST}/par.json"
  sed -e "s#${REPO_ROOT}#<repo>#g" -e "s#${PDK_ROOT_RESOLVED}#<pdk-root>#g" par.err > "${DEST}/par.err"
  cp par-request.json tool-versions.txt "${DEST}/"
  # Sourced evidence: route metrics + openroad logs (counts come from these).
  find .klt/place-and-route -maxdepth 1 -name '*_route_metrics.json' -exec cp {} "${DEST}/" \;
  for L in $(find .klt/place-and-route/openroad-logs -name stdout.log 2>/dev/null); do
    sed -e "s#${REPO_ROOT}#<repo>#g" -e "s#${PDK_ROOT_RESOLVED}#<pdk-root>#g" "${L}" | gzip -9n > "${DEST}/openroad-$(basename "$(dirname "${L}")")-stdout.log.gz"
  done
  if [ "${FAIL}" = 0 ]; then
    gzip -9n -c "${GDS}" > "${DEST}/npu_top.gds.gz"
    gzip -9n -c "${DEF}" > "${DEST}/npu_top.def.gz"
    gzip -9n -c "${VLOG}" > "${DEST}/npu_top_routed.v.gz"
    klt env-provenance lint-envelope "${DEST}"/par.json || FAIL=1
  fi
  echo "recorded -> layout/records/${RECORD_ID}/"
fi
exit "${FAIL}"
