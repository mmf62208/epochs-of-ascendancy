#!/usr/bin/env bash
# UI-PERF-1 / BOOT-PERF-1 windowed probe. gamescope headless 1280x800.
# Isolated XDG. Not live Play. One Godot. Does not kill a Godot this script
# did not start.
#
# Exits 0 only when the probe JSON says PASS and boot_ms is within the
# side-task bar (main 477bdf00 median boot_chips_ms 34851 + 300 = 35151).
# 3a5042e1 warms every map-mode fill during boot and fails this bar.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if pgrep -af '[g]odot' >/dev/null; then
  echo "GODOT_BUSY" >&2
  pgrep -af '[g]odot' >&2
  exit 2
fi
OUT="${1:-${HOME}/uiperf1/evidence/probe.json}"
mkdir -p "$(dirname "$OUT")"
if ! command -v gamescope >/dev/null 2>&1; then
  echo "WindowedUiPerf1Probe: RESULT=FAIL need gamescope" >&2
  exit 1
fi
# Side-task main median boot_chips_ms + 300. See ~/bootperf1/evidence/side/METHOD.md.
BOOT_BAR_MS=35151
XDG_DATA_HOME="$(mktemp -d)"
XDG_CONFIG_HOME="$(mktemp -d)"
XDG_CACHE_HOME="$(mktemp -d)"
export XDG_DATA_HOME XDG_CONFIG_HOME XDG_CACHE_HOME
echo "UI_PERF1 xdg_data=$XDG_DATA_HOME out=$OUT boot_bar_ms=$BOOT_BAR_MS" >&2
console="${OUT}.console"
set +e
env -u DISPLAY -u WAYLAND_DISPLAY \
  gamescope --backend headless -W 1280 -H 800 -w 1280 -h 800 -- \
  flock -n "${HOME}/.eoa_godot.lock" "${ROOT}/tools/run_godot.sh" --path . --resolution 1280x800 \
  -s res://scripts/core/WindowedUiPerf1Probe.gd -- --out "$OUT" >"$console" 2>&1
ec=$?
set -e
cat "$console"
rm -rf "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
# gamescope can SIGSEGV on teardown after the child has written the JSON.
if [[ ! -f "$OUT" ]]; then
  echo "WindowedUiPerf1Probe: RESULT=FAIL no json ec=$ec" >&2
  exit 1
fi
python3 - "$OUT" "$BOOT_BAR_MS" <<'PY'
import json, sys
path, bar_s = sys.argv[1], sys.argv[2]
bar = int(bar_s)
d = json.load(open(path))
boot = int(d.get("boot_ms", 10**9))
result = str(d.get("result", ""))
grade = d.get("grade", {}) if isinstance(d.get("grade"), dict) else {}
print(
    "UI_PERF1 shell boot_ms=%d bar=%d result=%s grade_boot=%s during_warm=%s map=%s"
    % (
        boot,
        bar,
        result,
        grade.get("boot", ""),
        grade.get("during_warm", ""),
        grade.get("map", ""),
    )
)
if result != "PASS" or boot > bar:
    sys.exit(1)
sys.exit(0)
PY
