# ATLAS-1 FIX #8 — deterministic Ruhr slots; no label-on-dot (PR #109)

Branch `grok/atlas1-cities-rivers`. Draft only. **Merge HOLD** until live Play.

**Parent:** `b20aa4c9` (FIX #7)

Play NOT READY on FIX #7: zoom-out Essen flipped south (remembered mid-band slot), ~1 px overlap with Duisburg; Dortmund (14,0) hid its own disc at z3.031; Düsseldorf at z1.022 covered most of Köln’s mark. Counters were off (Begin, U, Home). Cameras matched within 0.04 wu — placement, not camera.

Hard rules kept: seed `20fe9063` unedited; no `world_full` ID renumber; Godot 4.7.1 via `tools/run_godot.sh`; Prod / TopInfoBar unedited; no force-push; no `cursor/*` branch; no new PR.

---

## What changed

`CityLabelsLayer.gd`

- Ruhr compact sits are **default order only**. Dropped `_stable_off` (per-band memory reused before the defaults; last-resort `slots[0]` was the remembered south sit).
- Candidate scoring **rejects** a sit that buries its own 4 px disc or covers another Ruhr disc (`ruhr_dot_cover_names`). Dortmund walks `(12,6)` before `(14,0)`.
- Other Ruhr label AABBs are still allowed (70 px names on 13 px dots). Side-jumps (a southern city labelling north of a northern sibling’s mark) still fail.
- Duisburg prefers south/east (German) sits; west-into-NL is last.

`HeadlessAtlas1LiveRuhrTest.gd` / `HeadlessAtlas1CityLabelsTest.gd`

- Play path: Begin, **U (counters off)**, Home, wheel in and out.
- Live zooms **1.270 / 1.578 / 1.962 / 2.439 / 3.031**. 1.962 and 2.439 interpolated in **1/z** between Play cameras. Zoom-out asserts the same slots (≤3 px) and no extra overlaps.
- `ruhr_dot_cover_names` empty at every stop including z1.022.

---

## Commands (from repo root)

```bash
EOA_SLOW_BOX=1 EOA_ATLAS1_BUILD_BAR_MS=200 tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1CityLabelsTest.gd
EOA_SLOW_BOX=1 EOA_ATLAS1_BUILD_BAR_MS=200 tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAtlas1RiversTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHwy3HubRouteTest.gd
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessHwy3LiveScenarioTest.gd
EOA_ATLAS1_EVIDENCE=docs/evidence/atlas1-fix8 tools/eoa_atlas1_live_ruhr.sh
EOA_ATLAS1_PIXEL_OUT=/tmp/eoa-atlas1-pixel tools/eoa_atlas1_pixel_guard.sh
EOA_HWY3_RUHR_OUT=/tmp/eoa-hwy3-ruhr tools/eoa_hwy3_ruhr_legibility_guard.sh
tools/eoa_full_test_gates.sh --quick
```

Gate results land in the follow-up evidence commit after the run.

---

## Merge HOLD

Headless + xvfb, **not** live Play.
