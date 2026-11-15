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
#
# A stamped port points the gate at its own layout with two variables (relative
# values resolve against the repo root, absolute values are used as given):
#   NPU_RTL_DIR   the 7 PDK-independent files            (default: rtl)
#   NPU_PDK_DIR   npu_sram_bank.v and macro/<macro>/<macro>.v (default: rtl/pdk/sky130)

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${HERE}")"
# The file set and the seam rule, in one place for every script that reads them.
. "${REPO_ROOT}/rtl/sources.sh"
npu_seam_dirs

mapfile -t SRC < <(npu_rtl_files "${RTL_DIR}"; npu_seam_file "${PDK_DIR}")
# Synthesis view: the same wrapper with -DNPU_SRAM_MACRO (the define
# rtl/synth/synth-request.json sets), over the pinned 1024-word macro's Verilog.
MACRO=sky130_sram_4kbyte_1rw1r_32x1024_8
MACRO_V="${PDK_DIR}/macro/${MACRO}/${MACRO}.v"
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

# The macro view carries the 1024-word macro only, which is the ARRAY_N=8 bank.
# Icarus elaborates the macro's behavioral model; Yosys reads it with -lib (ports
# only, body ignored), as a blackbox: the distro Yosys in CI aborts in
# kernel/fmt.cc on the model's $display calls, and the synthesis flow treats the
# macro as a blackbox anyway.
for n in 8; do
  if iverilog -g2012 -Wall -DNPU_SRAM_MACRO -P"${TOP}.ARRAY_N=${n}" -s "${TOP}" -o /dev/null "${SRC[@]}" "${MACRO_V}" \
     && yosys -q -p "read_verilog -sv -lib ${MACRO_V}; read_verilog -sv -defer -DNPU_SRAM_MACRO ${SRC[*]}; chparam -set ARRAY_N ${n} ${TOP}; hierarchy -check -top ${TOP}"; then
    say "PASS  ARRAY_N=${n}: synthesis view (-DNPU_SRAM_MACRO over the macro) elaborates"
  else
    say "FAIL  ARRAY_N=${n}: synthesis view (-DNPU_SRAM_MACRO over the macro) expected to elaborate"; FAIL=1
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
