#!/usr/bin/env bash
# STARTUP-GUARD: one bounded windowed Begin→post-dismiss diagnostic.
# TEST-ONLY. NOT live Play. NEVER claims live-startup PASS.
# Does not add a standard gate. Does not change product code.
#
#   tools/eoa_startup_guard.sh
#   EOA_STARTUP_GUARD_OUT=/tmp/eoa-startup-guard tools/eoa_startup_guard.sh
#
# Finite timeout: import 1500s (separate), windowed Godot 600s.
# One Godot at a time. Launch only via tools/run_godot.sh.
# Isolated nonempty XDG. Cleans up PIDs this script started.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${EOA_STARTUP_GUARD_OUT:-/tmp/eoa-startup-guard}"
mkdir -p "$OUT" "$OUT/xdg/data" "$OUT/xdg/config" "$OUT/xdg/cache" "$OUT/xdg/saves"
export EOA_STARTUP_GUARD_OUT="$OUT"
export XDG_DATA_HOME="$OUT/xdg/data"
export XDG_CONFIG_HOME="$OUT/xdg/config"
export XDG_CACHE_HOME="$OUT/xdg/cache"
# Godot user:// follows XDG; keep saves nonempty-isolated.
mkdir -p "$XDG_DATA_HOME/godot" "$OUT/xdg/saves"
echo "startup-guard isolated $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OUT/xdg/saves/README.txt"

unset EOA_SKIP_TITLE || true
export EOA_SMOKE_AUTO_BEGIN=0
export EOA_SMOKE_ADVANCE_PAST_PLUS6=0

echo "EOA_STARTUP_GUARD who=wrapper out=$OUT (TEST-ONLY; xvfb ≠ live Play; LIVE_STARTUP=NOT_CLAIMED)"

if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "WindowedStartupGuardTest: RESULT=FIXTURE_FAIL need xvfb-run" >&2
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
  echo "WindowedStartupGuardTest: RESULT=FIXTURE_FAIL no official Godot 4.7.1 binary" >&2
  echo "LIVE_BLANK=INCOMPLETE LIVE_STARTUP=NOT_CLAIMED" >&2
  exit 1
fi
GODOT_VER="$("$GODOT_BIN" --version 2>/dev/null || true)"
echo "EOA_STARTUP_GUARD who=engine path=$GODOT_BIN version=$GODOT_VER"
if [[ "$GODOT_VER" != *"4.7.1.stable.official.a13da4feb"* ]]; then
  echo "EOA_STARTUP_GUARD LIMITATION engine_not_exact_official_a13da4feb got=$GODOT_VER" >&2
  echo "LIVE_BLANK=INCOMPLETE LIVE_STARTUP=NOT_CLAIMED (will not treat this as window acceptance)" >&2
  echo "$GODOT_VER" > "$OUT/engine_mismatch.txt"
fi

echo "EOA_STARTUP_GUARD who=inventory python unittest (no Godot)"
python3 -m unittest tools.map_generation.tests.test_startup_guard_inventory -v \
  >"$OUT/inventory_unittest.log" 2>&1 || {
  echo "WindowedStartupGuardTest: RESULT=FIXTURE_FAIL inventory_unittest" >&2
  tail -n 40 "$OUT/inventory_unittest.log" >&2 || true
  exit 1
}
python3 - "$OUT/inventory.json" <<'PY'
import json, sys
from pathlib import Path
sys.path.insert(0, "tools/map_generation/lib")
from startup_guard_inventory_product import build_startup_guard_inventory_product
p = build_startup_guard_inventory_product()
Path(sys.argv[1]).write_text(json.dumps(p, indent=2) + "\n", encoding="utf-8")
print("EOA_STARTUP_GUARD who=inventory status=%s provinces=%s berlin=%s" % (
    p.get("status"),
    (p.get("inventory") or {}).get("province_ids_n"),
    (p.get("inventory") or {}).get("has_berlin_710300"),
))
if not p.get("ok"):
    raise SystemExit(1)
PY

LOCK="${HOME}/.eoa_godot.lock"
if pgrep -af '[g]odot' >/dev/null; then
  echo "EOA_STARTUP_GUARD who=wrapper OTHER_GODOT_PRESENT (will not kill strangers)" >&2
  pgrep -af '[g]odot' >&2 || true
  echo "WindowedStartupGuardTest: RESULT=FIXTURE_FAIL godot_busy" >&2
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
}
trap cleanup EXIT

