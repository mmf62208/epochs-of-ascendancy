# STATUS — FIX IX-1 live spine press hang (toast trim `queue_free` spin) — start tip `c7f24242`

Updated: Fri Sep 25, 2026
From: Ship · CA (this run)
PR 55 HOLD: https://github.com/mmf62208/epochs-of-ascendancy/pull/55 · branch `cursor/ix1-road-spine-9d9b` · draft

## Verdict: machine FIX of the live Play-launch hang (not product F5)

Start tip: `c7f24242a1f7952216c5c510b281f7bde561d507`
Instrumentation (no toast fix): `328a83845090adf44ce53e92635b9869a71eacc1`
**GitHub head.sha:** filled after this STATUS commit is pushed.

## Spinning call

`LeaderEventUI._trim_live_f5_toast_stack` · `scripts/ui/LeaderEventUI.gd` **line 316 on `328a838`**:

```
while _toast_container.get_child_count() > 2:
    _dismiss_toast(_toast_container.get_child(0))
```

`_dismiss_toast` only `queue_free()` (line 470–472 on that commit). `get_child_count()` does not drop until end of frame, so the loop spun forever on child 0 and allocated ~140 MB/s. Same pattern in `show_toast` / `_show_toast` (`> 4`).

Reached from `_show_inspector_toast` → `show_toast` immediately after `MapRenderer.button`, once Search + `post_news` toasts had already filled the stack.

## FAIL-on-old (`328a838`, no toast fix)

Play launch = `tools/eoa_play_f5_smoke_auto_begin.sh` + viewport `InputEventMouseButton` (not the spine helper/API). Two Play boots were enough; did not spend a third.

| Evidence | Result |
|----------|--------|
| Isolated xvfb toast probe | Last line `EOA_SMOKE_SPINE_BISECT who=LeaderEventUI._trim_live_f5_toast_stack.iter0 n=3` — never `exit` / never `TOAST_PROBE done` |
| Play-launch after `.godot` import (`/tmp/eoa-ix1-fail-old/rss.log`) | RSS **1311 MB** plateau → climb to **15365 MB** (17:11–17:19) |
| Original Play (assignment) | Last line `EOA_SMOKE_SPINE_PROGRESS who=MapRenderer.button`; RSS **2.0 → 12.7 GB** in ~86 s; no frames / no toast |

## Fix

- Snapshot excess toast children; `remove_child` then `queue_free`.
- `_dismiss_toast` is idempotent (`eoa_toast_dismissing` meta; skip already-dismissing; no second tween).
- Bisect prints stay but are cheap behind `EOA_SMOKE_FRAME_GUARD=1` / `EOA_SMOKE_SPINE_BISECT=1`.
- `OrderCommandPanel._clear_container_children` already `remove_child` + `free()` — left alone. No other `while get_child_count()` + `queue_free` loops in project GDScript.

## PASS-on-new (same Play launch + same guard)

```
tools/eoa_ix1_spine_frame_guard.sh
# → tools/eoa_play_f5_smoke_auto_begin.sh + viewport mouse on Build Road Spine
```

| Gate | Result |
|------|--------|
| Isolated xvfb toast probe | `TOAST_PROBE done n=2` (after=0 n=1; after=1 n=2; after=2+ n=2; EXIT 0) |
| Play-launch frame guard | **PASS** · `EOA_SMOKE_FRAME_GUARD frames=324 rss_mb=0 PASS` · sidecar **PRESS 2016 MB → 2017 MB flat 60 s** · sidecar_max **2107 MB** (< 3072) |
| Visible after press | `toast_n=2 building=Building… toast_ok=1 building_ok=1` · Building… still on the button at 60 s |
| Trim after press | `enter n=3` → `iter0 n=3` → **`exit n=2 iters=1`** (returns; does not spin) |
| Mouse path | `TestRunner.mouse_press_returned ok=true reason=viewport_mouse` |
| `test_ix1_road_spine_product` | **15/15 OK** |
| Headless IX-1 5/5 | Mandate / DayTick / SearchGo / LivingTitle / CompleteTest **PASS** · SCRIPT_ERROR **0** · states `queued → construction → built` days=36 |

In-process `rss_mb=0` is FileAccess on `/proc` (Godot cannot read it here). Sidecar awk on the Godot pid is the RSS number: **2016–2107 MB**.

## Out of scope (unchanged)

Product Begin / Esc / mouse CC / 4x / clock stay **FAIL**. Play-F5 stays **UNFIXED**. Road effects stay proposal-only. The smoke harness is **not** the product.

## Play launch

```bash
tools/eoa_play_f5_smoke_auto_begin.sh
```

PR 55 stays draft **HOLD**. No merge. No second PR.
