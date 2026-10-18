# KEEP bundle chain resolutions (2026-10-18)

Chain rebuilt so each squash-merge onto `main` `e287ef3636aca5ecc2d340f59a69e562e8dacadf` is a prefix of the next. Method: start each PR at the predecessor’s new head and `git merge --no-ff` that PR’s previous tip. Local (uncommitted) attr `docs/*.md merge=union` kept both doc sides. No leftover `<<<<<<<` markers. No design-decision stop.

## #110 `keep/pr90r-perf5-2c68a67c`

Merged `origin/main` (INPUT-1 squash #89) into `3fc176b5`.

- **docs/*.md** — union / auto-merged (`CURRENT_STATE`, `GAME_STATUS_SNAPSHOT`, `TESTING_PLAN`).
- **scripts/map/MapRenderer.gd** — ort auto-merge. INPUT-1 close-click consume (`_close_click_guard`, `_unit_card_consumed_press`, `_ui_close_click_blocks_map_pick`) kept; PERF-5 legend day pulse + overlay freshness (`_on_game_day_advanced_legend`, `_supply_roles_cache` fingerprint, `patch_items`) kept.
- **tools/eoa_full_test_gates.sh** — ort auto-merge. `launch_input1_close_click` and `launch_perf5_*` both present.

No manual hunks.

## #98 `cursor/fac1a-l2-oval-fringe-da2c`

Merged previous tip `2089a1a0` onto new #110.

- **docs/*.md** — union / auto-merged.
- **MapRenderer.gd / gates.sh** — ort auto-merge. FAC-1a oval hit + `launch_fac1a_hit_geometry` land on top of PERF-5 / INPUT-1.

No manual hunks.

## #99 `cursor/perf6-dayroll-c4e1`

Merged previous tip `3912d5aa` onto new #98.

- **docs/*.md** — union / auto-merged.
- **gates.sh** — ort auto-merge. `launch_perf6_{day_roll,starve,pace}` added; earlier launchers kept.
- **SupplyManager / TimeManager / GameData / ProductionManager** — PERF-6 slice/pace changes applied with no conflict.

No manual hunks.

## #101 `cursor/render1-supply-rings-f6eb`

Merged previous tip `b8643278` onto new #99. These are the files that conflicted on the earlier rebase-onto-#99; **chain merge produced zero leftover conflicts**.

- **scripts/map/MapRenderer.gd** — earlier PERF-5 overlay freshness + INPUT-1 consume stay; RENDER-1 idle Home-LOD prebuild / role cache / `patch_items` + mesh finish land on top (`_tick_supply_ring_idle_prebuild`, `_supply_prebuild_*`, `_finish_supply_ring_prebuild_if_needed`).
- **scripts/map/SupplyOutlineBatchLayer.gd** — PERF-5 `patch_items` kept; RENDER-1 ArrayMesh chunks / Home LOD / `begin_idle_set_items` land on top.
- **tools/eoa_full_test_gates.sh** — `launch_render1_{supply_ring_mesh,prebuild_roles,draw_guard,live_cold}` added beside `launch_perf6_*` / `launch_perf5_*`.

No manual hunks (ort combined both intents).

## #102 `cursor/oridiom1b-march-terrain-131f`

Merged previous tip `458a1cc3` onto new #101.

- **docs/*.md** — union / auto-merged.
- **FormationMovement.gd / HeadlessOrIdiom1bMarchCostTest.gd / gates.sh** — no code overlap with the ring/legend work; march-terrain cost + `launch_oridiom1b_march_cost` added.

No manual hunks.

## #100 `cursor/hwy1-highway-chains-80dc`

Merged previous tip `5283e31f` onto new #102.

- **docs/*.md** — union / auto-merged.
- **RoadTierVisual.gd / InfrastructureOverlayLayer.gd / WindowedRt1RoadTierPixelGuard.gd / HeadlessHwy1HighwayChainTest.gd / gates.sh** — HWY-1 trunk-chain product and `launch_hwy1_highway_chain` added; no leftover conflicts.

No manual hunks.

## #104 `cursor/hwy3-hub-routes-3d86`

Merged previous tip `6f0e5389` onto new #100. Earlier rebase-onto-`main` saw **modify/delete** on `HeadlessHwy1HighwayChainTest.gd` because `main` never had that file. **#104 did not delete it.** It kept the HWY-1 harness and retargeted Part B bars for hub routes:

- highway count 60–114 (2× of HWY-1’s 52) instead of ±10% of the pre-HWY-3 count
- triangle / max-degree asserts run on `select_trunk_edges` (sparsifier), not the display cache (hub routes may exceed a forest)
- new `HeadlessHwy3*` tests + `launch_hwy3_*` sit beside `launch_hwy1_highway_chain`

On this chain merge, git applied that adaptation as a normal modify; **no modify/delete, no leftover hunks**.

Approved overlap files, both intents kept by ort:

- **InfrastructureOverlayLayer.gd** — HWY-1 chain draw stays; HWY-3 hub-route overlay / L-off cache land on top.
- **RoadTierVisual.gd** — HWY-1 trunk pick stays; `_hwy3_pick_hub_routes` / `pair_hub_routes` / `build_hub_route_adj` land on top.
- **WindowedRt1RoadTierPixelGuard.gd** — HWY-1 pixel bars stay; HWY-3 Ruhr / far-width / cased-run counts land on top.
- **HeadlessHwy1HighwayChainTest.gd** — follow #104 (keep + adapt), not delete.
- **gates.sh** — `launch_hwy1_*` and `launch_hwy3_*` both present.

## #105 `cursor/wheeldrift-1-zoom-edge-583f`

Merged previous tip `41e245b7` onto new #104.

- **docs/*.md** — union / auto-merged.
- **MapRenderer.gd / gates.sh** — ort auto-merge. WHEELDRIFT-1 cursor-zoom inverses + 350 ms edge suppress + 150 ms dwell (`_arm_wheel_edge_suppress`, `_gate_wheel_edge_pan`, `_wheel_zoom_factor`) land on top of EDGE-1 / HWY / RENDER paths. `launch_wheeldrift1` added.

No manual hunks.

## #106 `cursor/edge-2-rim-feel-1169`

Merged previous tip `9cff84fc` onto new #105. Files that conflicted on the earlier rebase-onto-`main` **auto-merged here**.

- **scripts/map/MapRenderer.gd** — WHEELDRIFT-1 `_gate_wheel_edge_pan` stays; EDGE-2 250 ms rim dwell + 600 ms ramp + Home-zoom world-speed cap land on top (comment at the `_process` edge-pan site records both).
- **scripts/map/MapViewInput.gd** — EDGE-1 `EDGE_PAN_RIGHT_SCREEN_PX=10` stays; EDGE-2 dwell/ramp/left-HUD 6 px exemption land on top.
- **tools/eoa_full_test_gates.sh** — `launch_edge2_rim_feel` added beside `launch_wheeldrift1`.
- **HeadlessClose1StaleDragGuardTest.gd** — EDGE-2 re-seed of headless origin kept (keep-green vs Close-1).

No manual hunks.

## Why rebase-onto-main conflicted and this chain did not

Rebase replayed later commits onto a tree that lacked the earlier PR’s files (HWY-1 test, PERF-5 overlay APIs, WHEELDRIFT-1 edge gate). Merge-onto-predecessor had those files as the ours side, so ort could combine them with the later PR’s theirs side. Docs union did the same for `CURRENT_STATE.md` / `GAME_STATUS_SNAPSHOT.md` / `TESTING_PLAN.md`.
