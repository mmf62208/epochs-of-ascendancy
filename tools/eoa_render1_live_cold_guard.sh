#!/usr/bin/env bash
# WINDOWED RENDER-1 live-boot cold L-on. xvfb is NOT product Play.
# Each wrapper run boots A (5df8e7fc) then B (this tree) in the same session.
# Measure each one's L-on frame2 and L-off frame2. Never read A from a JSON file.
# Δ = L-on − L-off. B/A = B frame2 / A frame2 (same run). 3/3 not best-of.
#
#   tools/eoa_render1_live_cold_guard.sh
#   EOA_RENDER1_LIVE_OUT=/tmp/eoa-render1-live tools/eoa_render1_live_cold_guard.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${EOA_RENDER1_LIVE_OUT:-/tmp/eoa-render1-live}"
mkdir -p "$OUT"
A_SHA="5df8e7fcc8c5dceb3b0429e14c87c83b116feee7"
WORKDIR="${EOA_RENDER1_A_WORKTREE:-/tmp/eoa-render1-a-5df8e7fc}"

loadavg() {
  if [[ -r /proc/loadavg ]]; then
    awk '{print $1" "$2" "$3}' /proc/loadavg
  else
    echo "?"
  fi
}

if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "WindowedRender1LiveColdGuard: RESULT=FAIL need xvfb-run" >&2
  exit 1
fi

GODOT=""
for c in \
  "${HOME}/Applications/Godot-4.7.1/Godot_v4.7.1-rc2_linux.x86_64" \
  "${HOME}/Applications/Godot-4.7.1/godot" \
  "${HOME}/Applications/godot-latest"; do
  if [[ -x "$c" ]]; then GODOT="$c"; break; fi
done
if [[ -z "$GODOT" && -x "${ROOT}/tools/run_godot.sh" ]]; then
  GODOT="${ROOT}/tools/run_godot.sh"
fi
if [[ -z "$GODOT" ]]; then
  echo "WindowedRender1LiveColdGuard: RESULT=FAIL no Godot binary" >&2
  exit 1
fi

ensure_a_worktree() {
  if [[ -d "$WORKDIR/.git" || -f "$WORKDIR/.git" ]]; then
    git -C "$WORKDIR" checkout --force "$A_SHA" >/dev/null 2>&1 || true
  else
    git fetch origin "$A_SHA" 2>/dev/null || true
    git worktree add --detach "$WORKDIR" "$A_SHA"
  fi
  mkdir -p "$WORKDIR/scripts/core" "$WORKDIR/tools" "$WORKDIR/docs/evidence/render1"
  cp -f "$ROOT/scripts/core/WindowedRender1LiveColdGuard.gd" "$WORKDIR/scripts/core/"
  if [[ -f "$ROOT/scripts/core/WindowedRender1LiveColdGuard.gd.uid" ]]; then
    cp -f "$ROOT/scripts/core/WindowedRender1LiveColdGuard.gd.uid" "$WORKDIR/scripts/core/"
  fi
  python3 - <<'PY' "$WORKDIR/scripts/map/MapRenderer.gd"
import pathlib, sys
p = pathlib.Path(sys.argv[1])
t = p.read_text()
needle = "var _supply_lon_input_t0_usec: int = 0"
if needle not in t:
    t = t.replace(
        "var _supply_toggle_in_progress: bool = false\n",
        "var _supply_toggle_in_progress: bool = false\n"
        "var _supply_lon_input_t0_usec: int = 0\n",
        1,
    )
    if needle not in t:
        t = t.replace(
            "var supply_mode: bool = false\n",
            "var supply_mode: bool = false\nvar _supply_lon_input_t0_usec: int = 0\n",
            1,
        )
old = """		if event.keycode == KEY_L:
			_toggle_supply_overlay()"""
new = """		if event.keycode == KEY_L:
			_supply_lon_input_t0_usec = Time.get_ticks_usec()
			_toggle_supply_overlay()"""
if old in t:
    t = t.replace(old, new, 1)
elif "_supply_lon_input_t0_usec = Time.get_ticks_usec()" not in t:
    t = t.replace(
        "if event.keycode == KEY_L and not event.ctrl_pressed and not event.alt_pressed:\n\t\t\t_toggle_supply_overlay()",
        "if event.keycode == KEY_L and not event.ctrl_pressed and not event.alt_pressed:\n\t\t\t_supply_lon_input_t0_usec = Time.get_ticks_usec()\n\t\t\t_toggle_supply_overlay()",
        1,
    )
if "func get_supply_lon_input_t0_usec()" not in t:
    t += (
        "\n\nfunc get_supply_lon_input_t0_usec() -> int:\n"
        "\treturn _supply_lon_input_t0_usec\n"
    )
p.write_text(t)
print("patched", p)
PY
  if [[ ! -f "$WORKDIR/.godot/global_script_class_cache.cfg" ]]; then
    echo "EOA_RENDER1_LIVE_COLD importing 5df8e7fc class cache"
    if [[ "$GODOT" == *run_godot.sh ]]; then
      for c in \
        "${HOME}/Applications/Godot-4.7.1/Godot_v4.7.1-rc2_linux.x86_64" \
        "${HOME}/Applications/Godot-4.7.1/godot" \
        "${HOME}/Applications/godot-latest"; do
        if [[ -x "$c" ]]; then
          "$c" --path "$WORKDIR" --headless --import --quit || true
          break
        fi
      done
    else
      "$GODOT" --path "$WORKDIR" --headless --import --quit || true
    fi
  fi
}

