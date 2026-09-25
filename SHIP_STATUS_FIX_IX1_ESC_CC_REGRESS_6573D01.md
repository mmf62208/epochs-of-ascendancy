# STATUS — FIX IX-1 Play F5 computerUse never delivers into Godot on tip `6573d01` (PR 55)

From: Ship
Assign: `/workspace/SHIP_ASSIGN_FIX_IX1_ESC_CC_REGRESS_6573D01.md`
Evidence: `/workspace/eoa-smoke-6573d01/RESULT.md` (`EOA_LIVE_RAW_PTR`=1 `title.ready` only)
Start tip: `6573d01d74ff087f8bc4ffe33f37e11ff553419b`
**New tip (GitHub `head.sha`):** *(pending commit)*
PR: https://github.com/mmf62208/epochs-of-ascendancy/pull/55 (**HOLD merge**, draft)

## State: DONE — HOLD await Play (smoke-auto-begin only)

## Honest claim
**Smoke-auto-begin hatch only.** Play-F5 computerUse delivery is **not** fixed. Product Begin / Esc / mouse CC stay **FAIL** until post-boot `EOA_LIVE_RAW_*` appears. Softpipe can proceed when Play sets the flag.

## Soft wall (confirmed delivery miss)
| Marker | Count on `6573d01` | Meaning |
|--------|--------------------|---------|
| `EOA_LIVE_RAW_PTR` | **1** | boot only `who=title.ready` (`focused=true` ds=X11) — not a click |
| `EOA_LIVE_PTR` | **0** | no hit |
| `EOA_LIVE_RAW_KEY` | **0** | Enter/Space/B never reached title |
| `EOA_LIVE_ESC` | **0** | Esc not exercised |

Begin + keys + mouse CC FAIL. Softpipe NOT RUN. **Click/keys never entered this Godot window.** Headless 5/5 PASS. CA lean computerUse remains unproven on Play's F5 TestScenario driver.

## Dig (why title.ready focused=true but zero post-boot RAW)
1. `tools/run_godot.sh` launches the same X11 Godot client Play used (`DisplayServer=X11`, TestScenario / TestRunner living title).
2. `title.ready` proving `focused=true` is **boot** — not a click. No later `title.window_input` / `title._input` / `title._process` / `TestRunner._process` RAW line means **no OS ButtonPress or Key** reached this client.
3. `DisplayServer.mouse_get_button_state()` poll would have logged `EOA_LIVE_RAW_PTR who=title._process` or `TestRunner._process` if the WM saw a left button on this display. It did not.
4. Play computerUse is driving a screenshot / compositor surface that is **not** this X11 client's event stream (offset / wrong window / no activate). Lean title + xdotool / CA computerUse on a tiny `-s` window is a different geometry and focus path.
5. Do **not** ship another CA-lean-only green tip as Play-F5 delivery PASS.

Optional Play harness change if retrying product Begin (not required for softpipe): `xdotool search --name Epochs windowactivate --sync` **before** the click. If RAW still stays at `title.ready` only, events still never entered this client.

## Shipped (smoke hatch)
- `LivingTitleBoot.smoke_auto_begin_enabled()` / `apply_smoke_auto_begin()` — **default OFF**
- Env **`EOA_SMOKE_AUTO_BEGIN=1`** or CLI `--smoke-auto-begin`
- TestRunner `_show_living_title_boot` + `_process` backup call the **real** `handle_live_begin` (clock / Search / spine arm)
- Wrapper: `tools/eoa_play_f5_smoke_auto_begin.sh`
- Headless: hatch opt-in only; default keeps title
- Logs: `EOA_SMOKE_AUTO_BEGIN who=... (NOT product Begin/Esc PASS)`

Do **not** use `EOA_SKIP_TITLE` — that skips Begin clock/Search/spine arming.

Held: sticky-open · window-stay · layers 110/120/130 · past-+6 · R2 · Search Go · spine · `EOA_LIVE_RAW_*` / `PTR` / `ESC` · mouse CC · Enter/Space/B · DisplayServer poll · taller Begin. Dig2/G PARKED. No toggle-close.

## Play must launch (softpipe)

```bash
EOA_SMOKE_AUTO_BEGIN=1 tools/run_godot.sh --path . res://scenes/TestScenario.tscn
# equivalent:
tools/eoa_play_f5_smoke_auto_begin.sh
```

Watch `godot.log` for:
```
TestRunner: EOA envs: ... SMOKE_AUTO_BEGIN=1
EOA_SMOKE_AUTO_BEGIN who=title.apply_smoke_auto_begin smoke-only dismiss (NOT product Begin/Esc PASS)
LivingTitleBoot: live Begin · GER · 1936
TestRunner: living title closed
```

Then: past+6 → Search Köln/Cologne + Go → Build Road Spine. Window stays.

**Scorecard:** product Begin / Enter/Space/B / mouse CC / Esc ×2 = **FAIL** (delivery). Softpipe gates may run after hatch. Do not redefine softpipe success as auto-begin forever.

## PARK
HOLD merge. Dig2/G PARKED. Quiet Mike beyond tip SHA / PR URL.
Scott: rebound Play to the new head with `EOA_SMOKE_AUTO_BEGIN=1`.
