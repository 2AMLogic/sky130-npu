# shellcheck shell=bash
#
# rtl/sources.sh -- which files are the design, and where the PDK seam is.
# Sourced, not run.
#
#   HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   REPO_ROOT="$(dirname "${HERE}")"
#   . "${REPO_ROOT}/rtl/sources.sh"
#   npu_seam_dirs
#   mapfile -t SRC < <(npu_rtl_files "${RTL_DIR}"; npu_seam_file "${PDK_DIR}")
#
# What it provides:
#
#   NPU_MODULES          the 7 PDK-independent module basenames, in read order
#   NPU_SEAM_BANK        the PDK-seam bank wrapper's basename
#   npu_resolve PATH     an absolute PATH as given, a relative one against
#                        REPO_ROOT (never the caller's cwd)
#   npu_seam_dirs        sets RTL_DIR and PDK_DIR from NPU_RTL_DIR / NPU_PDK_DIR
#   npu_rtl_files [DIR]  one `DIR/<module>.v` per line
#   npu_seam_file [DIR]  `DIR/<bank>.v`
#
# This is the only copy of the file set in executable shell, so adding or
# renaming an RTL module is an edit here and not in three other scripts.
#
# Two deliberate exceptions, which are not drift:
#
#   - The committed klt request files (rtl/synth/synth-request.json,
#     verification/tests/functional-verification-request.json) spell their
#     sources out. They are pinned tool inputs and cited evidence, not derived
#     lists, and they stay explicit.
#   - verification/runner.py builds the same list in Python: it is a cocotb
#     entry point and must not need a shell. That second implementation is
#     held to this one by verification/tests/test_source_list.py, which
#     compares the two file sets instead of asking a comment to be trusted.
#
# Shell options are the sourcing script's to set.

[ -n "${REPO_ROOT:-}" ] || { echo "sources.sh: REPO_ROOT must be set before sourcing" >&2; exit 2; }

# The 7 PDK-independent RTL files, in the order the tools read them.
NPU_MODULES=(npu_top npu_host npu_ctrl npu_banks npu_array npu_pe npu_requant)

# The seam: the bank wrapper is the one design file that lives under PDK_DIR.
NPU_SEAM_BANK=npu_sram_bank

npu_resolve() {
  case "${1?npu_resolve: path}" in
    /*) printf '%s\n' "$1" ;;
    *)  printf '%s\n' "${REPO_ROOT}/$1" ;;
  esac
}

# The two variables a stamped port repoints, with this repo's own layout as the
# defaults. The two directories need not be nested.
npu_seam_dirs() {
  # shellcheck disable=SC2034  # both are read by the sourcing script
  RTL_DIR="$(npu_resolve "${NPU_RTL_DIR:-rtl}")"
  # shellcheck disable=SC2034  # both are read by the sourcing script
  PDK_DIR="$(npu_resolve "${NPU_PDK_DIR:-rtl/pdk/sky130}")"
}

# One path per line, so a caller reads them with `mapfile -t`. With no DIR (or
# an empty one) the basenames come out bare, which is what a caller that has
# already cd'd into the directory wants.
npu_rtl_files() {
  local dir="${1-}" f
  for f in "${NPU_MODULES[@]}"; do
    printf '%s%s.v\n' "${dir:+${dir}/}" "${f}"
  done
}

npu_seam_file() {
  local dir="${1-}"
  printf '%s%s.v\n' "${dir:+${dir}/}" "${NPU_SEAM_BANK}"
}