parse_boot() {
  local json="$1"
  python3 - <<PY
import json, sys
p = "$json"
d = json.load(open(p))
def f(k):
    return float(d.get(k, -1))
print("%.6f %.6f %.6f %.6f %.6f %d %d %.6f" % (
    f("lon_frame2_ms"), f("loff_frame2_ms"), f("delta_ms"),
    f("lon_frame1_ms"), f("loff_frame1_ms"),
    int(d.get("hue_teal_edge", 0)), int(d.get("hue_olive_edge", 0)),
    f("hue_teal_share"),
))
print("%.6f" % f("width_proxy"))
PY
}

run_godot_guard() {
  local path="$1"
  local extra_env="$2"
  # Do not use tools/run_godot.sh for A: it forces --path <repo-root>.
  local bin="$GODOT"
  if [[ "$path" != "$ROOT" ]]; then
    for c in \
      "${HOME}/Applications/Godot-4.7.1/Godot_v4.7.1-rc2_linux.x86_64" \
      "${HOME}/Applications/Godot-4.7.1/godot" \
      "${HOME}/Applications/godot-latest"; do
      if [[ -x "$c" ]]; then bin="$c"; break; fi
    done
  elif [[ -x "${ROOT}/tools/run_godot.sh" ]]; then
    bin="${ROOT}/tools/run_godot.sh"
  fi
  # shellcheck disable=SC2086
  env $extra_env xvfb-run -a -s "-screen 0 1280x740x24" \
    "$bin" --path "$path" --resolution 1280x740 \
    -s res://scripts/core/WindowedRender1LiveColdGuard.gd
}

echo "EOA_RENDER1_LIVE_COLD who=wrapper out=$OUT same_run_A_then_B sha_A=$A_SHA xvfb=1 runs=3 (NOT product Play)"
echo "EOA_RENDER1_LIVE_COLD loadavg=$(loadavg)"
ensure_a_worktree

