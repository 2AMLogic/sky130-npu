#!/usr/bin/env bash
#
# verification/check-all.sh -- the verification.yml gate's commands, in one
# copy. This script is the single source of the gate's step commands, and CI
# is its caller: each job in .github/workflows/verification.yml keeps its own
# tool installation and then runs one line,
#
#   ./verification/check-all.sh <group>
#
# with <group> the job's name (bitexact, golden, rtl-elaborate). With no
# argument every group runs: that is the local one-command gate.
#
# Deliberately out of scope, CI-only on purpose and left as plain workflow
# steps: the workflow checker's own test suite (verification.yml's uv-wrapped
# run of test_check_workflows.py -- each of its tests spawns a uv subprocess,
# so the gate runs the checker itself, below, and leaves the checker's test
# suite to CI), and everything in signoff.yml (its grade check needs the
# pinned klt installed, which the dispatch workers forbid; its "Every
# workflow file parses" step is the same checker run there).
#
# Tool pre-checks are per group, traced from the workflow's own jobs:
# bitexact needs Icarus and cocotb (the job installs Icarus and builds .venv
# before calling this script), golden needs only uv, rtl-elaborate needs the
# distro iverilog and yosys.
#
# Steps, in the order run:
#   bitexact:
#     1. unittest test_runner_count.py
#     2. unittest test_source_list.py
#     3. runner.py --param ARRAY_N=8   (EXPECT_ICARUS=13.0)
#     4. runner.py --param ARRAY_N=4   (EXPECT_ICARUS=13.0)
#     5. check_mutation.sh 8
#     6. check_mutation.sh 4
#   golden:
#     7. check_workflows.py            (uv run --with pyyaml==6.0.3)
#     8. unittest test_golden.py
#   rtl-elaborate:
#     9. rtl/check.sh
#    10. unittest test_relocated_layout.py  (python3 -I)
#
# verification/check_mutation_gl.sh is deliberately absent: it is PDK-specific
# and not part of the workflow. Every step runs even after an earlier failure
# (the workflow's former separate mutation step carried `if: !cancelled()` for
# the same reason, which one script call gives directly), and the exit status
# is non-zero if any step failed. A missing tool is a loud exit before any
# step, never a silently narrowed gate.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "${HERE}")"

say() { printf '%s\n' "$*"; }

usage() {
  say "usage: ${0##*/} [bitexact|golden|rtl-elaborate]   # no argument: every group" >&2
}

cd "${REPO}" || { say "error: cannot cd to ${REPO}" >&2; exit 2; }

PY="${PYTHON:-python3}"
[ -x "${REPO}/.venv/bin/python" ] && PY="${REPO}/.venv/bin/python"

GROUP="${1:-all}"
case "${GROUP}" in
  bitexact)      WANT_BITEXACT=1;  WANT_GOLDEN=0;     WANT_RTL=0 ;;
  golden)        WANT_BITEXACT=0;  WANT_GOLDEN=1;     WANT_RTL=0 ;;
  rtl-elaborate) WANT_BITEXACT=0;  WANT_GOLDEN=0;     WANT_RTL=1 ;;
  all)           WANT_BITEXACT=1;  WANT_GOLDEN=1;     WANT_RTL=1 ;;
  *) say "error: unknown group '${GROUP}'" >&2; usage; exit 2 ;;
esac

require() {
  command -v "$1" >/dev/null || { say "error: $1 not on PATH" >&2; exit 2; }
}

if [ "${WANT_BITEXACT}" = 1 ]; then
  require iverilog
  if ! "${PY}" -c 'import cocotb' >/dev/null 2>&1; then
    say "error: cocotb not importable by ${PY} (verification/requirements.txt)" >&2
    exit 2
  fi
fi
[ "${WANT_GOLDEN}" = 1 ] && require uv
if [ "${WANT_RTL}" = 1 ]; then
  require iverilog
  require yosys
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

if [ "${WANT_BITEXACT}" = 1 ]; then
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
fi

if [ "${WANT_GOLDEN}" = 1 ]; then
  step "check_workflows.py" \
    uv run --with pyyaml==6.0.3 python verification/check_workflows.py

  step "unittest test_golden.py" \
    "${PY}" -m unittest discover -s verification/tests -p 'test_golden.py'
fi

if [ "${WANT_RTL}" = 1 ]; then
  step "rtl/check.sh" "${REPO}/rtl/check.sh"

  step "unittest test_relocated_layout.py" \
    "${PY}" -I -m unittest discover -s verification/tests -p 'test_relocated_layout.py'
fi

exit "${FAIL}"
