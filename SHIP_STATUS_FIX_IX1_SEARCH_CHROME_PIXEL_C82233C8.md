# STATUS — FIX IX-1 Search chrome **pixel-visible** after stay-alive — DONE tip `cf28e86b`

Updated: Fri Sep 25, 2026 ~1:56pm UTC
From: Ship · CA `bc-61c194e8-deaf-5975-be50-48938d025710`

## Verdict: DONE (pixel-visible Search after stay-alive; smoke softpipe path)

- Start tip: `c82233c8b9fa41b2ddc96cba0c913bd58845961d` (`c82233c8`)
- **New tip (GitHub head.sha):** `cf28e86be8e69979ec2fb2857f38b668fd709672` (`cf28e86b`)
- Code commit: `230cafd70a8c9af299979712371c198b21436ccc` (`230cafd7`)
- PR 55 HOLD: https://github.com/mmf62208/epochs-of-ascendancy/pull/55 · branch `cursor/ix1-road-spine-9d9b` · draft
- CA: https://cursor.com/agents/bc-61c194e8-deaf-5975-be50-48938d025710

## Root cause
Play MIXED on `c82233c8`: harness `EOA_SMOKE_SEARCH_CHROME` logged `visible=1 focusable=1 live=1` but screenshots had **no** LineEdit/Go. `live=1` was flag-only (Control.visible / focus_mode / min-size). Search was a child of a **0-size CanvasLayer** so drawn height collapsed, and the field sat under the expanded Map Mode wall. Stay-alive pause was **not** the root (confirmed: process_mode ALWAYS; sim pause only).

## What changed
1. Host `MapProvinceSearch` on **TopInfoBar** (UILayer 110 Control with real size) — never a CanvasLayer parent.
2. Pin **TOP_RIGHT of the 52px TopInfoBar strip** so Map Mode (layer 20) and NEXT cannot bury it.
3. Force LineEdit **180×28** + Go **48×28** actual size (not min-size only).
4. `search_chrome_pixel_report` / `EOA_SMOKE_SEARCH_CHROME_PIXEL` fail `live=0` when drawn rect is zero-area, off-screen, or covered.

Hatch, catch-up, stay-alive, corridor Köln/Bonn/Leverkusen/Essen IDs, prior UILayer 110 intent **kept**. Dig2/G PARKED.

## Play launch
```bash
tools/eoa_play_f5_smoke_auto_begin.sh
```
Require live: hatch + softpipe_catchup past7 + `EOA_SMOKE_STAYALIVE` **and** pixel-visible SearchLineEdit+Go (`EOA_SMOKE_SEARCH_CHROME_PIXEL` on_screen=1 live=1). Log flags alone are not enough so Play can Search Köln → Go → spine → RoadLayer → Essen.

## Honest
Smoke Search chrome **pixel-visible** after stay-alive only. Play-F5 delivery **UNFIXED**. Product Begin / Esc / mouse CC / 4x / clock stay **FAIL**. Hatch/advance/stay-alive/Search-chrome ≠ product PASS. Do not regress stay-alive/catch-up. Headless SearchGo PASS is **not** live softpipe proof — Play must confirm pixels.

## Headless (CA)
- `test_ix1_road_spine_product` 13/13 OK
- LivingTitleEscBegin PASS · DayTick PASS (catch-up + stay-alive EXIT 0) · SearchGo PASS · MandateGate PASS
- SCRIPT ERROR **0**

## Next
Scott rebounds Play on tip `cf28e86be8e69979ec2fb2857f38b668fd709672`. Ship HOLD await Play RESULT. No second CA. Dig2/G PARKED. Quiet Mike.
