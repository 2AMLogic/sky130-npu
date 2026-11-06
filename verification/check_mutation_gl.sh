#!/usr/bin/env bash
#
# verification/check_mutation_gl.sh -- negative control at GATE level.
#
#   ./verification/check_mutation_gl.sh [NETLIST]
#
# Copies the recorded synthesized netlist to a temp dir, inverts the output of
# the requantizer's out_word[0] flop there, runs the mm-smoke bit-exact test
# against the copy (pre-layout, functional cells, SRAM stand-in; see
# verification/README.md "Gate-level run"), and exits 0 ONLY if that test failed
# on a mismatch with expected_out.hex. The recorded netlist is never touched and
# the run writes its record to a temp ledger.
# Exit 1: the corruption was not caught, the mutation did not apply, or the run
# failed for another reason.
#
# PDK_VERILOG_DIR overrides the sky130_fd_sc_hd Verilog directory (default:
# ~/.ciel/sky130A/libs.ref/sky130_fd_sc_hd/verilog).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "${HERE}")"
NETLIST="${1:-${REPO}/rtl/synth/records/20261027-sky130-hd/npu_top_synth.v}"
LIB="${PDK_VERILOG_DIR:-${HOME}/.ciel/sky130A/libs.ref/sky130_fd_sc_hd/verilog}"
PY="${PYTHON:-python3}"
[ -x "${REPO}/.venv/bin/python" ] && PY="${REPO}/.venv/bin/python"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

"${PY}" -I - "${NETLIST}" "${TMP}/mutant.v" <<'PY' || { echo "FAIL: the mutation did not apply (netlist changed shape?)" >&2; exit 1; }
import re, sys
src = open(sys.argv[1]).read()
pat = re.compile(r"(\.Q\()out_word\[0\](\)\s*\);)")
if len(pat.findall(src)) != 1:
    sys.exit(1)
src = pat.sub(r"\1_mut_q_\2", src)
# inside module npu_requant: declare the inverted net before its first use (the
# header), drive out_word[0] from it at the end (after the port declarations)
hdr = src.index("module npu_requant(")
semi = src.index(";", hdr) + 1
end = src.index("endmodule", hdr)
src = (src[:semi] + "\n  wire _mut_q_;" + src[semi:end]
       + "  assign out_word[0] = ~_mut_q_;\n" + src[end:])
open(sys.argv[2], "w").write(src)
PY
echo "mutation: requant out_word[0] flop output inverted"

TESTCASE=test_workload_mm_smoke "${PY}" "${HERE}/runner.py" \
  --toplevel npu_top \
  --sources "${TMP}/mutant.v" "${LIB}/primitives.v" "${LIB}/sky130_fd_sc_hd.v" \
            "${HERE}/models/sky130_sram_4kbyte_standin.v" \
  --define FUNCTIONAL --define 'UNIT_DELAY=#0' --baked-param ARRAY_N=8 \
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
  echo "PASS: the suite caught the one-bit corruption at gate level"
  exit 0
fi
echo "FAIL: the corrupted netlist was NOT caught as a mismatch (rc=${rc})" >&2
exit 1
