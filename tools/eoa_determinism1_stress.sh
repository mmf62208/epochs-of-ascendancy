#!/usr/bin/env bash
# DETERMINISM-1 loaded-CPU proof.
# Busy-loop helpers are Python, never a second Godot.
# Godot is launched only by tools/eoa_save_reload1_determinism.sh or
# tools/run_godot.sh, one at a time, each with its own XDG_DATA_HOME.
# This script never kills a Godot it did not start. It only kills the
# Python busy-loops it started.
set -u
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
EVID="${EOA_EVIDENCE_DIR:-${HOME}/determinism1/evidence}"
mkdir -p "$EVID/logs" "$EVID/stress"
ROUNDS="${SR1_STRESS_ROUNDS:-5}"
BURN_N="${SR1_BURN_N:-4}"
PIN="${SR1_CPU_PIN:-0}"
BURN_PIDS=()

stop_burners() {
  local p
  for p in "${BURN_PIDS[@]}"; do
    kill "$p" 2>/dev/null || true
    wait "$p" 2>/dev/null || true
  done
  BURN_PIDS=()
}

start_burners() {
  stop_burners
  local i
  for i in $(seq 1 "$BURN_N"); do
    taskset -c "$PIN" python3 -c 'while True: pass' >/dev/null 2>&1 &
    BURN_PIDS+=("$!")
  done
  echo "BURNERS n=${#BURN_PIDS[@]} pin=$PIN pids=${BURN_PIDS[*]}"
}

if pgrep -af '[g]odot' >/dev/null 2>&1; then
  echo "FAIL: a Godot is already running; not starting another" >&2
  pgrep -af '[g]odot' >&2 || true
  exit 1
fi

echo "=== guard self-test ==="
SR1_GUARD_SELFTEST=1 bash tools/eoa_save_reload1_determinism.sh | tee "$EVID/logs/guard_selftest.log"
self_rc=${PIPESTATUS[0]}
if [[ "$self_rc" != "0" ]]; then
  echo "FAIL: guard self-test rc=$self_rc" >&2
  exit 1
fi

echo "=== front probe under load ==="
start_burners
probe_xdg="$(mktemp -d)"
probe_log="$EVID/logs/front_probe_loaded_after.log"
set +e
XDG_DATA_HOME="$probe_xdg" taskset -c "$PIN" flock "${HOME}/.eoa_godot.lock" \
  tools/run_godot.sh --headless --path . \
  -s res://scripts/core/HeadlessDeterminism1FrontProbe.gd >"$probe_log" 2>&1
probe_rc=$?
set -e
stop_burners
tail -20 "$probe_log"
if [[ "$probe_rc" != "0" ]]; then
  echo "FAIL: loaded front probe rc=$probe_rc" >&2
  exit 1
fi

echo "=== two-process day-60 x${ROUNDS} under load ==="
start_burners
trap stop_burners EXIT
pair_md5=""
r=1
while [[ "$r" -le "$ROUNDS" ]]; do
  round_evid="$EVID/stress/pair_${r}"
  mkdir -p "$round_evid"
  echo "PAIR round $r"
  SR1_SKIP_SEED=1 SR1_SKIP_INPROC=1 SR1_CPU_PIN="$PIN" \
    SR1_XDG="$(mktemp -d)" \
    EOA_EVIDENCE_DIR="$round_evid" \
    bash tools/eoa_save_reload1_determinism.sh | tee "$round_evid/driver.log"
  rc=${PIPESTATUS[0]}
  if [[ "$rc" != "0" ]]; then
    echo "FAIL: pair round $r rc=$rc" >&2
    exit 1
  fi
  md=$(md5sum "$round_evid/sr1_ref.trace" | awk '{print $1}')
  echo "PAIR_ROUND $r md5=$md"
  if [[ -z "$pair_md5" ]]; then
    pair_md5="$md"
  elif [[ "$md" != "$pair_md5" ]]; then
    echo "FAIL: round $r md5 $md != $pair_md5" >&2
    exit 1
  fi
  r=$((r + 1))
done
echo "PASS: ${ROUNDS} loaded two-process traces md5=$pair_md5"
stop_burners

echo "=== CL1 soak x${ROUNDS} under load ==="
start_burners
soak_key=""
r=1
while [[ "$r" -le "$ROUNDS" ]]; do
  soak_xdg="$(mktemp -d)"
  soak_log="$EVID/stress/soak_${r}.log"
  echo "SOAK round $r"
  set +e
  XDG_DATA_HOME="$soak_xdg" taskset -c "$PIN" \
    bash tools/eoa_campaign_loop1_soak.sh >"$soak_log" 2>&1
  soak_rc=$?
  set -e
  if [[ "$soak_rc" != "0" ]]; then
    echo "FAIL: soak round $r rc=$soak_rc" >&2
    tail -40 "$soak_log" >&2
    exit 1
  fi
  key="$(python3 - "$soak_log" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(errors="replace")
day = ""
md5 = ""
for line in text.splitlines():
    if "S2 determinism day" in line:
        parts = line.split()
        # ... day N md5 HEX
        if "day" in parts and "md5" in parts:
            day = parts[parts.index("day") + 1]
            md5 = parts[parts.index("md5") + 1]
print(f"{day} {md5}")
PY
)"
  echo "SOAK_ROUND $r key='$key'"
  if [[ -z "$key" || "$key" == " " ]]; then
    echo "FAIL: soak round $r missing S2 determinism line" >&2
    exit 1
  fi
  if [[ -z "$soak_key" ]]; then
    soak_key="$key"
  elif [[ "$key" != "$soak_key" ]]; then
    echo "FAIL: soak round $r '$key' != '$soak_key'" >&2
    exit 1
  fi
  r=$((r + 1))
done
stop_burners
trap - EXIT
echo "PASS: ${ROUNDS} loaded soaks key=$soak_key"
echo "STRESS_DONE pair_md5=$pair_md5 soak_key=$soak_key"
