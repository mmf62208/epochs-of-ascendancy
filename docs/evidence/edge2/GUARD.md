# EDGE-2 guard

```bash
tools/run_godot.sh --headless --path . --resolution 1280x740 \
  -s res://scripts/core/HeadlessEdge2RimFeelTest.gd
tools/eoa_edge2_guard.sh
```

Headless ≠ live Play. Never `EOA_SKIP_TITLE`.
