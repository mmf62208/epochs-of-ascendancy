# STATUS — FIX IX-1 Search chrome **pixel-visible** after stay-alive — DONE

Updated: Fri Sep 25, 2026 ~1:56pm UTC
From: Ship · CA `bc-61c194e8-deaf-5975-be50-48938d025710`

## Verdict: DONE (pixel-visible Search after stay-alive; smoke softpipe path)

- Start tip: `c82233c8b9fa41b2ddc96cba0c913bd58845961d` (`c82233c8`)
- **GitHub head.sha:** `ce194fd8f448605ea02cb7fa56779290da4aaea6` (`ce194fd8`) — this STATUS commit will move HEAD; use `git rev-parse origin/cursor/ix1-road-spine-9d9b` after push
- Code: `230cafd70a8c9af299979712371c198b21436ccc` (`230cafd7`)
- PR 55 HOLD: https://github.com/mmf62208/epochs-of-ascendancy/pull/55 · branch `cursor/ix1-road-spine-9d9b` · draft
- CA: https://cursor.com/agents/bc-61c194e8-deaf-5975-be50-48938d025710

## Corrected Play evidence (used)
- RESULT.md MIXED on `c82233c8` — hatch / catch-up past7 / stay-alive PASS; Search **pixels FAIL**
- `search_chrome.webp` full window — TopInfoBar + Map Mode + map; **no** LineEdit/Go
- `search_chrome_top_left.webp` crop — **Map Mode wall + NEXT banner**, no LineEdit/Go
- `clock_past7.webp` — on-screen past 7 Jan (harness-only)
- markers: `EOA_SMOKE_SEARCH_CHROME … live=1` after_hatch + heartbeat (log-only; not pixels)
- Prior STATUS `c82233c8`: UILayer 110 + TOP_LEFT + 180×28 — log PASS, pixels FAIL

## Root cause
`live=1` was flag-only (Control.visible / focus_mode / min-size). Search was a child of a **0-size CanvasLayer** so drawn height collapsed, and the field sat under the expanded Map Mode wall (matches top-left crop). Stay-alive pause was **not** the root (process_mode ALWAYS; sim pause only).

## What changed
1. Host `MapProvinceSearch` on **TopInfoBar** (UILayer 110 Control with real size) — never a CanvasLayer parent.
2. Pin **TOP_RIGHT of the 52px TopInfoBar strip** so Map Mode (layer 20) and NEXT cannot bury it.
3. Force LineEdit **180×28** + Go **48×28** actual size (not min-size only).
4. `search_chrome_pixel_report` / `EOA_SMOKE_SEARCH_CHROME_PIXEL` fail `live=0` when drawn rect is zero-area, off-screen, or covered.

Hatch, catch-up, stay-alive, corridor Köln/Bonn/Leverkusen/Essen IDs **kept**. Dig2/G PARKED.

## Play launch
```bash
tools/eoa_play_f5_smoke_auto_begin.sh
```
Require live: hatch + softpipe_catchup past7 + `EOA_SMOKE_STAYALIVE` **and** pixel-visible SearchLineEdit+Go on the **TopInfoBar right strip** (`EOA_SMOKE_SEARCH_CHROME_PIXEL` on_screen=1 live=1). Log `live=1` alone is FAIL. Look at the bar (Steel/Al side), not under the Map Mode wall.

## Honest
Smoke Search chrome **pixel-visible** after stay-alive only. Play-F5 delivery **UNFIXED**. Product Begin / Esc / mouse CC / 4x / clock stay **FAIL**. Headless SearchGo PASS is **not** live softpipe proof.

## Headless (CA)
- `test_ix1_road_spine_product` 13/13 OK
- LivingTitleEscBegin PASS · DayTick PASS (catch-up + stay-alive EXIT 0) · SearchGo PASS · MandateGate PASS
- SCRIPT ERROR **0**

## Next
Scott rebounds Play on branch `cursor/ix1-road-spine-9d9b` HEAD. Ship HOLD. No second CA. Dig2/G PARKED. Quiet Mike.
