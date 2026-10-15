#!/usr/bin/env bash
# Measure 5df8e7fc live-boot frame2 + ring-edge hue with the same KEY_L protocol.
# Writes docs/evidence/render1/a_live_5df8e7fc.json (no default A_FRAME2_MS).
#
#   tools/eoa_render1_measure_a.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${EOA_RENDER1_A_FRAME2_FILE:-$ROOT/docs/evidence/render1/a_live_5df8e7fc.json}"
WORKDIR="${EOA_RENDER1_A_WORKTREE:-/tmp/eoa-render1-a-5df8e7fc}"
mkdir -p "$(dirname "$OUT")"
if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "WindowedRender1LiveColdGuard: RESULT=FAIL need xvfb-run to measure A" >&2
  exit 1
fi
if [[ -d "$WORKDIR" ]]; then
  git -C "$WORKDIR" checkout --force 5df8e7fc >/dev/null 2>&1 || true
else
  git fetch origin 5df8e7fcc8c5dceb3b0429e14c87c83b116feee7 2>/dev/null || true
  git worktree add --detach "$WORKDIR" 5df8e7fcc8c5dceb3b0429e14c87c83b116feee7
fi
mkdir -p "$WORKDIR/scripts/core" "$WORKDIR/tools" "$WORKDIR/docs/evidence/render1"
cp -f "$ROOT/scripts/core/WindowedRender1LiveColdGuard.gd" "$WORKDIR/scripts/core/"
if [[ -f "$ROOT/scripts/core/WindowedRender1LiveColdGuard.gd.uid" ]]; then
  cp -f "$ROOT/scripts/core/WindowedRender1LiveColdGuard.gd.uid" "$WORKDIR/scripts/core/"
fi
# Stamp KEY_L t0 the same way B does, then expose the getter.
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
    if "var _supply_lon_input_t0_usec: int = 0" not in t:
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
echo "EOA_RENDER1_MEASURE_A who=5df8e7fc out=$OUT"
cd "$WORKDIR"
EOA_RENDER1_MEASURE_A=1 \
EOA_RENDER1_A_FRAME2_FILE="$OUT" \
EOA_RENDER1_LIVE_OUT="$(dirname "$OUT")" \
xvfb-run -a -s "-screen 0 1280x740x24" \
  "$ROOT/tools/run_godot.sh" --path "$WORKDIR" --resolution 1280x740 \
  -s res://scripts/core/WindowedRender1LiveColdGuard.gd
echo "EOA_RENDER1_MEASURE_A wrote $OUT"
test -s "$OUT"
python3 - <<PY
import json
p="$OUT"
d=json.load(open(p))
print("A lon_frame2_ms=%.3f loff_frame2_ms=%.3f delta=%.3f teal_share=%.4f teal_edge=%s width_proxy=%.3f" % (
    float(d.get("lon_frame2_ms",-1)), float(d.get("loff_frame2_ms",-1)),
    float(d.get("delta_ms",-1)), float(d.get("hue_teal_share",-1)),
    d.get("hue_teal_edge"), float(d.get("width_proxy",-1))))
PY
