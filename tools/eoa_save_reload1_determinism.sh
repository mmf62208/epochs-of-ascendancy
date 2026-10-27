#!/usr/bin/env bash
# DETERMINISM-1 / SAVE-RELOAD-1 two-process trace.
# One Godot at a time, launched only through tools/run_godot.sh.
# The guard watches this script's own Godot child. An unrelated Godot does
# not abort the run. This script never kills a Godot process.
set -u
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
EVID="${EOA_EVIDENCE_DIR:-}"
if [[ -z "$EVID" ]]; then
  EVID="/tmp/eoa_sr1_evidence"
fi
export EOA_EVIDENCE_DIR="$EVID"
LOG="${EVID}/logs"
mkdir -p "$LOG" "$EVID"
LOCK="${HOME}/.eoa_godot.lock"
REF="${EVID}/sr1_ref.trace"
LOAD="${EVID}/sr1_load.trace"
EXPECT="20fe9063de285f19d4f9b8a105abfd31"
PIDFILE="${SR1_OWN_PIDFILE:-${EVID}/sr1_own_godot.pid}"
if [[ -z "${SR1_XDG:-}" ]]; then
  SR1_XDG="$(mktemp -d)"
fi
export SR1_XDG

seed_md5() {
  local log="$1"
  python3 - "$log" <<'PY'
import hashlib, pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(errors="replace")
for line in text.splitlines():
    mark = "HeadlessPerf4LiveMultiAiDayTest: "
    if "multi_ai_decisions=" in line and mark in line:
        payload = line.split(mark, 1)[1]
        print(hashlib.md5((payload + "\n").encode()).hexdigest())
        break
else:
    print("MISSING")
PY
}

_descendants() {
  local p="$1"
  local kids c
  kids="$(cat "/proc/${p}/task/${p}/children" 2>/dev/null || true)"
  for c in $kids; do
    echo "$c"
    _descendants "$c"
  done
}

# True only when the pid we started is still a live Godot.
own_godot_alive() {
  [[ -f "$PIDFILE" ]] || return 1
  local pid cmd
  pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  cmd="$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)"
  case "$cmd" in
    *godot*|*Godot*) return 0 ;;
  esac
  return 1
}

run_godot() {
  local log="$1"
  shift
  if own_godot_alive; then
    echo "FAIL: this script's Godot is still running (pid $(cat "$PIDFILE"))" >&2
    exit 1
  fi
  if [[ -n "${SR1_CPU_PIN:-}" ]]; then
    XDG_DATA_HOME="$SR1_XDG" taskset -c "$SR1_CPU_PIN" flock "$LOCK" tools/run_godot.sh --headless --path . "$@" >"$log" 2>&1 &
  else
    XDG_DATA_HOME="$SR1_XDG" flock "$LOCK" tools/run_godot.sh --headless --path . "$@" >"$log" 2>&1 &
  fi
  local wrap=$!
  local godot_pid=""
  local spins=0
  while [[ "$spins" -lt 50 ]]; do
    if ! kill -0 "$wrap" 2>/dev/null; then
      break
    fi
    local d
    # Descendants of the wrapper. run_godot.sh execs the engine, so the
    # matching cmdline is the Godot we started.
    while IFS= read -r d; do
      [[ -n "$d" ]] || continue
      local dcmd
      dcmd="$(tr '\0' ' ' < "/proc/${d}/cmdline" 2>/dev/null || true)"
      case "$dcmd" in
        *godot*|*Godot*) godot_pid="$d" ;;
      esac
    done < <(_descendants "$wrap")
    if [[ -n "$godot_pid" ]]; then
      break
    fi
    spins=$((spins + 1))
    sleep 0.1
  done
  if [[ -n "$godot_pid" ]]; then
    echo "$godot_pid" >"$PIDFILE"
  fi
  local rc=0
  wait "$wrap" || rc=$?
  rm -f "$PIDFILE"
  return "$rc"
}

