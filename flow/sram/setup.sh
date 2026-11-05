#!/usr/bin/env bash
# Repo-local, pinned OpenRAM toolchain for the sky130 SRAM macros (issue #74).
#
# Needs only git, python3 (with venv) and curl. No conda, no Nix, no root, and
# nothing is installed outside the scratch directory. Every input is pinned by
# commit and sha256 in reuse.lock.json (pins[].name == "openram-toolchain"),
# including the hash-pinned Python wheels and the sky130A libs.tech payload.
#
#   flow/sram/setup.sh                     # fetch, verify, build overlay, run the probe
#   flow/sram/setup.sh --env-only          # stop after the overlay; print env for #51
#   flow/sram/setup.sh --record <id>       # also copy a run record to flow/sram/records/<id>/
#   SRAM_SCRATCH=/path flow/sram/setup.sh  # reuse a scratch dir (idempotent, re-verifies)
#   SETUP_PRINT_PINS=1 flow/sram/setup.sh  # print computed hashes instead of failing (pin bump)
#
# The probe is a 16 x 32 1rw1r macro with characterization and DRC/LVS off.
# It proves the environment, it is not a design macro. A run is a single local
# OpenRAM job, never a grid.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
LOCK="$REPO/reuse.lock.json"

ENV_ONLY=0
RECORD_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --env-only) ENV_ONLY=1 ;;
    --record) RECORD_ID="${2:?--record needs an id}"; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

for t in git python3 curl sha256sum; do
  command -v "$t" >/dev/null || { echo "missing required tool: $t" >&2; exit 2; }
done

# pin <dotted.path>: read one value from the toolchain pin in reuse.lock.json
pin() {
  python3 -I - "$LOCK" "$1" <<'PY'
import json, sys
lock, path = sys.argv[1], sys.argv[2].split(".")
node = next(p for p in json.load(open(lock))["pins"] if p["name"] == "openram-toolchain")
for k in path:
    node = node[k]
print(node)
PY
}

PRINT_PINS="${SETUP_PRINT_PINS:-0}"
# check <what> <expected> <actual>
check() {
  if [ "$2" = "$3" ]; then return 0; fi
  if [ "$PRINT_PINS" = 1 ]; then echo "PIN $1 = $3"; return 0; fi
  echo "FAIL: $1 mismatch" >&2
  echo "  pinned: $2" >&2
  echo "  actual: $3" >&2
  exit 3
}

# Scratch lives outside the repo.
if [ -n "${SRAM_SCRATCH:-}" ]; then
  SCRATCH="$SRAM_SCRATCH"; mkdir -p "$SCRATCH"
