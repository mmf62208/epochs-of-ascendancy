# SHIP STATUS — FIX2 scope change: units on top + view-only U (PR 57)

**HOLD for Play. Do not merge. Same draft PR 57.**

| | |
|--|--|
| **PR** | https://github.com/mmf62208/epochs-of-ascendancy/pull/57 (draft) |
| **Branch** | `cursor/rx1-rhine-crossing-e117` |
| **Starting tip** | `911dd0cac33a5555b3bb857ee48e6d8136451410` |
| **Play MIXED base** | `816cdc921c8072928d24a90a71a0d4088e9cde05` |
| **Implementation** | `88de600c` (units on top + U + HUD) + `2932180c` (gold spine paint) |
| **Pixel floors** | `c46ac26e` (gold 0.15) + `8a13a394` (river 0.28) |
| **HEAD** | `6b6576fd7dc08f6b7cb953f8599e11858192902f` |

## Scope change

1. **Units stay on top.** Undo FIX1 raise. Labels 18 < roads 21 < Rhine 22 < DemoUnitIcon 28. Keep theater-scale 1.728, screen-space widths, close-zoom label hide, Köln built state, leak scoping.
2. **View-only Units toggle.** HUD `BtnUnitsView` + plain **U**. Default shown. Does not touch sim / selection / orders / save. Search focus swallows U. **Shift+U** = supply/sealane flow.
3. **Pixel guard.** Units OFF river + gold spine FAIL on `816cdc9` / PASS on tip. Units ON: counters win. U hide/restore. 816cdc9 hides unit nodes directly.

## Guard table (real xvfb)

| Check | `816cdc9` (direct hide) | tip `8a13a394` |
|-------|-------------------------|----------------|
| mid river OFF (≥0.28) | **0.230 FAIL** | **1.000 PASS** |
| close river OFF | **0.172 FAIL** | **0.977 PASS** |
| gold spine OFF (≥0.15) | **0.000 FAIL** | **0.192 PASS** |
| units ON counter wins | **1.000 PASS** (already over Rhine) | **1.000 PASS** |
| U hide/restore + sim | **FAIL** (no toggle) | **PASS** |
| Köln re-offer / built | **true / false FAIL** | **false / true PASS** |
| `WindowedRx1RhinePixelGuard` | **RESULT=FAIL** | **RESULT=PASS** |

816cdc9 hide: `_hide_unit_nodes_direct` walks `DemoUnitIcon_*` / `StackBadge` / `PinFocusPulse` / `LandBattleBubbleLayer` / `SelectedFrame`. `direct_hide=true`.

Gold matcher rejects tan land and old tan road (128, 92, 36). 816cdc9 road **0.000** — tan false-pass is gone.

## Other gates (tip)

| Guard | Result |
|-------|--------|
| `HeadlessRx1RhineVisibilityTest` | **RESULT=PASS** |
| `HeadlessRx1RhinePanelStateTest` | **RESULT=PASS** |
| `HeadlessRx1RhineCrossingTest` | **RESULT=PASS** |
| `HeadlessRx1RhineLiveStayAliveTickTest` | **RESULT=PASS** |
| `HeadlessIx1SearchGoInspectorTest` | **RESULT=PASS** |
| `test_rx1_rhine_crossing_product` | **9/9** |
| `test_ix1_road_spine_product` | **15/15** |

## Known gaps

- Captures still read as a wide theater view when MapCamera reports Köln at zoom 2.10. Samples use canvas transforms + local course.
- Gold tip hit 0.192 is a thin gold-over-GER composite (honest).
- Köln bridge-leak was **false** on this 816cdc9 run; re-offer / missing-built still fail.

PNGs: `/tmp/eoa-rx1-pixel-816cdc9-final/`, `/tmp/eoa-rx1-pixel-tip-final/`, `/opt/cursor/artifacts/rx1-pixel/`.
