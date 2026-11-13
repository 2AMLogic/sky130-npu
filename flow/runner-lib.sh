# shellcheck shell=bash
#
# flow/runner-lib.sh -- the preamble every flow runner shares. Sourced, not run.
#
#   HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   REPO_ROOT="$(cd "${HERE}/.." && pwd)"
#   . "${REPO_ROOT}/flow/runner-lib.sh"
#   runner_parse_record "${HERE}/records" "$@"
#   runner_require_tools openroad gzip
#   runner_check_pins
#
# What it provides, in the order a runner uses it:
#
#   runner_parse_record DIR "$@"  sets RECORD_ID from `--record ID`, refusing an
#                                 id that already exists under DIR (records are
#                                 append-only)
#   runner_require_tools ...      every named tool plus uvx and jq on PATH
#   runner_check_pins             klt() wrapping the pinned release through uvx,
#                                 then the klt and open_pdks pin checks; sets
#                                 PIN_PYPI, PIN_VERSION, KLT_VERSION, PDK_WANT,
#                                 PDK_VARIANT, PDK_ROOT_RESOLVED
#   fail MSG                      record a failed gate (sets FAIL=1) and keep going
#   scrub [FILE]                  strip host paths from a recorded envelope
#
# The pins live in exactly two files -- flow/toolchain.json (klt) and
# flow/pdk.json (open_pdks, variant) -- and this is the only code that reads
# them, so a runner never carries its own copy of a pin or of a pin check.
#
# klt always runs through `uvx --from` the pinned release, never a host install:
# the host klt is not the pin and must not be changed. A runner therefore needs
# uvx on PATH, not klt.
#
# Shell options are the sourcing runner's to set (they all use
# `set -uo pipefail`: a failed gate must not stop the run, so no `-e`).

[ -n "${REPO_ROOT:-}" ] || { echo "runner-lib.sh: REPO_ROOT must be set before sourcing" >&2; exit 2; }

# A non-zero exit status for the run as a whole, set by fail(). Every step still
# runs after a failed gate so the record shows all of it; the runner ends with
# `exit "${FAIL}"`.
FAIL=0
# shellcheck disable=SC2034  # read by the sourcing runner's final `exit "${FAIL}"`
fail() { echo "FAIL: $*" >&2; FAIL=1; }

# `--record ID`: the id must be a safe directory name and must not already
# exist under DIR. Recorded results are append-only evidence -- a runner never
# overwrites a record, so a re-run under an existing id is refused here rather
# than after the tools have run.
RECORD_ID=""
runner_parse_record() {
  local records_dir="${1:?runner_parse_record: records dir}"
  shift
  [ "${1:-}" = "--record" ] || return 0
  RECORD_ID="${2:?usage: run.sh --record ID}"
  [[ "${RECORD_ID}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || { echo "bad record id" >&2; exit 2; }
  [ ! -e "${records_dir}/${RECORD_ID}" ] || { echo "record ${RECORD_ID} exists; records are append-only" >&2; exit 2; }
}

# uvx and jq are this file's own dependencies (the pinned klt and the pin
# files); a runner names only what it needs on top of them.
runner_require_tools() {
  local tool
  for tool in uvx jq "$@"; do
    command -v "${tool}" >/dev/null || { echo "error: ${tool} not on PATH" >&2; exit 2; }
  done
}

# The two pin checks, failing closed before any tool step runs.
runner_check_pins() {
  PIN_PYPI="$(jq -r '.klayout_tools.pypi' "${REPO_ROOT}/flow/toolchain.json")"
  PIN_VERSION="$(jq -r '.klayout_tools.reported_version' "${REPO_ROOT}/flow/toolchain.json")"
  klt() { uvx --from "${PIN_PYPI}" klt "$@"; }

  # Belt and braces: uvx resolves the pin, so this can only fail if the release
  # on PyPI does not report the version flow/toolchain.json says it does.
  KLT_VERSION="$(klt --version)"
  [ "${KLT_VERSION}" = "klt ${PIN_VERSION}" ] || {
    echo "error: klt '${KLT_VERSION}' is not the pinned release (klt ${PIN_VERSION}); see flow/toolchain.json" >&2; exit 2; }

  # The PDK klt resolves must be the open_pdks commit in flow/pdk.json.
  PDK_WANT="$(jq -r '.open_pdks.commit' "${REPO_ROOT}/flow/pdk.json")"
  PDK_VARIANT="$(jq -r '.variant' "${REPO_ROOT}/flow/pdk.json")"
  local pdk_json pdk_got
  pdk_json="$(klt pdk find --pdk "${PDK_VARIANT}" --format json)"
  pdk_got="$(printf '%s' "${pdk_json}" | jq -r '.version')"
  [ "${pdk_got}" = "open_pdks ${PDK_WANT}" ] || {
    echo "error: klt resolved '${pdk_got}', flow/pdk.json pins open_pdks ${PDK_WANT}; set PDK_ROOT" >&2; exit 2; }
  # The root the same query reported, for scrub() and for Liberty paths.
  PDK_ROOT_RESOLVED="$(printf '%s' "${pdk_json}" | jq -r '.root')"
}

# Recorded envelopes carry no host path: klt writes some output paths absolute
# (klayout-tools#3798, #3820), so this checkout's root becomes <repo> and the
# PDK root becomes <pdk-root>. Nothing else in an envelope is edited. Reads
# FILE, or stdin with no argument, and writes to stdout.
scrub() {
  [ -n "${PDK_ROOT_RESOLVED:-}" ] || { echo "scrub: runner_check_pins must run first" >&2; exit 2; }
  sed -e "s#${REPO_ROOT}#<repo>#g" -e "s#${PDK_ROOT_RESOLVED}#<pdk-root>#g" "$@"
}
