#!/usr/bin/env bash
# STARTUP-PARITY: empty-board 575 vs live TestScenario skip + viewport shrink.
# TEST-ONLY. NOT live Play. NEVER claims live-startup PASS.
# Does not add a standard gate. Does not change product Begin/camera/map code.
#
#   tools/eoa_startup_parity.sh
#   EOA_STARTUP_PARITY_OUT=/tmp/eoa-startup-parity tools/eoa_startup_parity.sh
#
# Order: inventory → empty-board garrison (headless) → seed hash (headless,
# EOA_PERF4_SEED_ONLY) → import → one windowed xvfb+xfwm4 process.
# Finite timeouts. Launch only via tools/run_godot.sh.
#
# STARTUP-BLANK extension (does not change the default #166 path):
#   EOA_STARTUP_BLANK=1              pointer + Enter + pointer-mutant on 1920x1200
#   EOA_STARTUP_BLANK_BEGIN=pointer  one pointer-Begin run (iteration)
#   EOA_STARTUP_BLANK_BEGIN=enter    one Enter-Begin run
#   EOA_STARTUP_BLANK_MUTANT=1       revert product fix (pointer must FAIL)
#   EOA_STARTUP_BLANK_SOAK_S=120     post-resize soak seconds (default 25 in-engine)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${EOA_STARTUP_PARITY_OUT:-/tmp/eoa-startup-parity}"
mkdir -p "$OUT" "$OUT/xdg/data" "$OUT/xdg/config" "$OUT/xdg/cache" "$OUT/xdg/saves"
export EOA_STARTUP_PARITY_OUT="$OUT"
export XDG_DATA_HOME="$OUT/xdg/data"
export XDG_CONFIG_HOME="$OUT/xdg/config"
export XDG_CACHE_HOME="$OUT/xdg/cache"
mkdir -p "$XDG_DATA_HOME/godot" "$OUT/xdg/saves"
echo "startup-parity isolated $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OUT/xdg/saves/README.txt"

unset EOA_SKIP_TITLE || true
export EOA_SMOKE_AUTO_BEGIN=0
export EOA_SMOKE_ADVANCE_PAST_PLUS6=0

echo "EOA_STARTUP_PARITY who=wrapper out=$OUT (TEST-ONLY; xvfb+xfwm4 ≠ live Play; LIVE_STARTUP=NOT_CLAIMED)"

if ! command -v xvfb-run >/dev/null 2>&1 || ! command -v Xvfb >/dev/null 2>&1; then
  echo "WindowedStartupParityTest: RESULT=FIXTURE_FAIL need xvfb" >&2
  echo "LIVE_BLANK=INCOMPLETE LIVE_STARTUP=NOT_CLAIMED" >&2
  exit 1
fi
if ! command -v xfwm4 >/dev/null 2>&1; then
  echo "WindowedStartupParityTest: RESULT=FIXTURE_FAIL need xfwm4 for maximize/resize" >&2
  echo "LIVE_BLANK=INCOMPLETE LIVE_STARTUP=NOT_CLAIMED" >&2
  exit 1
fi

GODOT_BIN=""
for c in \
  "${HOME}/Applications/Godot-4.7.1/godot" \
  "${HOME}/Applications/Godot-4.7.1/Godot_v4.7.1-stable_linux.x86_64" \
  "${HOME}/Applications/godot-latest"; do
  if [[ -x "$c" ]]; then
    GODOT_BIN="$c"
    break
  fi
done
if [[ -z "$GODOT_BIN" ]]; then
  echo "WindowedStartupParityTest: RESULT=FIXTURE_FAIL no official Godot 4.7.1 binary" >&2
  echo "LIVE_BLANK=INCOMPLETE LIVE_STARTUP=NOT_CLAIMED" >&2
  exit 1
fi
GODOT_VER="$("$GODOT_BIN" --version 2>/dev/null || true)"
echo "EOA_STARTUP_PARITY who=engine path=$GODOT_BIN version=$GODOT_VER"
if [[ "$GODOT_VER" != *"4.7.1.stable.official.a13da4feb"* ]]; then
  echo "EOA_STARTUP_PARITY LIMITATION engine_not_exact_official_a13da4feb got=$GODOT_VER" >&2
  echo "$GODOT_VER" > "$OUT/engine_mismatch.txt"
fi

