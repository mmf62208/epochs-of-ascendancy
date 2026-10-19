#!/usr/bin/env bash
# AI-CREDIBLE-1 soak. One Godot at a time. Default 4 years x 3 seeds, each
# seed twice. If the first seed exceeds 15 minutes, fall back to 1 year x
# 1 seed (still twice) and say so. Q4 in the launch brief.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
EVID="${HOME}/ai1_evidence"
mkdir -p "$EVID"

if pgrep -af '[Gg]odot_v4' >/dev/null; then
  echo "GODOT_BUSY" >&2
  pgrep -af '[Gg]odot_v4' >&2
  exit 2
fi

run_one() {
  local seed="$1" days="$2" tag="$3" credible="$4" expect="$5"
  local log="$EVID/soak_${tag}.log"
  local t0 t1 ec sec
  t0=$(date +%s)
  set +e
  timeout 1200 flock "${HOME}/.eoa_godot.lock" \
    env EOA_AIC_SOAK_SEED="$seed" EOA_AIC_SOAK_DAYS="$days" \
        EOA_AI_CREDIBLE="$credible" EOA_AIC_EXPECT_TRACE="$expect" \
    "${ROOT}/tools/run_godot.sh" --headless --path . \
    -s res://scripts/core/HeadlessAiCredible1SoakTest.gd >"$log" 2>&1
  ec=$?
  set -e
  t1=$(date +%s)
  sec=$((t1 - t0))
  echo "$sec" >"$EVID/soak_${tag}.sec"
  echo "SOAK_WALL seed=$seed days=$days tag=$tag credible=$credible sec=$sec exit=$ec"
  if grep -q "SCRIPT ERROR" "$log"; then
    echo "HeadlessAiCredible1SoakTest: RESULT=FAIL script error" >&2
    tail -40 "$log" >&2
    exit 1
  fi
  if [[ "$ec" -eq 124 ]]; then
    echo "HeadlessAiCredible1SoakTest: RESULT=FAIL timeout" >&2
    exit 1
  fi
  if [[ "$ec" -ne 0 ]]; then
    tail -40 "$log" >&2
    exit "$ec"
  fi
  if ! grep -q "RESULT=PASS" "$log"; then
    echo "HeadlessAiCredible1SoakTest: RESULT=FAIL missing PASS" >&2
    tail -40 "$log" >&2
    exit 1
  fi
  grep -E '^(TRACE_MD5=|AIC_SOAK_JSON=)' "$log" || true
}

md5_of() {
  grep -m1 '^TRACE_MD5=' "$1" | cut -d= -f2
}

compare_pair() {
  local a="$1" b="$2" label="$3"
  local ma mb
  ma=$(md5_of "$a")
  mb=$(md5_of "$b")
  if [[ -z "$ma" || "$ma" != "$mb" ]]; then
    echo "DETERMINISM FAIL $label $ma vs $mb" >&2
    exit 1
  fi
  echo "DETERMINISM OK $label $ma"
}

pair() {
  local seed="$1" days="$2"
  run_one "$seed" "$days" "${seed}_a" 1 ""
  run_one "$seed" "$days" "${seed}_b" 1 ""
  compare_pair "$EVID/soak_${seed}_a.log" "$EVID/soak_${seed}_b.log" "seed=$seed days=$days"
}

DAYS="${EOA_AIC_SOAK_DAYS:-1461}"
if [[ "${EOA_AIC_SOAK_ONE:-}" == "1" ]]; then
  pair 193601 "$DAYS"
else
  run_one 193601 "$DAYS" "193601_a" 1 ""
  first_sec=$(cat "$EVID/soak_193601_a.sec")
  if [[ "$DAYS" -ge 1461 && "$first_sec" -gt 900 ]]; then
    echo "Q4 FALLBACK: seed 193601 took ${first_sec}s (>15 min). Switching to 365 days x 1 seed."
    DAYS=365
    pair 193601 365
  else
    run_one 193601 "$DAYS" "193601_b" 1 ""
    compare_pair "$EVID/soak_193601_a.log" "$EVID/soak_193601_b.log" "seed=193601 days=$DAYS"
    pair 193602 "$DAYS"
    pair 193603 "$DAYS"
  fi
fi

run_one 193601 "$DAYS" "kill_a" 0 "empty"
run_one 193601 "$DAYS" "kill_b" 0 "empty"
compare_pair "$EVID/soak_kill_a.log" "$EVID/soak_kill_b.log" "killswitch days=$DAYS"
echo "AIC_SOAK_HARNESS RESULT=PASS days=$DAYS"
exit 0
