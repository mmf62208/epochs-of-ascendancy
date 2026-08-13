#!/usr/bin/env bash
# Year multi-AI campaign: every land-owning nation is an AI agent for N days (default 365).
#
# Usage:
#   tools/eoa_year_multi_ai_test.sh                 # full 1 year, all owners
#   tools/eoa_year_multi_ai_test.sh --smoke         # 30 days, majors only (fast)
#   tools/eoa_year_multi_ai_test.sh --days 90
#   tools/eoa_year_multi_ai_test.sh --majors-only
#   tools/eoa_year_multi_ai_test.sh --max-factions 16
#   tools/eoa_year_multi_ai_test.sh --plan-only     # pure product, no Godot
#   tools/eoa_year_multi_ai_test.sh --log DIR       # capture godot log under DIR
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DAYS=365
MAJORS=0
MAX_FAC=0
PLAN_ONLY=0
SMOKE=0
LOG_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days) DAYS="$2"; shift 2 ;;
    --majors-only) MAJORS=1; shift ;;
    --max-factions) MAX_FAC="$2"; shift 2 ;;
    --plan-only) PLAN_ONLY=1; shift ;;
    --smoke) SMOKE=1; DAYS=30; MAJORS=1; shift ;;
    --log) LOG_DIR="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,15p' "$0"
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

echo "[year-ai] plan days=$DAYS majors_only=$MAJORS max_factions=$MAX_FAC smoke=$SMOKE"

python3 - << PY
import sys
sys.path.insert(0, "tools/map_generation/lib")
from year_multi_ai_campaign_product import build_year_multi_ai_campaign_product
p = build_year_multi_ai_campaign_product(
    days=int("$DAYS"),
    majors_only=bool(int("$MAJORS")),
    max_factions=int("$MAX_FAC"),
)
print(p.get("summary"))
print("factions_n", p.get("factions_n"), "run_cmd", p.get("run_cmd"))
assert p.get("ok"), p
print("PLAN_OK")
PY

if [[ "$PLAN_ONLY" -eq 1 ]]; then
  echo "[year-ai] plan-only done"
  exit 0
fi

export EOA_YEAR_AI_DAYS="$DAYS"
export EOA_YEAR_MULTI_AI=1
if [[ "$MAJORS" -eq 1 ]]; then
  export EOA_YEAR_AI_MAJORS_ONLY=1
else
  unset EOA_YEAR_AI_MAJORS_ONLY || true
fi
if [[ "$MAX_FAC" -gt 0 ]]; then
  export EOA_YEAR_AI_MAX_FACTIONS="$MAX_FAC"
else
  unset EOA_YEAR_AI_MAX_FACTIONS || true
fi

if [[ -n "$LOG_DIR" ]]; then
  mkdir -p "$LOG_DIR"
  GODOT_LOG="$LOG_DIR/year_ai_${DAYS}d_godot.log"
else
  GODOT_LOG="$(mktemp /tmp/eoa-year-ai-XXXXXX.log)"
fi

echo "[year-ai] launching Godot headless lean year AI (EOA_YEAR_MULTI_AI=1)..."
echo "[year-ai] log=$GODOT_LOG"
set +e
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessYearMultiAiCampaignTest.gd \
  >"$GODOT_LOG" 2>&1
GODOT_EC=$?
set -e

# Observables
if grep -q 'SCRIPT ERROR' "$GODOT_LOG"; then
  echo "[year-ai] FAIL: SCRIPT ERROR in log"
  grep -n 'SCRIPT ERROR' "$GODOT_LOG" | head -20
  exit 1
fi
if grep -qE 'Killed|Out of memory|Cannot allocate' "$GODOT_LOG"; then
  echo "[year-ai] FAIL: process killed / OOM"
  tail -30 "$GODOT_LOG"
  exit 1
fi
if ! grep -q 'end ok=true' "$GODOT_LOG"; then
  echo "[year-ai] FAIL: missing end ok=true (godot_ec=$GODOT_EC)"
  grep -E 'FAIL:|PASS:|end ok' "$GODOT_LOG" | tail -20
  exit 1
fi
if ! grep -q 'year_campaign_ok' "$GODOT_LOG"; then
  echo "[year-ai] FAIL: missing year_campaign_ok pass"
  exit 1
fi
if [[ "$DAYS" -ge 7 ]] && ! grep -q 'major_apply_sum=' "$GODOT_LOG"; then
  echo "[year-ai] WARN: major_apply_sum not reported (older harness?)"
fi
if [[ "$DAYS" -ge 7 ]] && grep -q 'major_apply_sum=0' "$GODOT_LOG"; then
  echo "[year-ai] FAIL: major_apply_sum=0"
  exit 1
fi

echo "[year-ai] PASS (godot_ec=$GODOT_EC log=$GODOT_LOG)"
grep -E '\[YEAR AI\] day 1/|\[YEAR AI\] day .*/365|\[YEAR AI\] result:|PASS:|end ok' "$GODOT_LOG" | tail -25
exit 0