echo "EOA_STARTUP_PARITY who=inventory python unittest (no Godot)"
python3 -m unittest tools.map_generation.tests.test_startup_parity_inventory -v \
  >"$OUT/inventory_unittest.log" 2>&1 || {
  echo "WindowedStartupParityTest: RESULT=FIXTURE_FAIL inventory_unittest" >&2
  tail -n 40 "$OUT/inventory_unittest.log" >&2 || true
  exit 1
}
python3 - "$OUT/inventory.json" <<'PY'
import json, sys
from pathlib import Path
sys.path.insert(0, "tools/map_generation/lib")
from startup_parity_inventory_product import build_startup_parity_inventory_product
p = build_startup_parity_inventory_product()
Path(sys.argv[1]).write_text(json.dumps(p, indent=2) + "\n", encoding="utf-8")
print("EOA_STARTUP_PARITY who=inventory status=%s provinces=%s berlin=%s" % (
    p.get("status"),
    (p.get("inventory") or {}).get("province_ids_n"),
    (p.get("inventory") or {}).get("has_berlin_710300"),
))
if not p.get("ok"):
    raise SystemExit(1)
PY

LOCK="${HOME}/.eoa_godot.lock"
if pgrep -af '[g]odot' >/dev/null; then
  echo "EOA_STARTUP_PARITY who=wrapper OTHER_GODOT_PRESENT (will not kill strangers)" >&2
  pgrep -af '[g]odot' >&2 || true
  echo "WindowedStartupParityTest: RESULT=FIXTURE_FAIL godot_busy" >&2
  echo "LIVE_BLANK=INCOMPLETE LIVE_STARTUP=NOT_CLAIMED" >&2
  exit 2
fi

