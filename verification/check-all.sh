#!/usr/bin/env bash
#
# verification/check-all.sh -- the full CI gate, runnable locally in one command.
#
# .github/workflows/verification.yml is the canonical gate (attested as a
# shipped testbench in manifests/inventories/item-9.json:11); this script
# mirrors its eight steps for local runs and is kept in step with it by hand --
# nothing here detects drift, so if they diverge the workflow wins.
#
# Steps, in the order run (verification.yml line):
#   1. unittest test_runner_count.py          (:52)
#   2. runner.py --param ARRAY_N=8            (:53, EXPECT_ICARUS=13.0)
#   3. runner.py --param ARRAY_N=4            (:54, EXPECT_ICARUS=13.0)
#   4. check_mutation.sh 8                    (:60)
#   5. check_mutation.sh 4                    (:61)
#   6. unittest test_golden.py                (:73)
#   7. rtl/check.sh                           (:91)
#   8. unittest test_relocated_layout.py      (:94, python3 -I)
#
# verification/check_mutation_gl.sh is deliberately absent: it is PDK-specific
# and not part of the workflow. Every step runs even after an earlier failure
# (the workflow's mutation step carries `if: !cancelled()` for the same
# reason), and the exit status is non-zero if any step failed. A missing tool
# is a loud exit before any step, never a silently narrowed gate.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "${HERE}")"

PY="${PYTHON:-python3}"
[ -x "${REPO}/.venv/bin/python" ] && PY="${REPO}/.venv/bin/python"

say() { printf '%s\n' "$*"; }

for tool in iverilog yosys; do
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

step "runner.py --param ARRAY_N=8" \
  env EXPECT_ICARUS=13.0 "${PY}" verification/runner.py --param ARRAY_N=8

step "runner.py --param ARRAY_N=4" \
  env EXPECT_ICARUS=13.0 "${PY}" verification/runner.py --param ARRAY_N=4

step "check_mutation.sh 8" "${HERE}/check_mutation.sh" 8
step "check_mutation.sh 4" "${HERE}/check_mutation.sh" 4

step "unittest test_golden.py" \
  "${PY}" -m unittest discover -s verification/tests -p 'test_golden.py'

step "rtl/check.sh" "${REPO}/rtl/check.sh"

step "unittest test_relocated_layout.py" \
  "${PY}" -I -m unittest discover -s verification/tests -p 'test_relocated_layout.py'

exit "${FAIL}"
