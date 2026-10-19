#!/usr/bin/env bash
# SAVE-RELOAD-1 test B. Seed check, then two Godot processes one after another,
# then the in-process and autosave-inert traces. Never two Godots at once.
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

run_godot() {
  local log="$1"
  shift
  if pgrep -f 'Godot_v4|godot --headless|godot --path' >/dev/null 2>&1; then
    echo "FAIL: a Godot process is already running" >&2
    pgrep -af 'Godot_v4|godot --headless|godot --path' >&2 || true
    exit 1
  fi
  flock "$LOCK" tools/run_godot.sh --headless --path . "$@" >"$log" 2>&1
}

if [[ "${SR1_SKIP_SEED:-}" != "1" ]]; then
  # The seed harness crosses a month. Do not write Mike's autosave slots.
  EOA_CALENDAR_AUTOSAVE=0 run_godot "$LOG/sr1_det_seed.log" -s res://scripts/core/HeadlessPerf4LiveMultiAiDayTest.gd
  got="$(seed_md5 "$LOG/sr1_det_seed.log")"
  echo "SEED_MD5 $got"
  if [[ "$got" != "$EXPECT" ]]; then
    echo "FAIL: multi_ai_decisions md5 $got want $EXPECT" >&2
    exit 1
  fi
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

SR1_DET_MODE=inproc run_godot "$LOG/sr1_det_inproc.log" -s res://scripts/core/HeadlessSaveReload1DeterminismTest.gd
in_rc=$?
if [[ "$in_rc" != "0" ]]; then
  echo "FAIL: inproc rc=$in_rc" >&2
  tail -40 "$LOG/sr1_det_inproc.log" >&2
  exit 1
fi

SR1_DET_MODE=autosave SR1_REF_TRACE="$REF" run_godot "$LOG/sr1_det_autosave.log" -s res://scripts/core/HeadlessSaveReload1DeterminismTest.gd
auto_rc=$?
if [[ "$auto_rc" != "0" ]]; then
  echo "FAIL: autosave-inert rc=$auto_rc" >&2
  tail -40 "$LOG/sr1_det_autosave.log" >&2
  exit 1
fi

echo "PASS: save-reload determinism"