cleanup() {
  local pid
  if [[ -n "${WRAP:-}" ]]; then
    kill "$WRAP" 2>/dev/null || true
  fi
  if [[ -n "${GODOT_PIDS:-}" ]]; then
    for pid in $GODOT_PIDS; do
      kill "$pid" 2>/dev/null || true
    done
  fi
  if [[ -n "${WM_PID:-}" ]]; then
    kill "$WM_PID" 2>/dev/null || true
  fi
  if [[ -n "${XVFB_PID:-}" ]]; then
    kill "$XVFB_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "EOA_STARTUP_PARITY who=import_separate timeout=1500s (headless --import --quit; before any test Godot)"
set +e
timeout 1500 flock -n "$LOCK" \
  "${ROOT}/tools/run_godot.sh" --headless --path . --import --quit \
  >"$OUT/import.log" 2>&1
imp_rc=$?
set -e
echo "EOA_STARTUP_PARITY who=import_done rc=$imp_rc"
if [[ $imp_rc -ne 0 ]]; then
  echo "WindowedStartupParityTest: RESULT=FIXTURE_FAIL import_rc=$imp_rc" >&2
  tail -n 40 "$OUT/import.log" >&2 || true
  echo "LIVE_BLANK=INCOMPLETE LIVE_STARTUP=NOT_CLAIMED" >&2
  exit 1
fi

echo "EOA_STARTUP_PARITY who=empty_board_garrison timeout=180s (headless CampaignLoopTestBoot)"
set +e
timeout 180 flock -n "$LOCK" \
  env EOA_STARTUP_PARITY_OUT="$OUT" \
  "${ROOT}/tools/run_godot.sh" --headless --path . \
  -s res://scripts/core/HeadlessStartupParityGarrisonTest.gd \
  >"$OUT/empty_board_garrison.log" 2>&1
empty_rc=$?
set -e
echo "EOA_STARTUP_PARITY who=empty_board_garrison_done rc=$empty_rc"
if [[ $empty_rc -ne 0 ]] || ! grep -q "HeadlessStartupParityGarrisonTest: RESULT=PASS" "$OUT/empty_board_garrison.log"; then
  echo "WindowedStartupParityTest: RESULT=FIXTURE_FAIL empty_board_garrison rc=$empty_rc" >&2
  tail -n 60 "$OUT/empty_board_garrison.log" >&2 || true
  exit 1
fi
grep -E "EOA_STARTUP_PARITY who=(empty_board|empty_seed|occupied_berlin)" "$OUT/empty_board_garrison.log" || true

echo "EOA_STARTUP_PARITY who=seed_hash timeout=180s (EOA_PERF4_SEED_ONLY; not the full Perf4 soak)"
set +e
timeout 180 flock -n "$LOCK" \
  env EOA_PERF4_SEED_ONLY=1 \
  "${ROOT}/tools/run_godot.sh" --headless --path . \
  -s res://scripts/core/HeadlessPerf4LiveMultiAiDayTest.gd \
  >"$OUT/seed_hash.log" 2>&1
seed_rc=$?
set -e
echo "EOA_STARTUP_PARITY who=seed_hash_done rc=$seed_rc"
python3 - "$OUT/seed_hash.log" "$OUT/seed_hash.txt" <<'PY'
import hashlib, pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(errors="replace")
got = "MISSING"
for line in text.splitlines():
    mark = "HeadlessPerf4LiveMultiAiDayTest: "
    if "multi_ai_decisions=" in line and mark in line:
        payload = line.split(mark, 1)[1]
        got = hashlib.md5((payload + "\n").encode()).hexdigest()
        break
pathlib.Path(sys.argv[2]).write_text(got + "\n", encoding="utf-8")
print("EOA_STARTUP_PARITY who=seed_hash md5=%s expect_prefix=20fe9063" % got)
if not got.startswith("20fe9063"):
    raise SystemExit(2)
PY
seed_hash_rc=$?
if [[ $seed_rc -ne 0 || $seed_hash_rc -ne 0 ]]; then
  echo "EOA_STARTUP_PARITY SEED_HASH_STOP rc=$seed_rc hash_rc=$seed_hash_rc" >&2
  echo "If the hash moved, STOP without committing a new expected seed." >&2
  tail -n 40 "$OUT/seed_hash.log" >&2 || true
  if [[ "$(cat "$OUT/seed_hash.txt" 2>/dev/null || true)" != "20fe9063de285f19d4f9b8a105abfd31" ]]; then
    echo "NEW_HASH=$(cat "$OUT/seed_hash.txt" 2>/dev/null || echo MISSING)" >&2
    exit 3
  fi
  exit 1
fi

if pgrep -af '[g]odot' >/dev/null; then
  echo "EOA_STARTUP_PARITY who=wrapper leftover_godot_after_import" >&2
  pgrep -af '[g]odot' >&2 || true
  echo "WindowedStartupParityTest: RESULT=FIXTURE_FAIL leftover_godot" >&2
  exit 2
fi

run_windowed() {
  local name="$1"
  local begin="${2:-}"
  local mutant="${3:-0}"
  local xvfb_geom="$4"
  local disp="$5"
  local expect_blank="${6:-}"
  local vdir="$OUT"
  if [[ -n "$name" ]]; then
    vdir="$OUT/$name"
  fi
  mkdir -p "$vdir"
  local log="$vdir/windowed.log"
  local rss="$vdir/rss.txt"
  : > "$rss"
  echo "EOA_STARTUP_PARITY who=windowed_one_run name=${name:-default} begin=${begin:-handle_live_begin} mutant=$mutant xvfb=$xvfb_geom display=$disp timeout=720s"

  Xvfb "$disp" -screen 0 "${xvfb_geom}x24" -ac +extension GLX +render -noreset \
    >"$vdir/xvfb.log" 2>&1 &
  XVFB_PID=$!
  sleep 0.4
  export DISPLAY="$disp"
  if command -v dbus-launch >/dev/null 2>&1; then
    # shellcheck disable=SC2046
    eval "$(dbus-launch --sh-syntax)"
  fi
  xfwm4 --replace --compositor=off --sm-client-disable >"$vdir/xfwm4.log" 2>&1 &
  WM_PID=$!
  sleep 0.6
  echo "EOA_STARTUP_PARITY who=wm name=${name:-default} xvfb_pid=$XVFB_PID xfwm4_pid=$WM_PID DISPLAY=$DISPLAY"

  local xdg_data="$XDG_DATA_HOME"
  local xdg_config="$XDG_CONFIG_HOME"
  local xdg_cache="$XDG_CACHE_HOME"
  if [[ -n "$name" ]]; then
    xdg_data="$vdir/xdg/data"
    xdg_config="$vdir/xdg/config"
    xdg_cache="$vdir/xdg/cache"
    mkdir -p "$xdg_data" "$xdg_config" "$xdg_cache"
  fi

  set +e
  timeout 720 flock -n "$LOCK" \
    env \
      EOA_STARTUP_PARITY_OUT="$vdir" \
      EOA_STARTUP_BLANK_OUT="$vdir" \
      EOA_STARTUP_BLANK_BEGIN="$begin" \
      EOA_STARTUP_BLANK_MUTANT="$mutant" \
      EOA_STARTUP_BLANK_SOAK_S="${EOA_STARTUP_BLANK_SOAK_S:-}" \
      XDG_DATA_HOME="$xdg_data" \
      XDG_CONFIG_HOME="$xdg_config" \
      XDG_CACHE_HOME="$xdg_cache" \
      DISPLAY="$disp" \
    "${ROOT}/tools/run_godot.sh" --path . --resolution 1280x800 --position 0,0 --maximized \
      -s res://scripts/core/WindowedStartupParityTest.gd \
    >"$log" 2>&1 &
  WRAP=$!
  local peak_kb=0
  while kill -0 "$WRAP" 2>/dev/null; do
    local child_kb=0
    GODOT_PIDS="$(pgrep -d ' ' -f 'WindowedStartupParityTest|Godot_v4|Applications/Godot-4.7.1/godot' 2>/dev/null || true)"
    for pid in $GODOT_PIDS; do
      [[ -z "$pid" ]] && continue
      local kb
      kb="$(awk '/VmRSS/{print $2}' "/proc/$pid/status" 2>/dev/null || true)"
      if [[ -n "${kb:-}" ]]; then
        child_kb=$((child_kb + kb))
      fi
    done
    if [[ "${child_kb:-0}" -gt "$peak_kb" ]]; then
      peak_kb="$child_kb"
    fi
    echo "rss_sample_kb=${child_kb:-0} peak_kb=$peak_kb" >> "$rss"
    sleep 2
  done
  wait "$WRAP"
  local code=$?
  set -e
  kill "$WM_PID" 2>/dev/null || true
  kill "$XVFB_PID" 2>/dev/null || true
  WM_PID=""
  XVFB_PID=""
  WRAP=""
  local mb
  mb="$(awk -v k="$peak_kb" 'BEGIN{printf "%.1f", k/1024}')"
  echo "EOA_STARTUP_PARITY who=windowed_done name=${name:-default} rc=$code rss_mb=$mb"
  LOG="$log"

  if grep -Eiq "SCRIPT ERROR|SIGSEGV" "$log"; then
    echo "WindowedStartupParityTest: RESULT=FIXTURE_FAIL engine_error name=${name:-default} log=$log"
    echo "LIVE_BLANK=INCOMPLETE LIVE_STARTUP=NOT_CLAIMED"
    grep -Ei "SCRIPT ERROR|SIGSEGV" "$log" || true
    return 1
  fi
  if grep -q "LIVE_STARTUP=PASS" "$log"; then
    echo "WindowedStartupParityTest: RESULT=FIXTURE_FAIL refused_live_startup_pass"
    return 1
  fi
  if [[ -n "$expect_blank" ]]; then
    grep -E "EOA_STARTUP_BLANK |EOA_STARTUP_PARITY |WindowedStartupParityTest:" "$log" | tail -n 60 || true
    if [[ "$expect_blank" == "PASS" ]]; then
      if ! grep -q "WindowedStartupParityTest: RESULT=COMPLETED" "$log"; then
        echo "WindowedStartupBlank: RESULT=FAIL name=$name want COMPLETED"
        tail -n 40 "$log" || true
        return 1
      fi
      if ! grep -q "STARTUP_BLANK=PASS" "$log"; then
        echo "WindowedStartupBlank: RESULT=FAIL name=$name want STARTUP_BLANK=PASS"
        return 1
      fi
    else
      if grep -q "STARTUP_BLANK=PASS" "$log"; then
        echo "WindowedStartupBlank: RESULT=FAIL name=$name mutant was not killed (STARTUP_BLANK=PASS)"
        return 1
      fi
      if ! grep -q "STARTUP_BLANK=FAIL" "$log"; then
        echo "WindowedStartupBlank: RESULT=FAIL name=$name mutant want STARTUP_BLANK=FAIL"
        return 1
      fi
      echo "EOA_STARTUP_BLANK who=mutant_killed name=$name"
    fi
    return 0
  fi

  if ! grep -q "WindowedStartupParityTest: RESULT=COMPLETED" "$log"; then
    echo "WindowedStartupParityTest: RESULT=FIXTURE_FAIL rc=$code log=$log"
    echo "LIVE_BLANK=INCOMPLETE LIVE_STARTUP=NOT_CLAIMED"
    tail -n 80 "$log" || true
    return 1
  fi
  if ! grep -q "VIEWPORT_PARITY=PASS" "$log"; then
    echo "WindowedStartupParityTest: RESULT=FIXTURE_FAIL viewport_parity_not_pass"
    echo "LIVE_BLANK=INCOMPLETE LIVE_STARTUP=NOT_CLAIMED"
    grep -E "VIEWPORT_PARITY=|who=viewport_parity|who=window_" "$log" || true
    return 1
  fi
  echo "WindowedStartupParityTest: RESULT=COMPLETED rss_mb=$mb (NOT live-startup PASS)"
  grep -E "DATA_INVARIANT=|GARRISON_SKIP=|VIEWPORT_PARITY=|LIVE_BLANK=|FIXTURE=|LIVE_STARTUP=|who=live_garrison|who=empty_seed|who=viewport_parity" "$log" || true
  return 0
}

BLANK_ALL="${EOA_STARTUP_BLANK:-0}"
BLANK_BEGIN="${EOA_STARTUP_BLANK_BEGIN:-}"
if [[ "$BLANK_ALL" == "1" || -n "$BLANK_BEGIN" ]]; then
  export EOA_STARTUP_BLANK_SOAK_S="${EOA_STARTUP_BLANK_SOAK_S:-120}"
  echo "EOA_STARTUP_BLANK who=wrapper_blank soak_s=$EOA_STARTUP_BLANK_SOAK_S begin=${BLANK_BEGIN:-all} all=$BLANK_ALL"
  overall=0
  if [[ "$BLANK_ALL" == "1" || "$BLANK_BEGIN" == "pointer" ]]; then
    if [[ "${EOA_STARTUP_BLANK_MUTANT:-0}" == "1" && "$BLANK_BEGIN" == "pointer" ]]; then
      run_windowed "mutant_pointer" "pointer" "1" "1920x1200" ":87" "FAIL" || overall=1
    else
      run_windowed "pointer" "pointer" "0" "1920x1200" ":87" "PASS" || overall=1
    fi
  fi
  if [[ "$BLANK_ALL" == "1" || "$BLANK_BEGIN" == "enter" ]]; then
    run_windowed "enter" "enter" "0" "1920x1200" ":88" "PASS" || overall=1
  fi
  if [[ "$BLANK_ALL" == "1" ]]; then
    run_windowed "mutant_pointer" "pointer" "1" "1920x1200" ":89" "FAIL" || overall=1
  fi
  if [[ -d /opt/cursor/artifacts ]]; then
    mkdir -p /opt/cursor/artifacts/startup-blank
    cp -f "$OUT"/seed_hash.txt /opt/cursor/artifacts/startup-blank/ 2>/dev/null || true
    cp -f "$OUT"/empty_board_garrison.log /opt/cursor/artifacts/startup-blank/ 2>/dev/null || true
  fi
  if [[ $overall -ne 0 ]]; then
    echo "WindowedStartupBlank: RESULT=FAIL"
    exit 1
  fi
  echo "WindowedStartupBlank: RESULT=PASS (NOT live-startup PASS)"
  exit 0
fi

# Default #166 path: 1280x800 xvfb, handle_live_begin, 860x550 shrink.
if ! run_windowed "" "" "0" "1280x800" ":91" ""; then
  exit 1
fi

if [[ -d /opt/cursor/artifacts ]]; then
  mkdir -p /opt/cursor/artifacts/startup-parity
  cp -f "$OUT"/*.json /opt/cursor/artifacts/startup-parity/ 2>/dev/null || true
  cp -f "$OUT"/*.png /opt/cursor/artifacts/startup-parity/ 2>/dev/null || true
  cp -f "${LOG:-$OUT/windowed.log}" /opt/cursor/artifacts/startup-parity/windowed.log 2>/dev/null || true
  cp -f "$OUT/empty_board_garrison.log" /opt/cursor/artifacts/startup-parity/ 2>/dev/null || true
  cp -f "$OUT/seed_hash.log" /opt/cursor/artifacts/startup-parity/ 2>/dev/null || true
  cp -f "$OUT/seed_hash.txt" /opt/cursor/artifacts/startup-parity/ 2>/dev/null || true
fi
exit 0