if [[ "${SR1_GUARD_SELFTEST:-}" == "1" ]]; then
  # A process whose argv[0] looks like Godot. The old global pgrep aborted.
  # This script must continue, and it must not kill that process itself
  # except the sleep this test started (it is not a Godot engine).
  exec -a Godot_v4 sleep 30 &
  fake=$!
  old=0
  if pgrep -f 'Godot_v4|godot --headless|godot --path' >/dev/null 2>&1; then
    old=1
  fi
  echo "OLD_GUARD_WOULD_ABORT=$old fake_pid=$fake"
  if own_godot_alive; then
    echo "FAIL: scoped guard treated pid $fake as this script's Godot" >&2
    kill "$fake" 2>/dev/null || true
    wait "$fake" 2>/dev/null || true
    exit 1
  fi
  if ! kill -0 "$fake" 2>/dev/null; then
    echo "FAIL: self-test sleep died before the guard check" >&2
    exit 1
  fi
  echo "NEW_GUARD_CONTINUES=1"
  kill "$fake" 2>/dev/null || true
  wait "$fake" 2>/dev/null || true
  echo "PASS: guard self-test"
  exit 0
fi

if [[ "${SR1_SKIP_SEED:-}" != "1" ]]; then
  EOA_CALENDAR_AUTOSAVE=0 run_godot "$LOG/sr1_det_seed.log" -s res://scripts/core/HeadlessPerf4LiveMultiAiDayTest.gd
  seed_rc=$?
  if [[ "$seed_rc" != "0" ]]; then
    echo "FAIL: seed process rc=$seed_rc" >&2
    tail -40 "$LOG/sr1_det_seed.log" >&2
    exit 1
  fi
  got="$(seed_md5 "$LOG/sr1_det_seed.log")"
  echo "SEED_MD5 $got"
  if [[ "$got" != "$EXPECT" ]]; then
    echo "FAIL: multi_ai_decisions md5 $got want $EXPECT" >&2
    exit 1
  fi
fi

if [[ "${SR1_SKIP_PAIR:-}" == "1" ]]; then
  echo "PASS: seed-only"
  exit 0
fi

SR1_DET_MODE=ref SR1_TRACE="$REF" run_godot "$LOG/sr1_det_ref.log" -s res://scripts/core/HeadlessSaveReload1DeterminismTest.gd
ref_rc=$?
if [[ "$ref_rc" != "0" ]]; then
  echo "FAIL: ref process rc=$ref_rc" >&2
  tail -40 "$LOG/sr1_det_ref.log" >&2
  exit 1
fi

SR1_DET_MODE=load SR1_TRACE="$LOAD" run_godot "$LOG/sr1_det_load.log" -s res://scripts/core/HeadlessSaveReload1DeterminismTest.gd
load_rc=$?
if [[ "$load_rc" != "0" ]]; then
  echo "FAIL: load process rc=$load_rc" >&2
  tail -40 "$LOG/sr1_det_load.log" >&2
  exit 1
fi

if cmp -s "$REF" "$LOAD"; then
  echo "PASS: two-process traces match $(md5sum "$REF" | awk '{print $1}')"
else
  echo "FAIL: two-process traces differ" >&2
  diff -u "$REF" "$LOAD" | head -40 >&2
  exit 1
fi

if [[ "${SR1_SKIP_INPROC:-}" == "1" ]]; then
  echo "PASS: save-reload determinism (pair only)"
  exit 0
fi

SR1_DET_MODE=inproc run_godot "$LOG/sr1_det_inproc.log" -s res://scripts/core/HeadlessSaveReload1DeterminismTest.gd
in_rc=$?
if [[ "$in_rc" != "0" ]]; then
  echo "FAIL: inproc rc=$in_rc" >&2
  tail -40 "$LOG/sr1_det_inproc.log" >&2
  exit 1
fi

echo "PASS: save-reload determinism"
