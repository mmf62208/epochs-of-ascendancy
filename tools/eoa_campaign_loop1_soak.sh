#!/usr/bin/env bash
# Headless CL1 soak. Fails closed on SCRIPT ERROR, Killed, or timeout.
# One Godot on the machine: flock -n so a busy lock does not queue a second.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if pgrep -af '[g]odot' >/dev/null; then
  echo "GODOT_BUSY" >&2
  pgrep -af '[g]odot' >&2
  exit 2
fi
tmp="$(mktemp)"
set +e
timeout 900 flock -n "${HOME}/.eoa_godot.lock" \
  "${ROOT}/tools/run_godot.sh" --headless --path . \
  -s res://scripts/core/HeadlessCampaignLoop1SoakTest.gd >"$tmp" 2>&1
ec=$?
set -e
cat "$tmp"
if grep -q "SCRIPT ERROR" "$tmp"; then
  rm -f "$tmp"
  echo "HeadlessCampaignLoop1SoakTest: RESULT=FAIL script error" >&2
  exit 1
fi
if [[ "$ec" -eq 124 ]]; then
  rm -f "$tmp"
  echo "HeadlessCampaignLoop1SoakTest: RESULT=FAIL timeout" >&2
  exit 1
fi
if [[ "$ec" -ne 0 ]]; then
  rm -f "$tmp"
  exit "$ec"
fi
if ! grep -q "RESULT=PASS" "$tmp"; then
  rm -f "$tmp"
  echo "HeadlessCampaignLoop1SoakTest: RESULT=FAIL missing PASS" >&2
  exit 1
fi
rm -f "$tmp"
exit 0
