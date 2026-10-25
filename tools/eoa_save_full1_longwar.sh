#!/usr/bin/env bash
# SAVE-FULL-1 long-war round trip. One Godot at a time, via tools/run_godot.sh.
# Does not kill a Godot this script did not start. Isolated XDG_DATA_HOME.
set -u
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
EVID="${EOA_EVIDENCE_DIR:-${HOME}/savefull1/evidence}"
mkdir -p "$EVID"
LOG="${EVID}/logs"
mkdir -p "$LOG"
LOCK="${HOME}/.eoa_godot.lock"
XDG="${SF1_XDG:-$(mktemp -d)}"
export XDG_DATA_HOME="$XDG"
echo "XDG=$XDG"
if pgrep -af '[g]odot' >/dev/null; then
  echo "GODOT_BUSY" >&2
  pgrep -af '[g]odot' >&2
  exit 2
fi

PIDFILE="${EVID}/sf1_own_godot.pid"

_descendants() {
  local p="$1"
  local kids c
  kids="$(cat "/proc/${p}/task/${p}/children" 2>/dev/null || true)"
  for c in $kids; do
    echo "$c"
    _descendants "$c"
  done
}

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
    echo "FAIL: this script's Godot is still running" >&2
    exit 1
  fi
  if pgrep -af '[g]odot' >/dev/null; then
    echo "GODOT_BUSY" >&2
    pgrep -af '[g]odot' >&2
    exit 2
  fi
  XDG_DATA_HOME="$XDG" flock "$LOCK" tools/run_godot.sh --headless --path . "$@" >"$log" 2>&1 &
  local wrap=$!
  local godot_pid=""
  local spins=0
  while [[ "$spins" -lt 50 ]]; do
    if ! kill -0 "$wrap" 2>/dev/null; then
      break
    fi
    local d
    while IFS= read -r d; do
      [[ -n "$d" ]] || continue
      [[ -r "/proc/${d}/cmdline" ]] || continue
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

bar_check() {
  python3 - "$1" <<'PY'
import re, sys
text = open(sys.argv[1], errors="replace").read()
save_ok = load_ok = True
for kind, limit in (("SAVE_METRIC", 1000.0), ("LOAD_METRIC", 3000.0)):
    for m in re.finditer(kind + r" day=(\d+) ms=([0-9.]+) bytes=(\d+)", text):
        ms = float(m.group(2)); nbytes = int(m.group(3))
        ok = ms <= limit and nbytes <= 8 * 1024 * 1024
        print("%s day=%s ms=%.1f bytes=%d limit_ms=%.0f size_ok=%s time_ok=%s" % (
            kind, m.group(1), ms, nbytes, limit, nbytes <= 8*1024*1024, ms <= limit))
        if not ok:
            if kind == "SAVE_METRIC":
                save_ok = False
            else:
                load_ok = False
if not save_ok or not load_ok:
    sys.exit(1)
PY
}

SF1_MODE=cont \
SF1_TRACE_400="${EVID}/sf1_cont_400.trace" \
SF1_TRACE_600="${EVID}/sf1_cont_600.trace" \
  run_godot "$LOG/sf1_cont.log" -s res://scripts/core/HeadlessSaveFull1LongWarTest.gd
cont_rc=$?
if [[ "$cont_rc" != "0" ]]; then
  echo "FAIL: cont rc=$cont_rc" >&2
  tail -50 "$LOG/sf1_cont.log" >&2
  exit 1
fi

SF1_MODE=load SF1_SLOT=sf1_d400 SF1_SAVE_DAY=400 SF1_TRACE="${EVID}/sf1_load_400.trace" \
  run_godot "$LOG/sf1_load_400.log" -s res://scripts/core/HeadlessSaveFull1LongWarTest.gd
l4=$?
if [[ "$l4" != "0" ]]; then
  echo "FAIL: load400 rc=$l4" >&2
  tail -50 "$LOG/sf1_load_400.log" >&2
  exit 1
fi

SF1_MODE=load SF1_SLOT=sf1_d600 SF1_SAVE_DAY=600 SF1_TRACE="${EVID}/sf1_load_600.trace" \
  run_godot "$LOG/sf1_load_600.log" -s res://scripts/core/HeadlessSaveFull1LongWarTest.gd
l6=$?
if [[ "$l6" != "0" ]]; then
  echo "FAIL: load600 rc=$l6" >&2
  tail -50 "$LOG/sf1_load_600.log" >&2
  exit 1
fi

if cmp -s "${EVID}/sf1_cont_400.trace" "${EVID}/sf1_load_400.trace"; then
  echo "PASS: day-400 trace matches $(md5sum "${EVID}/sf1_cont_400.trace" | awk '{print $1}')"
else
  echo "FAIL: day-400 traces differ" >&2
  diff -u "${EVID}/sf1_cont_400.trace" "${EVID}/sf1_load_400.trace" | head -20 >&2
  exit 1
fi
if cmp -s "${EVID}/sf1_cont_600.trace" "${EVID}/sf1_load_600.trace"; then
  echo "PASS: day-600 trace matches $(md5sum "${EVID}/sf1_cont_600.trace" | awk '{print $1}')"
else
  echo "FAIL: day-600 traces differ" >&2
  diff -u "${EVID}/sf1_cont_600.trace" "${EVID}/sf1_load_600.trace" | head -20 >&2
  exit 1
fi

bar_check "$LOG/sf1_cont.log" || { echo "FAIL: save bar"; exit 1; }
bar_check "$LOG/sf1_load_400.log" || { echo "FAIL: load400 bar"; exit 1; }
bar_check "$LOG/sf1_load_600.log" || { echo "FAIL: load600 bar"; exit 1; }
echo "PASS: save-full-1 long war"
