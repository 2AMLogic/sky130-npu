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

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "${HERE}")"
N="${1:-8}"
PY="${PYTHON:-python3}"
[ -x "${REPO}/.venv/bin/python" ] && PY="${REPO}/.venv/bin/python"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
cp -r "${REPO}/rtl" "${TMP}/rtl"

sed -i 's/lane_out = r\[7:0\];/lane_out = {r[7:1], ~r[0]};/' "${TMP}/rtl/npu_requant.v"
if cmp -s "${REPO}/rtl/npu_requant.v" "${TMP}/rtl/npu_requant.v"; then
  echo "FAIL: the mutation did not apply (npu_requant.v changed shape?)" >&2
  exit 1
fi
echo "mutation: $(diff "${REPO}/rtl/npu_requant.v" "${TMP}/rtl/npu_requant.v" | grep '^>' )"

SRC=()
for f in npu_top npu_host npu_ctrl npu_banks npu_array npu_pe npu_requant pdk/sky130/npu_sram_bank; do
  SRC+=("${TMP}/rtl/${f}.v")
done

TESTCASE=test_workload_mm_smoke "${PY}" "${HERE}/runner.py" \
  --sources "${SRC[@]}" --param "ARRAY_N=${N}" \
  --records-dir "${TMP}/records" --build-dir "${TMP}/build" >"${TMP}/run.log" 2>&1
rc=$?
tail -n 12 "${TMP}/run.log"

REC="$(ls "${TMP}"/records/*/record.json 2>/dev/null | head -n 1)"
if [ -z "${REC}" ]; then
  echo "FAIL: no record written (the run broke before the tests ran, rc=${rc})" >&2
  exit 1
fi
if [ "${rc}" -ne 0 ] && grep -q 'vs expected_out.hex: row' "${TMP}/run.log" \
   && "${PY}" -I -c 'import json,sys; r=json.load(open(sys.argv[1])); sys.exit(0 if r["failures"]>0 and not r["passed"] else 1)' "${REC}"; then
  echo "PASS: the suite caught the one-bit corruption at ARRAY_N=${N}"
  exit 0
fi
echo "FAIL: the corrupted RTL was NOT caught as a mismatch (rc=${rc})" >&2
exit 1
