# FIRST20-P2 evidence (F6 start-zoom LOD + F7 mapmode strip)

Stills under this folder are **layout contracts**, not live F5 Play captures.

| File | What it shows |
|------|----------------|
| `before_start_zoom.png` / `after_start_zoom.png` | z&lt;0.6: full cards covering GER land vs 22×16 stack chips + “Germany” unobstructed |
| `before_mapmode_*.png` / `after_mapmode_*.png` | Each mapmode chip: stuck F2 + Ix/S/M/H/X overflow vs toggle + Intensity + More ▾ + CYAN active fill |
| `after_toolbar_live.png` | Optional headless viewport grab from `HeadlessFirst20P2Test` |

Regenerate the annotated stills:

```bash
python3 tools/map_generation/scripts/render_first20_p2_evidence.py
```

Headless contract:

```bash
XDG_DATA_HOME=$(mktemp -d) tools/run_godot.sh --headless --path . \
  --resolution 1280x800 -s res://scripts/core/HeadlessFirst20P2Test.gd
```