else
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/sky130-openram.XXXXXX")"
fi
SCRATCH="$(cd "$SCRATCH" && pwd)"
case "$SCRATCH" in "$REPO"|"$REPO"/*) echo "scratch must be outside the repo" >&2; exit 2 ;; esac
echo "scratch: $SCRATCH"

# fetch_repo <dir> <url> <commit>: clone at an exact commit, verify HEAD
fetch_repo() {
  local dir="$1" url="$2" commit="$3"
  if [ ! -d "$dir/.git" ]; then
    git init -q "$dir"
    git -C "$dir" remote add origin "$url"
  fi
  if [ "$(git -C "$dir" rev-parse -q --verify HEAD 2>/dev/null || true)" != "$commit" ]; then
    git -C "$dir" fetch -q --depth 1 origin "$commit"
    git -C "$dir" checkout -q --force FETCH_HEAD
  fi
  # The overlay edits tracked files in the OpenRAM tree, so a reused scratch
  # dir is reset to the pinned commit before it is hashed (scratch is ours).
  git -C "$dir" reset -q --hard "$commit"
  git -C "$dir" clean -fdxq
  check "$url HEAD" "$commit" "$(git -C "$dir" rev-parse HEAD)"
}

# tree_sha256 <dir>: sha256 over the sorted "sha256  path" listing of tracked files
tree_sha256() {
  ( cd "$1" && git ls-files -z | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1 )
}

OR="$SCRATCH/OpenRAM"
BD="$SCRATCH/sky130_fd_bd_sram"
SC="$SCRATCH/sky130_fd_sc_hd"
MC="$SCRATCH/sky130_sram_macros"

fetch_repo "$OR" "$(pin openram.repo)"           "$(pin openram.commit)"
fetch_repo "$BD" "$(pin sram_cells.repo)"        "$(pin sram_cells.commit)"
fetch_repo "$SC" "$(pin std_cell_views.repo)"    "$(pin std_cell_views.commit)"
fetch_repo "$MC" "$(pin macro_configs.repo)"     "$(pin macro_configs.commit)"
check "OpenRAM tree sha256"          "$(pin openram.tree_sha256)"        "$(tree_sha256 "$OR")"
check "sky130_fd_bd_sram tree sha256" "$(pin sram_cells.tree_sha256)"    "$(tree_sha256 "$BD")"
check "sky130_fd_sc_hd tree sha256"   "$(pin std_cell_views.tree_sha256)" "$(tree_sha256 "$SC")"
check "sky130_sram_macros tree sha256" "$(pin macro_configs.tree_sha256)" "$(tree_sha256 "$MC")"

# The macro configs are also pinned file by file in the macro pins (same commit).
COMMON="$MC/configs/sky130_sram_common.py"
check "sky130_sram_common.py sha256" "$(pin macro_configs.common_py_sha256)" "$(sha256sum "$COMMON" | cut -d' ' -f1)"

# --- Python venv -------------------------------------------------------------
VENV="$SCRATCH/venv"
[ -x "$VENV/bin/python" ] || python3 -m venv "$VENV"
REQS="$HERE/requirements.lock.txt"
check "requirements.lock.txt sha256" "$(pin requirements.sha256)" "$(sha256sum "$REQS" | cut -d' ' -f1)"
# --require-hashes: every wheel (and transitive dep) must match a hash in REQS.
"$VENV/bin/python" -m pip install -q --disable-pip-version-check --require-hashes -r "$REQS"

# --- sky130A tech files (SPICE models, magic/netgen rc) at the PDK pin ---------
# OpenRAM's sky130 tech reads $PDK_ROOT/sky130A/libs.tech. The commit is the one
# flow/pdk.json already pins; ciel (pinned above, in the venv) fetches that build.
PDK_COMMIT="$(python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1]))["open_pdks"]["commit"])' "$REPO/flow/pdk.json")"
export PDK_ROOT="$SCRATCH/pdk"
if [ ! -e "$PDK_ROOT/sky130A/libs.tech/ngspice/sky130.lib.spice" ]; then
  "$VENV/bin/ciel" enable --pdk-root "$PDK_ROOT" --pdk-family sky130 --include-libraries sky130_fd_sc_hd "$PDK_COMMIT"
fi
[ -e "$PDK_ROOT/sky130A/libs.tech/ngspice/sky130.lib.spice" ] || { echo "FAIL: ciel did not provide sky130A libs.tech" >&2; exit 3; }
echo "pdk: open_pdks $PDK_COMMIT"
# Hash the libs.tech payload ciel fetched, so a tampered or drifted payload fails
# before the overlay and the probe use it. Sorted "sha256  path" listing.
dir_sha256() {
  ( cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1 )
}
check "sky130A libs.tech tree sha256" "$(pin pdk_libs_tech.tree_sha256)" "$(dir_sha256 "$PDK_ROOT/sky130A/libs.tech")"

# --- Tech overlay: the same install OpenRAM's `make sky130-install` does -----
T="$OR/technology/sky130"
rm -rf "$T"/{gds_lib,mag_lib,sp_lib,lvs_lib,calibre_lvs_lib,klayout_lvs_lib,maglef_lib}
for d in gds_lib mag_lib sp_lib lvs_lib calibre_lvs_lib klayout_lvs_lib maglef_lib; do mkdir -p "$T/$d"; done
# Stage the std-cell latch OpenRAM also wants (dlxtn_1) next to the bitcell cells.
mkdir -p "$SCRATCH/stage/cells/dlxtn"
cp "$SC/cells/dlxtn/sky130_fd_sc_hd__dlxtn_1.gds" "$SC/cells/dlxtn/sky130_fd_sc_hd__dlxtn_1.spice" "$SCRATCH/stage/cells/dlxtn/"
for src in "$BD/cells" "$SCRATCH/stage/cells"; do
  for f in "$src"/*/*; do
    b="$(basename "$f")"
    case "$b" in
      *.base.spice)         cp "$f" "$T/sp_lib/${b%.base.spice}.sp" ;;
      *.lvs.calibre.spice)  cp "$f" "$T/calibre_lvs_lib/${b%.lvs.calibre.spice}.sp" ;;
      *.lvs.klayout.spice)  cp "$f" "$T/klayout_lvs_lib/${b%.lvs.klayout.spice}.sp" ;;
      *.lvs.spice)          cp "$f" "$T/lvs_lib/${b%.lvs.spice}.sp" ;;
      *.spice)              [ -e "$T/sp_lib/${b%.spice}.sp" ] || cp "$f" "$T/sp_lib/${b%.spice}.sp" ;;
      *.gds)                cp "$f" "$T/gds_lib/$b" ;;
      *.maglef)             cp "$f" "$T/maglef_lib/${b%.maglef}.mag" ;;
      *.mag)                cp "$f" "$T/mag_lib/$b" ;;
    esac
  done
