#!/usr/bin/env bash
#
# rtl/check.sh -- elaborate and lint the RTL with Icarus and Yosys.
#
#   ./rtl/check.sh              # N = 8 and N = 4 must pass, N = 6 and N = 16 must fail
#   ./rtl/check.sh 8 4          # only these sizes must pass; the negative cases still run
#
# The parameter is the only thing that changes between sizes. This is an
# elaboration/lint gate: it says nothing about functional correctness (that is
# the testbench issue's job).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${HERE}"

SRC=(npu_top.v npu_host.v npu_ctrl.v npu_banks.v npu_array.v npu_pe.v npu_requant.v
     pdk/sky130/npu_sram_bank.v)
# Synthesis view (macro as a black box): the same file list with the wrapper swapped.
SRC_BB=("${SRC[@]/pdk\/sky130\/npu_sram_bank.v/pdk/sky130/npu_sram_bank_bb.v}")
TOP=npu_top
GOOD=("$@"); [ "${#GOOD[@]}" -gt 0 ] || GOOD=(8 4)
BAD=(6 16)

FAIL=0
say() { printf '%s\n' "$*"; }

for tool in iverilog yosys; do
  command -v "${tool}" >/dev/null || { say "error: ${tool} not on PATH" >&2; exit 2; }
done

for n in "${GOOD[@]}"; do
  if iverilog -g2012 -Wall -P"${TOP}.ARRAY_N=${n}" -s "${TOP}" -o /dev/null "${SRC[@]}" \
     && yosys -q -p "read_verilog -sv -defer ${SRC[*]}; chparam -set ARRAY_N ${n} ${TOP}; hierarchy -check -top ${TOP}"; then
    say "PASS  ARRAY_N=${n}: iverilog + yosys hierarchy -check"
  else
    say "FAIL  ARRAY_N=${n}: expected to elaborate"; FAIL=1
  fi
done

# The black-box view carries the 1024-word macro only, which is the ARRAY_N=8 bank.
for n in 8; do
  if iverilog -g2012 -Wall -P"${TOP}.ARRAY_N=${n}" -s "${TOP}" -o /dev/null "${SRC_BB[@]}" \
     && yosys -q -p "read_verilog -sv -defer ${SRC_BB[*]}; chparam -set ARRAY_N ${n} ${TOP}; hierarchy -check -top ${TOP}"; then
    say "PASS  ARRAY_N=${n}: synthesis view (npu_sram_bank_bb.v) elaborates"
  else
    say "FAIL  ARRAY_N=${n}: synthesis view (npu_sram_bank_bb.v) expected to elaborate"; FAIL=1
  fi
done

for n in "${BAD[@]}"; do
  if iverilog -g2012 -P"${TOP}.ARRAY_N=${n}" -s "${TOP}" -o /dev/null "${SRC[@]}" >/dev/null 2>&1; then
    say "FAIL  ARRAY_N=${n}: iverilog accepted an unsupported size"; FAIL=1
  elif yosys -q -p "read_verilog -sv -defer ${SRC[*]}; chparam -set ARRAY_N ${n} ${TOP}; hierarchy -check -top ${TOP}" >/dev/null 2>&1; then
    say "FAIL  ARRAY_N=${n}: yosys accepted an unsupported size"; FAIL=1
  else
    say "PASS  ARRAY_N=${n}: rejected at elaboration by iverilog and yosys"
  fi
done

exit "${FAIL}"
