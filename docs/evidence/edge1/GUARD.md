# EDGE-1 guard

```bash
tools/run_godot.sh --headless --path . --resolution 1280x740 \
  -s res://scripts/core/HeadlessEdge1CameraFeelTest.gd
tools/eoa_edge1_guard.sh
```

Headless + xvfb. **NOT live Play.** Never `EOA_SKIP_TITLE`.

Asserts 1280×740 helper + camera apply:

- left (3, 370) west
- right **(1270, 370)** and (1279, 370) east
- top under TopInfoBar (640, 1) north
- bottom (640, 737) south
- top-right corner **(1270, 1)** northeast
- same normalized step on every rim
- toast hover still blocks; UI-1 rest (97, 731) still no pan
- Close-held north-strip suppress still zeros edge pan
- Home / TipDismiss / ORDERS dock source needles
- large-drag south jump not reproduced (activate reseeds last_mouse)
