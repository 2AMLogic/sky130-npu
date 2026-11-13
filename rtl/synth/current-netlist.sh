#!/usr/bin/env bash
#
# rtl/synth/current-netlist.sh -- print the path of the CURRENT recorded
# gate-level netlist.
#
#   ./rtl/synth/current-netlist.sh              # absolute path
#   ./rtl/synth/current-netlist.sh --relative   # path relative to the repo root
#
# The single owner of "which recorded netlist is current". It reads
# `.outputs.dir` from synth-request.json -- the same field `klt synthesize`
# writes into -- so the record the next synthesis run produces is the record
# every consumer reads, with no record id spelled out anywhere else.
# Consumers: layout/run.sh, verification/check_mutation_gl.sh, and the
# gate-level command in verification/README.md.
#
# Records are append-only: pointing at a different netlist is an edit to
# synth-request.json, never an edit to a record.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQ="${HERE}/synth-request.json"

command -v jq >/dev/null || { echo "error: jq not on PATH" >&2; exit 2; }
[ -f "${REQ}" ] || { echo "error: ${REQ} not found" >&2; exit 2; }

DIR="$(jq -er '.outputs.dir' "${REQ}")" \
  || { echo "error: ${REQ} has no .outputs.dir" >&2; exit 2; }
case "${DIR}" in
  ""|/*|*..*) echo "error: .outputs.dir '${DIR}' is not a path under rtl/synth/" >&2; exit 2 ;;
esac

NETLIST="${HERE}/${DIR}/npu_top_synth.v"
[ -f "${NETLIST}" ] || {
  echo "error: ${NETLIST} does not exist (synth-request.json .outputs.dir is '${DIR}'; run klt synthesize to make that record)" >&2
  exit 2; }

if [ "${1:-}" = "--relative" ]; then
  printf '%s\n' "rtl/synth/${DIR}/npu_top_synth.v"
else
  printf '%s\n' "${NETLIST}"
fi