fails=0
run=1
while [ "$run" -le 3 ]; do
  echo "EOA_RENDER1_LIVE_COLD who=wrapper.run=$run loadavg=$(loadavg)"
  A_OUT="$OUT/run${run}_a"
  B_OUT="$OUT/run${run}_b"
  mkdir -p "$A_OUT" "$B_OUT"
  unset EOA_RENDER1_A_FRAME2_MS EOA_RENDER1_A_FRAME2_FILE
  unset EOA_RENDER1_A_HUE_SHARE EOA_RENDER1_A_HUE_TEAL EOA_RENDER1_A_HUE_OLIVE
  unset EOA_RENDER1_A_WIDTH_PROXY

  echo "EOA_RENDER1_LIVE_COLD who=A.run=$run sha=$A_SHA"
  set +e
  EOA_RENDER1_MEASURE_A=1 EOA_RENDER1_LIVE_OUT="$A_OUT" \
    run_godot_guard "$WORKDIR" "EOA_RENDER1_MEASURE_A=1 EOA_RENDER1_LIVE_OUT=$A_OUT"
  a_rc=$?
  set -e
  if [[ $a_rc -ne 0 || ! -s "$A_OUT/live_boot.json" ]]; then
    echo "EOA_RENDER1_LIVE_COLD who=wrapper.run=$run RESULT=FAIL A boot"
    fails=$((fails + 1))
    run=$((run + 1))
    continue
  fi
  a_parsed="$(parse_boot "$A_OUT/live_boot.json")"
  a_line1="$(echo "$a_parsed" | sed -n '1p')"
  a_width="$(echo "$a_parsed" | sed -n '2p')"
  A_LON="$(echo "$a_line1" | awk '{print $1}')"
  A_LOFF="$(echo "$a_line1" | awk '{print $2}')"
  A_DELTA="$(echo "$a_line1" | awk '{print $3}')"
  A_LON1="$(echo "$a_line1" | awk '{print $4}')"
  A_LOFF1="$(echo "$a_line1" | awk '{print $5}')"
  A_TEAL="$(echo "$a_line1" | awk '{print $6}')"
  A_OLIVE="$(echo "$a_line1" | awk '{print $7}')"
  A_SHARE="$(echo "$a_line1" | awk '{print $8}')"
  echo "same_run A L-on_frame1=$A_LON1 L-on_frame2=$A_LON L-off_frame1=$A_LOFF1 L-off_frame2=$A_LOFF delta=$A_DELTA teal_share=$A_SHARE loadavg=$(loadavg)"

  echo "EOA_RENDER1_LIVE_COLD who=B.run=$run"
  set +e
  EOA_RENDER1_MEASURE_A=0 \
  EOA_RENDER1_LIVE_OUT="$B_OUT" \
  EOA_RENDER1_A_FRAME2_MS="$A_LON" \
  EOA_RENDER1_A_HUE_SHARE="$A_SHARE" \
  EOA_RENDER1_A_HUE_TEAL="$A_TEAL" \
  EOA_RENDER1_A_HUE_OLIVE="$A_OLIVE" \
  EOA_RENDER1_A_WIDTH_PROXY="$a_width" \
    run_godot_guard "$ROOT" \
      "EOA_RENDER1_MEASURE_A=0 EOA_RENDER1_LIVE_OUT=$B_OUT EOA_RENDER1_A_FRAME2_MS=$A_LON EOA_RENDER1_A_HUE_SHARE=$A_SHARE EOA_RENDER1_A_HUE_TEAL=$A_TEAL EOA_RENDER1_A_HUE_OLIVE=$A_OLIVE EOA_RENDER1_A_WIDTH_PROXY=$a_width"
  b_rc=$?
  set -e
  if [[ $b_rc -ne 0 || ! -s "$B_OUT/live_boot.json" ]]; then
    echo "EOA_RENDER1_LIVE_COLD who=wrapper.run=$run RESULT=FAIL B boot rc=$b_rc"
    fails=$((fails + 1))
    run=$((run + 1))
    continue
  fi
  b_parsed="$(parse_boot "$B_OUT/live_boot.json")"
  b_line1="$(echo "$b_parsed" | sed -n '1p')"
  B_LON="$(echo "$b_line1" | awk '{print $1}')"
  B_LOFF="$(echo "$b_line1" | awk '{print $2}')"
  B_DELTA="$(echo "$b_line1" | awk '{print $3}')"
  B_LON1="$(echo "$b_line1" | awk '{print $4}')"
  B_LOFF1="$(echo "$b_line1" | awk '{print $5}')"
  BA="$(python3 -c "a=float('$A_LON'); b=float('$B_LON'); print('%.6f' % (b/a if a>0 else 0))")"
  echo "same_run B L-on_frame1=$B_LON1 L-on_frame2=$B_LON L-off_frame1=$B_LOFF1 L-off_frame2=$B_LOFF delta=$B_DELTA"
  echo "same_run run=$run A_lon2=$A_LON A_loff2=$A_LOFF A_delta=$A_DELTA B_lon2=$B_LON B_loff2=$B_LOFF B_delta=$B_DELTA B/A=$BA loadavg=$(loadavg)"
  set +e
  python3 - <<PY
a_lon=float("$A_LON"); b_lon=float("$B_LON"); b_delta=float("$B_DELTA"); ba=float("$BA")
ok=1
if a_lon <= 0 or b_lon <= 0:
    print("same_run FAIL missing raw frame2 A=%.3f B=%.3f" % (a_lon, b_lon))
    ok=0
if b_delta > 250.0:
    print("same_run FAIL B Δ=%.3f > 250" % b_delta)
    ok=0
if ba > 0.75 or ba <= 0.0:
    print("same_run FAIL B/A=%.3f want <= 0.75 (B frame2 / A frame2)" % ba)
    ok=0
if ok:
    print("same_run PASS Δ=%.3f B/A=%.3f (A and B measured this run; not a stored file)" % (b_delta, ba))
raise SystemExit(0 if ok else 1)
PY
  cmp_rc=$?
  set -e
  if [[ $cmp_rc -ne 0 || $b_rc -ne 0 ]]; then
    echo "EOA_RENDER1_LIVE_COLD who=wrapper.run=$run RESULT=FAIL"
    fails=$((fails + 1))
  else
    echo "EOA_RENDER1_LIVE_COLD who=wrapper.run=$run RESULT=PASS"
  fi
  run=$((run + 1))
done
if [ "$fails" -gt 0 ]; then
  echo "WindowedRender1LiveColdGuard: RESULT=FAIL runs_failed=$fails/3 loadavg=$(loadavg)"
  exit 1
fi
echo "WindowedRender1LiveColdGuard: RESULT=PASS 3/3 same-run A+B loadavg=$(loadavg)"
exit 0