echo "EOA_STARTUP_GUARD who=import_separate timeout=1500s (headless --import --quit; not the windowed acceptance)"
set +e
timeout 1500 flock -n "$LOCK" \
  "${ROOT}/tools/run_godot.sh" --headless --path . --import --quit \
  >"$OUT/import.log" 2>&1
imp_rc=$?
set -e
echo "EOA_STARTUP_GUARD who=import_done rc=$imp_rc"
if [[ $imp_rc -ne 0 ]]; then
  echo "WindowedStartupGuardTest: RESULT=FIXTURE_FAIL import_rc=$imp_rc" >&2
  tail -n 40 "$OUT/import.log" >&2 || true
  echo "LIVE_BLANK=INCOMPLETE LIVE_STARTUP=NOT_CLAIMED" >&2
  exit 1
fi

if pgrep -af '[g]odot' >/dev/null; then
  echo "EOA_STARTUP_GUARD who=wrapper leftover_godot_after_import" >&2
  pgrep -af '[g]odot' >&2 || true
  echo "WindowedStartupGuardTest: RESULT=FIXTURE_FAIL leftover_godot" >&2
  exit 2
fi

LOG="$OUT/windowed.log"
RSS_LOG="$OUT/rss.txt"
: > "$RSS_LOG"
echo "EOA_STARTUP_GUARD who=windowed_one_run timeout=600s xvfb=1280x800 (NOT --maximized; NOT live Play)"
set +e
timeout 600 xvfb-run -a -s "-screen 0 1280x800x24" \
  flock -n "$LOCK" \
  "${ROOT}/tools/run_godot.sh" --path . --resolution 1280x800 --position 0,0 \
  -s res://scripts/core/WindowedStartupGuardTest.gd \
  >"$LOG" 2>&1 &
WRAP=$!
peak_kb=0
while kill -0 "$WRAP" 2>/dev/null; do
  child_kb=0
  GODOT_PIDS="$(pgrep -d ' ' -f 'WindowedStartupGuardTest|Godot_v4|Applications/Godot-4.7.1/godot' 2>/dev/null || true)"
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
echo "EOA_STARTUP_GUARD who=windowed_done rc=$code rss_mb=$mb"

if [[ -d /opt/cursor/artifacts ]]; then
  mkdir -p /opt/cursor/artifacts/startup-guard
  cp -f "$OUT"/*.json /opt/cursor/artifacts/startup-guard/ 2>/dev/null || true
  cp -f "$OUT"/*.png /opt/cursor/artifacts/startup-guard/ 2>/dev/null || true
  cp -f "$LOG" /opt/cursor/artifacts/startup-guard/windowed.log 2>/dev/null || true
fi

if ! grep -q "WindowedStartupGuardTest: RESULT=COMPLETED" "$LOG"; then
  echo "WindowedStartupGuardTest: RESULT=FIXTURE_FAIL rc=$code log=$LOG"
  echo "LIVE_BLANK=INCOMPLETE LIVE_STARTUP=NOT_CLAIMED"
  tail -n 80 "$LOG" || true
  exit 1
fi
if grep -Eiq "SCRIPT ERROR|SIGSEGV" "$LOG"; then
  echo "WindowedStartupGuardTest: RESULT=FIXTURE_FAIL engine_error log=$LOG"
  echo "LIVE_BLANK=INCOMPLETE LIVE_STARTUP=NOT_CLAIMED"
  grep -Ei "SCRIPT ERROR|SIGSEGV" "$LOG" || true
  exit 1
fi
if grep -q "LIVE_STARTUP=PASS" "$LOG"; then
  echo "WindowedStartupGuardTest: RESULT=FIXTURE_FAIL refused_live_startup_pass"
  exit 1
fi
echo "WindowedStartupGuardTest: RESULT=COMPLETED rss_mb=$mb (NOT live-startup PASS)"
grep -E "DATA_INVARIANT=|LIVE_BLANK=|FIXTURE=|LIVE_STARTUP=" "$LOG" || true
exit 0
