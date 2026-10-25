#!/usr/bin/env bash
# Windowed F5 garrison chip probe. gamescope headless. One Godot.
# Isolated XDG_DATA_HOME. Not Play.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if pgrep -af '[g]odot|[G]odot|[g]amescope' >/dev/null; then
  echo "GODOT_BUSY" >&2
  pgrep -af '[g]odot|[G]odot|[g]amescope' >&2
  exit 2
fi
if ! command -v gamescope >/dev/null 2>&1; then
  echo "WindowedGarrisonPerfProbe: RESULT=FAIL need gamescope" >&2
  exit 1
fi
OUT="${EOA_GARRISON_PERF_OUT:-${HOME}/garrperf1/evidence}"
mkdir -p "$OUT"
XDG="$(mktemp -d)"
echo "GARRISON_PERF xdg=$XDG out=$OUT" >&2
GODOT=(flock -n "${HOME}/.eoa_godot.lock" "${ROOT}/tools/run_godot.sh" --path . --resolution 1280x800 -s res://scripts/core/WindowedGarrisonPerfProbe.gd)
tmp="$(mktemp)"
set +e
env -u DISPLAY -u WAYLAND_DISPLAY \
  XDG_DATA_HOME="$XDG" \
  EOA_GARRISON_PERF_OUT="$OUT" \
  EOA_SMOKE_AUTO_BEGIN=1 \
  gamescope --backend headless -W 1280 -H 800 -w 1280 -h 800 -- "${GODOT[@]}" >"$tmp" 2>&1
ec=$?
set -e
cat "$tmp"
if [[ -n "${EOA_GARRISON_PERF_LOG:-}" ]]; then
  cp "$tmp" "$EOA_GARRISON_PERF_LOG"
fi
rm -rf "$XDG"
# gamescope can SIGSEGV on teardown after the child already passed.
# Addon SVG preloads during a cold import are not probe failures.
if grep -q "RESULT=PASS" "$tmp"; then
  real_err="$(grep "SCRIPT ERROR" "$tmp" | grep -v "addons/" | grep -v "unrecognized file extension" || true)"
  if [[ -z "$real_err" ]]; then
    rm -f "$tmp"
    exit 0
  fi
  echo "$real_err" >&2
fi
rm -f "$tmp"
exit "$ec"
