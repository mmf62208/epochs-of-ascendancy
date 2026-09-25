# STATUS — FIX IX-1 live clock / softpipe regression on `36485b9` (PR 55)

**HOLD merge.** Draft PR 55. Do not merge.

- Branch: `cursor/ix1-road-spine-9d9b`
- Start SHA: `36485b99ffa18175fb7ee37b78614af94251900c`
- PR: https://github.com/mmf62208/epochs-of-ascendancy/pull/55

## Cause (Play FAIL `36485b9`)

Parent `5732d34` had live past +6 PASS + Search Go PASS. Spine-pin CA on `36485b9` kept Search Go + Build Road Spine chrome, but live Begin GER 1936 wedged at **1 Jan 1936 00:00** (~272% CPU; speed/pause/Space no advance). Pale map residual. Search / spine / RoadLayer / Essen **NOT RUN**. SCRIPT_ERROR 0. Headless SearchGo (spine pin) + Mandate 0 + day-tick **PASS**.

Headless day-tick papered over the live path: `is_live_f5_play_path()` deferred to `is_interactive_light_sim()` (equiv-flag only in `-s` harness); MapRenderer day_emit / feature rings were light-sim-only; `simulate_live_f5_day_advance` called `advance_days` and never TopInfoBar `advance_real_time`; leftover Search focus after Begin swallowed Space.

## Fix

1. Windowed DisplayServer (X11 / softpipe / Vulkan) **is** live F5 — do not require `is_interactive_light_sim()`.
2. MapRenderer day_emit + feature-ring walk gate on `is_live_f5_play_path` (skip 3520 fills / rings / route-risk on Play).
3. `_reveal_ix1_road_spine_on_inspector` re-entrancy — no second `_layout_info_panel_inner` (softpipe resize-storm suspect). Search+Go chrome pin **kept**.
4. Begin releases Search focus; TopInfoBar `_input` Space (empty Search) + 00:00 watchdog force one hour.
5. Live-equiv gate now drives `advance_live_f5_equivalent_hours` (`advance_real_time`) and requires `past_hour_plus6` **and** `past_plus6`.

Search Go wiring from `5732d34` and Build Road Spine CTA pin from `36485b9` **kept**. Corridor IDs unchanged. Dig2/G PARKED.

## Gates

- `test_ix1_road_spine_product` including `search_go_spine_visible` + strengthened `day_tick_unblocked`
- `HeadlessIx1SearchGoInspectorTest` (spine pin still visible/startable)
- `HeadlessIx1RoadSpineMandateGateTest` cost=0
- `HeadlessIx1RoadSpineDayTickTest` hours past +6 + days past +6

## HOLD

Do not merge until Scott/Play rebounds: past +6 → Search→spine visible+start → complete → RoadLayer → Essen.
