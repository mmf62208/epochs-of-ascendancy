# STATUS — FIX IX-1 Build Road Spine visible after Search+Go (PR 55)

**HOLD merge.** Draft PR 55. Do not merge.

- Branch: `cursor/ix1-road-spine-9d9b`
- Start SHA: `5732d3400c364b20694d0618787b6250ca537d3d`
- New head: `67731cfc4acde7123481e54a60d5fda2d731b503`
- PR: https://github.com/mmf62208/epochs-of-ascendancy/pull/55

## Cause (Play MIXED `5732d34`)

Live Search LineEdit + Go **held** (Köln `710417` panel opens; not Garrison; not silent). Esc→CC / Begin GER 1936 / past +6 / headless SearchGo + Mandate 0 + day-tick **held**.

Residual: Köln chrome after Cologne+Go showed **facility Build rows only** (Settle Köln, Heavy Water, Kiel Canal, Airfield, Light Factory…). **Build Road Spine was absent** — it lived at the end of `InfoContent` under modifiers / construction list, and adding special-site rows scrolled that list into view. Headless spine complete ≠ live button present.

## Fix

1. Pin `BtnBuildRoadSpine` to InfoPanel chrome next to Settle (not buried in scroll).
2. After Search+Go / Alt-infra / inspector open, `_reveal_ix1_road_spine_on_inspector` shows+enables the CTA, resets scroll, raises z80.
3. Prepend `Ix1SpineBuildRow` / `BtnBuildRoadSpineInList` as the first facility Build row Play actually sees.
4. IDM `should_show_road_spine_button` no longer hides the CTA when MapManager cache misses the Province.
5. New live-facing gate `search_go_spine_visible` + HeadlessIx1SearchGoInspectorTest asserts visible/startable after Search+Go.

Corridor unchanged: Köln `710417` → Bonn `710416` + Leverkusen `710418`; Essen `710403` off-spine. Dig2/G PARKED.

## Gates (this SHA)

- `test_ix1_road_spine_product` **13/13** including `search_go_spine_visible`
- `HeadlessIx1SearchGoInspectorTest` **RESULT=PASS** (Go+Enter inspector + spine chrome/list + IDM should_show Köln / not Essen / Mandate 0)
- `HeadlessIx1RoadSpineMandateGateTest` **PASS (failures=0)** cost=0
- `HeadlessIx1RoadSpineDayTickTest` **RESULT=PASS** (+12d 17.0%→50.6%; complete; live-F5-equiv +8d past+6 consider=0 pick=0 autosave=0)
- Official `--quick` `living_unit_order_loop` wiring FAIL + Pillow `map_qc` are **pre-existing** (not this FIX)
