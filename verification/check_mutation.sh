#!/usr/bin/env bash
#
# verification/check_mutation.sh -- prove the suite catches a one-bit RTL error.
#
#   ./verification/check_mutation.sh [ARRAY_N]     # default 8
#
# Copies rtl/ to a temp dir, flips the least significant bit of every in-range
# requantizer output byte there, runs the mm-smoke bit-exact test against the
# copy, and exits 0 ONLY if that test failed on a mismatch. The corrupted copy
# is never inside the repo, and the run writes its record to a temp ledger.
# Exit 1: the corruption was not caught (or the mutation did not apply, or the
# run failed for a reason other than a recorded test failure).
#
# NPU_RTL_DIR / NPU_PDK_DIR (defaults rtl, rtl/pdk/sky130; relative values
# resolve against the repo root) point it at a port's layout; the two
# directories need not be nested.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${HERE}")"
# The file set and the seam rule (rtl/sources.sh), and the temp dir and the
# verdict this control shares with check_mutation_gl.sh (mutation-lib.sh).
. "${REPO_ROOT}/rtl/sources.sh"
. "${REPO_ROOT}/verification/mutation-lib.sh"
N="${1:-8}"

mutation_tmpdir
npu_seam_dirs
mkdir "${TMP}/rtl" "${TMP}/pdk"
# Stage the tree from the list rtl/sources.sh names, not from a *.v glob: the
# staged set and the --sources set below are then the same set by
# construction (#174). macro/ stays unstaged, as the globs left it. A listed
# name with no file behind it fails here, in cp, and stops the control --
# this script has no set -e, so the failure is made explicit.
stage_listed() {
  local dest="$1" src
  while IFS= read -r src; do
    cp "${src}" "${dest}/" || {
      echo "FAIL: listed source missing or unreadable: ${src}" >&2
      exit 1
    }
  done
}
stage_listed "${TMP}/rtl" < <(npu_rtl_files "${RTL_DIR}")
stage_listed "${TMP}/pdk" < <(npu_seam_file "${PDK_DIR}")

sed -i 's/lane_out = r\[7:0\];/lane_out = {r[7:1], ~r[0]};/' "${TMP}/rtl/npu_requant.v"
if cmp -s "${RTL_DIR}/npu_requant.v" "${TMP}/rtl/npu_requant.v"; then
  echo "FAIL: the mutation did not apply (npu_requant.v changed shape?)" >&2
  exit 1
fi
echo "mutation: $(diff "${RTL_DIR}/npu_requant.v" "${TMP}/rtl/npu_requant.v" | grep '^>' )"

mapfile -t SRC < <(npu_rtl_files "${TMP}/rtl"; npu_seam_file "${TMP}/pdk")

TESTCASE=test_workload_mm_smoke "${PY}" "${HERE}/runner.py" \
  --sources "${SRC[@]}" --param "ARRAY_N=${N}" \
  --records-dir "${TMP}/records" --build-dir "${TMP}/build" >"${TMP}/run.log" 2>&1
rc=$?
mutation_verdict "${rc}" "the corrupted RTL" "at ARRAY_N=${N}"