done
for cell in openram_dp_cell openram_dp_cell_dummy openram_dp_cell_replica openram_dp_cell_cap_col openram_dp_cell_cap_row; do
  for d in sp_lib gds_lib; do
    ext=sp; [ "$d" = gds_lib ] && ext=gds
    [ -s "$T/$d/sky130_fd_bd_sram__$cell.$ext" ] || { echo "FAIL: overlay lacks $d/$cell.$ext" >&2; exit 3; }
  done
done

export OPENRAM_HOME="$OR/compiler"
export OPENRAM_TECH="$OR/technology"
export PYTHONPATH="$OR/compiler${PYTHONPATH:+:$PYTHONPATH}"
export PATH="$VENV/bin:$PATH"
echo "overlay ready"
echo "  export OPENRAM_HOME=$OPENRAM_HOME OPENRAM_TECH=$OPENRAM_TECH"
echo "  export PYTHONPATH=$OR/compiler   # python: $VENV/bin/python"
echo "  macro configs: $MC/configs (pinned)"
[ "$ENV_ONLY" = 1 ] && exit 0

# --- Probe run: one local job, small config ------------------------------------
OUT="$SCRATCH/probe-out"
rm -rf "$OUT"; mkdir -p "$OUT"
export SRAM_COMMON_PY="$COMMON" SRAM_OUT_DIR="$OUT"
LOG="$SCRATCH/probe.log"
START="$(date +%s)"
set +e
( cd "$SCRATCH" && "$VENV/bin/python" "$OR/sram_compiler.py" -v "$HERE/probe_16x32_1rw1r.py" ) >"$LOG" 2>&1
RC=$?
set -e
WALL=$(( $(date +%s) - START ))
echo "probe exit=$RC wall=${WALL}s log=$LOG"
OUTSTEM="$OUT/probe_sram_32x16_1rw1r"

if [ "$RC" -ne 0 ]; then
  echo "OpenRAM refused. Last lines:" >&2
  tail -20 "$LOG" >&2
fi

if [ -n "$RECORD_ID" ]; then
  REC="$HERE/records/$RECORD_ID"
  [ ! -e "$REC" ] || { echo "record $RECORD_ID exists (append-only)" >&2; exit 2; }
  mkdir -p "$REC"
  {
    echo "date_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "openram_commit: $(git -C "$OR" rev-parse HEAD)"
    echo "openram_version: $(cat "$OR/VERSION")"
    echo "sram_cells_commit: $(git -C "$BD" rev-parse HEAD)"
    echo "python: $("$VENV/bin/python" --version 2>&1)"
    echo "probe_config: flow/sram/probe_16x32_1rw1r.py (check_lvsdrc=False, analytical_delay=True)"
    echo "exit_code: $RC"
    echo "wall_seconds: $WALL"
    echo "bitcell_creation_passed: $(! grep -q 'Custom cell pin names do not match' "$LOG" && [ "$RC" -eq 0 ] && echo yes || echo no)"
    echo "outputs_sha256:"
    for ext in lef gds v; do
      f="$OUTSTEM.$ext"
      if [ -s "$f" ]; then echo "  $(sha256sum "$f" | cut -d' ' -f1)  probe_sram_32x16_1rw1r.$ext"; else echo "  MISSING  probe_sram_32x16_1rw1r.$ext"; fi
    done
  } >"$REC/run-record.txt"
  # Log with host paths replaced, so the record holds no host path.
  sed -e "s#$SCRATCH#<scratch>#g" -e "s#$REPO#<repo>#g" -e 's#/tmp/openram_[A-Za-z0-9_]*#<openram-tmp>#g' "$LOG" | tail -n 400 >"$REC/probe.log.tail"
  echo "record: $REC"
fi
exit "$RC"
