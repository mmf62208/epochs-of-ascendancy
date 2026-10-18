# PERF-5 live recipe — cheap L-on legend day tick + fresh supply overlay

Window **1280×740**. `tools/run_godot.sh --path . res://scenes/TestScenario.tscn`.
Begin → **Germany** → **1936** → **Home**. Headless / xvfb ≠ live Play.
Do **not** click provinces between an overlay trigger and the readout (a select
recomputes roles on main and hides the stale-ring bug).

Pre-step (once per machine): `timeout 1500 tools/run_godot.sh --headless --path . --import --quit`.

## Run 1 — legend (L on vs off)

1. Begin GER 1936. Home. Clock **1x**, then **4x**.
2. Tip only: `EOA_LEGEND_PROFILE=1`. Main “before” numbers are the brief §3 table
   (code on main is identical to the #88 map renderer).
3. **L on.** 10 days with the mouse **off** the window, then 10 days hovering a
   GER province. Then **L off:** 5 days. Repeat at **z0.889**.
4. Bars: listener p95 ≤ **100 ms** mouse-off and ≤ **150 ms** mouse-over;
   L-on day-frame minus L-off ≤ **100 ms**; L-off day-frame no worse than main +5 %.
5. By eye: the legend **border pulse** still flashes on day change and the date
   footer rolls. Closing L and reopening must not re-walk roles when nothing changed.

## Run 2 — overlay freshness (local trigger hook, never commit)

There is no UI path for a depot or a capture. A **local, never-committed**
`MapRenderer._process` poll of `user://perf5_trigger.txt` may run one command
then delete the file:

- `SupplyManager.set_player_depot(710301,true)`
- `MapManager.update_province_owner(710160,<owner>,"FRA",true,false)`
- ten captures `710161–710169` + `710172`
- `GameData.apply_peace_conference_settlement_live("FRA","GER",710171,true,false,0.0,false)`
- `set_player_depot(710301,false)`

After each command print `PERF5_SUP routes=<n> drawn=<n> roles=<n> pid=<p> role=<r> batch_n=<n>`.
Toggle L off/on and print again. Paused and unpaused. Screenshot rings at z0.889.

Expect: `drawn` = `routes`; new depot has a ring; captured / annexed pids lose
their route ring; L off → on shows the same state.

**Revert the hook before committing.**

## Run 3 — PERF-3 regression

L on/off ×3 at Home and at z0.889. Must stay in line with #87 (Home on 212/171 ms,
off 264/268 ms; z0.889 on ≤ ~700 ms). Second L-on must **not** recompute roles.

## Run 4 — keep-green glance

Quick #83–#87 re-confirm (stars, L batch visibility, wheel burst). 0 SCRIPT /
Parse errors. Note RSS peak.

## Must not change

SupplyManager / supply sim, seed-193601 infra picks (JAP 903951 / FRA 710739 /
ITA 710859 / ENG 711481 / POL 711054 / SOV none / JAP 902474), #89 MapRenderer
regions (`_process` first 10 lines, `_input` / `_unhandled_input`, title swallow),
FacilityIconLayer, labels/LOD, TipDismiss, ORDERS, camera/edge-pan.
