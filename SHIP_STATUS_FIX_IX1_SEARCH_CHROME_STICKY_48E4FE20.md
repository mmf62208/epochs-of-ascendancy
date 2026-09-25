# STATUS — FIX IX-1 Search chrome **sticky** through TopInfoBar reflow — DONE

Updated: Fri Sep 25, 2026
From: Ship · one CA · PR 55 HOLD

## Verdict: DONE (sticky pixel Search after More+/Steel/Al reflow; smoke softpipe path)

- Start tip: `48e4fe209ddf031d587b1d3d5f944a14a4580d32` (`48e4fe20`)
- **New GitHub head.sha:** `22679ad036f553e37ad2459a52e11cbef39a2974` (`22679ad0`) — this STATUS commit will move HEAD; use `git rev-parse origin/cursor/ix1-road-spine-9d9b` after push
- Code: `22679ad036f553e37ad2459a52e11cbef39a2974`
- PR 55 HOLD: https://github.com/mmf62208/epochs-of-ascendancy/pull/55 · branch `cursor/ix1-road-spine-9d9b` · draft
- Same draft PR / same branch. No second PR. Do not merge.

## Root cause
First-paint Search on TopInfoBar right was an overlay `PRESET_TOP_RIGHT` sibling of `ContentRow`. When `_apply_responsive_layout` / `_update_resources` settled **More + / Steel: 12000 / Al**, that TOP_RIGHT slot was eaten (stale or covered rect). PIXEL heartbeat still logged `live=1` because the gate did not require `in_bar` after layout settle and did not treat resource labels as cover. Play `search_chrome_top_right.webp` PASS → `search_chrome_top_right_missing.webp` FAIL. Softpipe Köln → Go → spine **NOT RUN**.

## What changed
1. Host Search **in-flow** on TopInfoBar `RightContainer`: Resources → SearchLineEdit+Go → Menu (UILayer 110 / TopInfoBar host kept).
2. `_keep_search_chrome_sticky` re-applies after responsive layout and resource-text widen; hide extra resource chips before Search can leave the strip.
3. PIXEL: `in_bar` + Steel/Al/More cover; `sticky` / `reflow` fields. First-paint-only live=1 is insufficient.
4. TestRunner `layout_settle` sticky check after hatch + heartbeat (every beat re-checks PIXEL).

Held: stay-alive / catch-up past7 / hatch smoke-only / corridor Köln/Bonn/Leverkusen/Essen IDs / first-paint TopInfoBar host + sized LineEdit/Go. Dig2/G PARKED.

## Play launch
```bash
tools/eoa_play_f5_smoke_auto_begin.sh
```
Require live: hatch + softpipe_catchup past7 + `EOA_SMOKE_STAYALIVE` **and** pixel-visible SearchLineEdit+Go **still present after TopInfoBar More+/Steel/Al reflow** (`EOA_SMOKE_SEARCH_CHROME_PIXEL` `who=TestRunner.layout_settle` `in_bar=1` `sticky=1` `live=1`). Early PIXEL alone is FAIL if chrome vanishes before Köln.

## Honest
Smoke sticky pixel Search after TopInfoBar reflow only. Stay-alive / catch-up / first-paint host **kept**. Product Begin / Esc / mouse CC / 4x / clock **UNFIXED**. Play-F5 **UNFIXED** unless proven. Headless SearchGo PASS ≠ live softpipe proof.

## Headless (CA)
LivingTitleEscBegin · DayTick (stay-alive EXIT 0) · SearchGoInspector · MandateGate · `test_ix1_road_spine_product` 13/13 · SCRIPT ERROR **0**

## Next
Scott rebounds Play. HOLD merge. Quiet Mike.
