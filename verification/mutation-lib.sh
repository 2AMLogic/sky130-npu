# shellcheck shell=bash
#
# verification/mutation-lib.sh -- the preamble and the verdict both negative
# controls share. Sourced, not run.
#
#   HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   REPO_ROOT="$(dirname "${HERE}")"
#   . "${REPO_ROOT}/verification/mutation-lib.sh"
#   mutation_tmpdir
#   ... corrupt a copy under ${TMP}, then run runner.py against the copy with
#       --records-dir "${TMP}/records" --build-dir "${TMP}/build"
#       >"${TMP}/run.log" 2>&1 ...
#   rc=$?
#   mutation_verdict "${rc}" "the corrupted RTL" "at ARRAY_N=${N}"
#
# What it provides:
#
#   PY                 the interpreter runner.py is run with: the repo venv
#                      when there is one, else PYTHON, else python3
#   mutation_tmpdir    sets TMP to a fresh temp dir, removed on exit -- the
#                      corrupted copy is never inside the repo and the run
#                      writes its record to a temp ledger, not to the
#                      committed append-only one
#   mutation_verdict   "did the suite actually catch it?", exiting 0 or 1
#
# Why the verdict lives here and not in each control: it is the line between
# "the injected error was caught as a mismatch" and "the run merely failed",
# which is the whole claim a negative control makes. With a copy per control, a
# tightening applied to one leaves the other grading on the old rule, and a
# control that grades too loosely reports PASS while proving nothing.
#
# Shell options are the sourcing script's to set.

[ -n "${REPO_ROOT:-}" ] || { echo "mutation-lib.sh: REPO_ROOT must be set before sourcing" >&2; exit 2; }

PY="${PYTHON:-python3}"
if [ -x "${REPO_ROOT}/.venv/bin/python" ]; then
  PY="${REPO_ROOT}/.venv/bin/python"
fi

mutation_tmpdir() {
  TMP="$(mktemp -d)"
  trap 'rm -rf "${TMP}"' EXIT
}

# mutation_verdict RC WHAT WHERE
#
#   RC     the runner's exit status
#   WHAT   what was corrupted, for the FAIL line ("the corrupted netlist")
#   WHERE  where the catch happened, for the PASS line ("at gate level")
#
# PASS needs all four of: the run failed, it wrote a record, the failure was a
# bit-exact mismatch against expected_out.hex, and the record itself says a
# test failed and the run did not pass. Anything else is a FAIL -- no record
# means the run broke before the tests ran, and a non-mismatch failure means
# something other than the injected error took the run down. Neither is
# evidence that the suite catches a one-bit error.
#
# Reads ${TMP}/run.log and ${TMP}/records, and exits: it is the last thing a
# control does.
mutation_verdict() {
  local rc="${1?mutation_verdict: runner exit status}"
  local what="${2?mutation_verdict: what was corrupted}"
  local where="${3?mutation_verdict: where the catch happened}"
  local rec
  tail -n 12 "${TMP}/run.log"

  # shellcheck disable=SC2012  # a record id is `<timestamp>-<hex>`; no odd filenames
  rec="$(ls "${TMP}"/records/*/record.json 2>/dev/null | head -n 1)"
  if [ -z "${rec}" ]; then
    echo "FAIL: no record written (the run broke before the tests ran, rc=${rc})" >&2
    exit 1
  fi
  if [ "${rc}" -ne 0 ] && grep -q 'vs expected_out.hex: row' "${TMP}/run.log" \
     && "${PY}" -I -c 'import json,sys; r=json.load(open(sys.argv[1])); sys.exit(0 if r["failures"]>0 and not r["passed"] else 1)' "${rec}"; then
    echo "PASS: the suite caught the one-bit corruption ${where}"
    exit 0
  fi
  echo "FAIL: ${what} was NOT caught as a mismatch (rc=${rc})" >&2
  exit 1
}
