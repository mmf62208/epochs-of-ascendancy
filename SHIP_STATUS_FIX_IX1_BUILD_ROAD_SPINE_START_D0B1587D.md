# STATUS — FIX IX-1 Build Road Spine **start** at Mandate 0 — DONE tip `99635f8d`

Updated: Fri Sep 25, 2026 ~2:50pm ET
From: Ship · CA `bc-69b9277b-d508-5805-bec9-5ecbad90a9f9`

## Verdict: DONE (live press arms start at Mandate 0; smoke softpipe path)

- Start tip: `d0b1587d4b5888bbc556287e16ead2491eefa564` (`d0b1587d`)
- Code commit: `01253362ad3f455e34b62c561e56b7c1e8298bdf` (`01253362`)
- **GitHub head.sha:** `99635f8dcc8e61cca38ab2e7daf4dd25929a1225` (`99635f8d`)
- PR 55 HOLD: https://github.com/mmf62208/epochs-of-ascendancy/pull/55 · branch `cursor/ix1-road-spine-9d9b` · draft
- CA: https://cursor.com/agents/bc-69b9277b-d508-5805-bec9-5ecbad90a9f9

## Root cause
Play MIXED `d0b1587d`: Köln inspector + Build Road Spine **visible**, repeated clicks no toast/progress/state.

1. Leftover map `_input` swallowed inspector button-up (Search Go already opted out via `_search_ui_owns_click`; spine did not).
2. `try_start_road_spine` still called generic Invest `can_start_project` (Köln 73 Mandate / capacity). Visible Mandate-0 CTA could no-op. MandateGate previously passed on “not Insufficient Mandate” even when start failed for other Invest reasons.

## What changed
1. `_road_spine_btn_owns_click` + `_input` / unhandled / chip-open yield (same class as Search).
2. Press-on-down (`ACTION_MODE_BUTTON_PRESS` + `button_down` + `gui_input`).
3. `start_road_spine_project` — IX-1 first-session grant; **does not** call `can_start_project`.
4. Press always toasts (no silent `selected_province_id < 0` return); resolves inspector pid.
5. Live/smoke gate `EOA_SMOKE_SPINE_START` + `press_build_road_spine_from_live_ui` — visible chrome that never arms after press is FAIL.

Sticky Search / stay-alive / catch-up / hatch / corridor IDs **kept**. Dig2/G PARKED.

## Play launch
```bash
tools/eoa_play_f5_smoke_auto_begin.sh
```
Require live: hatch + softpipe_catchup past7 + `EOA_SMOKE_STAYALIVE` + sticky Search + Köln inspector + **Build Road Spine starts** (toast/progress/state) then complete → RoadLayer Bonn–Köln–Leverkusen → Essen. Prefer `EOA_SMOKE_SPINE_START visible=1 armed=1`. Visible button alone is FAIL if start never arms.

## Honest
Smoke softpipe: Build Road Spine **starts** at Mandate 0 on live press. Sticky Search / stay-alive / catch-up kept. Play-F5 delivery **UNFIXED**. Product Begin / Esc / mouse CC / 4x / clock stay **FAIL**. Headless SearchGo / MandateGate PASS ≠ live softpipe proof — Play must confirm toast/progress after press.

## Headless (CA)
LivingTitleEscBegin · DayTick (stay-alive EXIT 0, past7 catchup) · SearchGoInspector · MandateGate · `test_ix1_road_spine_product` **14/14** · SCRIPT ERROR **0**

## Next
Scott rebound Play on the GitHub head after this STATUS. Ship HOLD await Play RESULT. No second CA. Dig2/G PARKED. Quiet Mike.
