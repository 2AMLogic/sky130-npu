#!/usr/bin/env bash
#
# verification/check-all.sh -- the full verification.yml gate, runnable locally
# in one command. Deliberately out of scope: signoff.yml's grade check (it
# needs the pinned klt installed, which the dispatch workers forbid) and the
# CodeQL checks (they are GitHub-hosted) -- CI runs both, this script does not.
#
# .github/workflows/verification.yml is the canonical gate (attested as a
# shipped testbench in manifests/inventories/item-9.json:11); this script
# mirrors its eleven steps for local runs. The step set is no longer only
# hand-synced: verification/tests/test_check_all_parity.py (step 9 below) is
# run by both sides and fails if a step is added to one and not the other.
# The header's step list and line citations remain hand-synced.
#
# Steps, in the order run (verification.yml line):
#   1. unittest test_runner_count.py          (:52)
#   2. unittest test_source_list.py           (:53)
#   3. runner.py --param ARRAY_N=8            (:54, EXPECT_ICARUS=13.0)
#   4. runner.py --param ARRAY_N=4            (:55, EXPECT_ICARUS=13.0)
#   5. check_mutation.sh 8                    (:61)
#   6. check_mutation.sh 4                    (:62)
#   7. check_workflows.py                     (:82, uv run --with pyyaml==6.0.3)
#   8. unittest test_golden.py                (:74)
#   9. unittest test_check_all_parity.py      (:77)
#  10. rtl/check.sh                           (:95)
#  11. unittest test_relocated_layout.py      (:98, python3 -I)
#
# verification/check_mutation_gl.sh is deliberately absent: it is PDK-specific
# and not part of the workflow. verification.yml's uv-wrapped run of the
# checker's own test suite (test_check_workflows.py, :85) is deliberately
# absent too: CI-only -- each of its tests spawns a uv subprocess, so this
# gate runs the checker itself (step 7) and leaves its test suite to CI.
# Every step runs even after an earlier failure
# (the workflow's mutation step carries `if: !cancelled()` for the same
# reason), and the exit status is non-zero if any step failed. A missing tool
# is a loud exit before any step, never a silently narrowed gate.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "${HERE}")"

say() { printf '%s\n' "$*"; }

cd "${REPO}" || { say "error: cannot cd to ${REPO}" >&2; exit 2; }

PY="${PYTHON:-python3}"
[ -x "${REPO}/.venv/bin/python" ] && PY="${REPO}/.venv/bin/python"

for tool in iverilog yosys uv; do
  command -v "${tool}" >/dev/null || { say "error: ${tool} not on PATH" >&2; exit 2; }
done
if ! "${PY}" -c 'import cocotb' >/dev/null 2>&1; then
  say "error: cocotb not importable by ${PY} (verification/requirements.txt)" >&2
  exit 2
fi

FAIL=0
step() {
  local name="$1"; shift
  say "== step: ${name}"
  if "$@"; then
    say "PASS  ${name}"
  else
    say "FAIL  ${name}"; FAIL=1
  fi
}

step "unittest test_runner_count.py" \
  "${PY}" -m unittest discover -s verification/tests -p 'test_runner_count.py'

step "unittest test_source_list.py" \
  "${PY}" -m unittest discover -s verification/tests -p 'test_source_list.py'

step "runner.py --param ARRAY_N=8" \
  env EXPECT_ICARUS=13.0 "${PY}" verification/runner.py --param ARRAY_N=8

step "runner.py --param ARRAY_N=4" \
  env EXPECT_ICARUS=13.0 "${PY}" verification/runner.py --param ARRAY_N=4

step "check_mutation.sh 8" "${HERE}/check_mutation.sh" 8
step "check_mutation.sh 4" "${HERE}/check_mutation.sh" 4

step "check_workflows.py" \
  uv run --with pyyaml==6.0.3 python verification/check_workflows.py

step "unittest test_golden.py" \
  "${PY}" -m unittest discover -s verification/tests -p 'test_golden.py'

step "unittest test_check_all_parity.py" \
  "${PY}" -m unittest discover -s verification/tests -p 'test_check_all_parity.py'

step "rtl/check.sh" "${REPO}/rtl/check.sh"

step "unittest test_relocated_layout.py" \
  "${PY}" -I -m unittest discover -s verification/tests -p 'test_relocated_layout.py'

exit "${FAIL}"
