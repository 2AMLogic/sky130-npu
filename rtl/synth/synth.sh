#!/usr/bin/env bash
#
# rtl/synth/synth.sh -- generic Yosys synthesis estimate (no cell library).
#
#   ./rtl/synth/synth.sh 8 core      # logic only: npu_sram_bank is a black box
#   ./rtl/synth/synth.sh 8 full      # behavioral SRAM model included (flops!)
#   ./rtl/synth/synth.sh 4 core
#
# Prints the `stat` section. Cell counts are an ESTIMATE from Yosys's internal
# gate library (no Liberty, no ABC mapping to sky130): not area, not timing,
# not signoff. `full` turns every SRAM bit into a flop: about 6 minutes and
# 2.4 GB at N = 8, so it is not run in CI. `core` takes about 5 minutes at
# N = 8 (almost all of it ABC on the multiplier array) and 340 MB.
#
# The sky130-mapped synthesis request is synth-request.json next to this file;
# see rtl/synth/README.md.

set -euo pipefail
N="${1:?usage: synth.sh N core|full}"
MODE="${2:?usage: synth.sh N core|full}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/../.." && pwd)"
# The file set, from the one place that spells it out. This script reads the
# files cd-relative and does NOT honour NPU_RTL_DIR / NPU_PDK_DIR, so it takes
# the basenames and not npu_seam_dirs: verification/README.md names the three
# scripts that read the seam, and this is deliberately not one of them.
. "${REPO_ROOT}/rtl/sources.sh"
cd "${HERE}/.."

mapfile -t CORE_FILES < <(npu_rtl_files "")   # "": bare basenames, cd-relative
CORE="${CORE_FILES[*]}"
BANK="$(npu_seam_file pdk/sky130)"
case "${MODE}" in
  core) READ="read_verilog -sv -lib ${BANK}; read_verilog -sv ${CORE}" ;;
  full) READ="read_verilog -sv ${CORE} ${BANK}" ;;
  *) echo "mode must be core or full" >&2; exit 2 ;;
esac

yosys -q -p "${READ}; chparam -set ARRAY_N ${N} npu_top; hierarchy -check -top npu_top; synth -top npu_top -flatten; tee -o /dev/stdout stat"
