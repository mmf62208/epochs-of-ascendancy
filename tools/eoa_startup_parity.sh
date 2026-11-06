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

LOG="$OUT/windowed.log"
RSS_LOG="$OUT/rss.txt"
: > "$RSS_LOG"
echo "EOA_STARTUP_PARITY who=windowed_one_run timeout=600s xvfb=1280x800 xfwm4 --maximized"

# Private X server + XFCE WM so maximize/resize ConfigureNotify reaches Godot.
# Screen matches the live pair (1280x800). xfwm4 compositor off (llvmpipe).
Xvfb :91 -screen 0 1280x800x24 -ac +extension GLX +render -noreset \
  >"$OUT/xvfb.log" 2>&1 &
XVFB_PID=$!
sleep 0.4
export DISPLAY=:91
if command -v dbus-launch >/dev/null 2>&1; then
  # shellcheck disable=SC2046
  eval "$(dbus-launch --sh-syntax)"
fi
xfwm4 --replace --compositor=off --sm-client-disable >"$OUT/xfwm4.log" 2>&1 &
WM_PID=$!
sleep 0.6
echo "EOA_STARTUP_PARITY who=wm xvfb_pid=$XVFB_PID xfwm4_pid=$WM_PID DISPLAY=$DISPLAY"

set +e
timeout 600 flock -n "$LOCK" \
  "${ROOT}/tools/run_godot.sh" --path . --resolution 1280x800 --position 0,0 --maximized \
  -s res://scripts/core/WindowedStartupParityTest.gd \
  >"$LOG" 2>&1 &
WRAP=$!
peak_kb=0
while kill -0 "$WRAP" 2>/dev/null; do
  child_kb=0
  GODOT_PIDS="$(pgrep -d ' ' -f 'WindowedStartupParityTest|Godot_v4|Applications/Godot-4.7.1/godot' 2>/dev/null || true)"
  for pid in $GODOT_PIDS; do
    [[ -z "$pid" ]] && continue
    kb="$(awk '/VmRSS/{print $2}' "/proc/$pid/status" 2>/dev/null || true)"
    if [[ -n "${kb:-}" ]]; then
      child_kb=$((child_kb + kb))
    fi
  done
  if [[ "${child_kb:-0}" -gt "$peak_kb" ]]; then
    peak_kb="$child_kb"
  fi
  echo "rss_sample_kb=${child_kb:-0} peak_kb=$peak_kb" >> "$RSS_LOG"
  sleep 2
done
wait "$WRAP"
code=$?
set -e
mb="$(awk -v k="$peak_kb" 'BEGIN{printf "%.1f", k/1024}')"
echo "EOA_STARTUP_PARITY who=windowed_done rc=$code rss_mb=$mb"

if [[ -d /opt/cursor/artifacts ]]; then
  mkdir -p /opt/cursor/artifacts/startup-parity
  cp -f "$OUT"/*.json /opt/cursor/artifacts/startup-parity/ 2>/dev/null || true
  cp -f "$OUT"/*.png /opt/cursor/artifacts/startup-parity/ 2>/dev/null || true
  cp -f "$LOG" /opt/cursor/artifacts/startup-parity/windowed.log 2>/dev/null || true
  cp -f "$OUT/empty_board_garrison.log" /opt/cursor/artifacts/startup-parity/ 2>/dev/null || true
  cp -f "$OUT/seed_hash.log" /opt/cursor/artifacts/startup-parity/ 2>/dev/null || true
  cp -f "$OUT/seed_hash.txt" /opt/cursor/artifacts/startup-parity/ 2>/dev/null || true
fi

if ! grep -q "WindowedStartupParityTest: RESULT=COMPLETED" "$LOG"; then
  echo "WindowedStartupParityTest: RESULT=FIXTURE_FAIL rc=$code log=$LOG"
  echo "LIVE_BLANK=INCOMPLETE LIVE_STARTUP=NOT_CLAIMED"
  tail -n 80 "$LOG" || true
  exit 1
fi
if grep -Eiq "SCRIPT ERROR|SIGSEGV" "$LOG"; then
  echo "WindowedStartupParityTest: RESULT=FIXTURE_FAIL engine_error log=$LOG"
  echo "LIVE_BLANK=INCOMPLETE LIVE_STARTUP=NOT_CLAIMED"
  grep -Ei "SCRIPT ERROR|SIGSEGV" "$LOG" || true
  exit 1
fi
if grep -q "LIVE_STARTUP=PASS" "$LOG"; then
  echo "WindowedStartupParityTest: RESULT=FIXTURE_FAIL refused_live_startup_pass"
  exit 1
fi
if ! grep -q "VIEWPORT_PARITY=PASS" "$LOG"; then
  echo "WindowedStartupParityTest: RESULT=FIXTURE_FAIL viewport_parity_not_pass"
  echo "LIVE_BLANK=INCOMPLETE LIVE_STARTUP=NOT_CLAIMED"
  grep -E "VIEWPORT_PARITY=|who=viewport_parity|who=window_" "$LOG" || true
  exit 1
fi
echo "WindowedStartupParityTest: RESULT=COMPLETED rss_mb=$mb (NOT live-startup PASS)"
grep -E "DATA_INVARIANT=|GARRISON_SKIP=|VIEWPORT_PARITY=|LIVE_BLANK=|FIXTURE=|LIVE_STARTUP=|who=live_garrison|who=empty_seed|who=viewport_parity" "$LOG" || true
exit 0
