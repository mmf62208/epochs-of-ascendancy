# CL1-S3-POL-1 — CampaignLoop1 S3 stall at POL progress 0.4460

Diagnosis only. No product change. Base `0e50ea39d4fd9657c8fff3513e9c12b44bfcfc80` (main after #220). Measuring test `scripts/core/HeadlessCl1S3Pol1Test.gd`. `RESULT=PASS` means the variants finished and printed the table. It does not require the stall to be gone.

This is not the earlier CL1 S1 siege-holder livelock. Do not start B2-SCOPE-1. Any fix needs its own OP GO, with a before/after on the identity / twin / trace pins and the d180 bands.

## 1. Repro

Official soak `scripts/core/HeadlessCampaignLoop1SoakTest.gd` via `tools/eoa_campaign_loop1_soak.sh` (timeout 900, `tools/run_godot.sh`, isolated XDG `/tmp/eoa-cl1s3-xdg-uy6Ge7`). Log `/tmp/cl1-s3-pol-1-soak.log`. Exit 1. 0 SCRIPT ERROR.

| Case | Result | Notes |
|------|--------|-------|
| S4 | PASS | time-limit Defeat: Eclipsed (rank 3) 1936-01-31 |
| M8 | PASS | no victory while at war with FRA; victory after the major war ends |
| S2 | PASS | defeat day 139 |
| S2b | PASS | defeat day 139; determinism md5 `b9cf8d506235342ff4693617a4d18b07` |
| S1 | PASS | POL annexed by GER day 156, stationed=16, progress=0.0000 |
| S3 | **FAIL** | `S3 UNKNOWN POL progress 0.4460 after 152 days (real battles stalled)` |

Exact FAIL:

```
SOAK S3 day=113 progress=0.4460 owned=31
SOAK S3 day=120 progress=0.4460 owned=31
SOAK S3 day=140 progress=0.4460 owned=31
SOAK S3 days=152 wall_ms=19191 ms_per_day=126.3 stationed=16 progress=0.4460
  [FAIL] HeadlessCampaignLoop1SoakTest: S3 UNKNOWN POL progress 0.4460 after 152 days (real battles stalled)
HeadlessCampaignLoop1SoakTest: FAIL (failures=1)
HeadlessCampaignLoop1SoakTest: RESULT=FAIL
```

S2 / S2b / S1 all print `day=108 progress=0.4460 owned=31` and continue. S3 hits `0.4460 owned=31` at day 113 and stays there through day 152. `_fight_until` (`HeadlessCampaignLoop1SoakTest.gd:305–326`) trips `STALL_DAYS=40` (`:11`) after `113 + 39` frozen days. `D_MAX=400`. POL capitulation threshold is 0.62 (`CapitulationDomain.progress` `:260`, `threshold` `:314`; printed `pol_thr=0.6200`).

Same FAIL shape as the #218 box gate on tip `fff01b9e` and base `22d8acb0`. Pre-existing on main. Diagnosis files do not change the soak.

## 2. Where progress stops (S3 in-suite)

Soak S3 is `_player_victory` (`:271–302`): boot player **GER**, `include_player_in_ai_land_battles = true` (`:275`), `victory_min_majors_defeated=1` and `victory_count_minors=true` (`:276`), declare GER vs POL, station GER on the POL border (`_station_border` `:350`, 16 divisions), fight until POL capitulates.

The official soak does not dump per-unit stations. The measuring test copies the same boot/station/`_fight_until` surface and adds leftovers, last-flip pids, open battles, empty-hex siege, reject counters, and GER/POL unit rows.

In-suite freeze at 0.4460 owned=31 is the same plateau S1/S2 pass through. On the leftover S1-then-S3 measuring run (section 3), the freeze is a **POL recapture**: last GER flip is day 121 pid `711120` (Żyrardowski); POL then takes `711113`, `711086` (Elbing), `711083`, `711084` and owned climbs 31 → 35. At stall day 161:

- progress=0.4425 owned=35 last_flip=`day=121 pids=[711120]`
- open land battles = 0
- `_empty_hex_siege` empty
- Dominant rejects: `no_formation` (9) + `ratio` (1). `retake_cooldown` is no longer firing at stall.
- GER `cl1_GER_711057` wandered to station `710300` (Berlin depot). `cl1_GER_711088` sits on `711120` (the last GER flip) and does not walk on.
- POL `capdef_POL_711112` at `711081`, `capdef_POL_711112_2` at capital `711112`.

`FREEZE_START` in the measuring test fires on every 3-day empty-hex siege pause. That is ordinary light-capture pacing (`BattleManager.LIGHT_CAPTURE_ORDINARY_DAYS = 3` at `:54`), not the 40-day stall.

## 3. Why S3 and not S1/S2 (one change at a time)

S3 unique knobs (`_player_victory` vs `_observer_war` `:230` / `_defeat_run`):

1. player tag **GER** (S1 boots USA; S2/S2b boot POL)
2. `include_player_in_ai_land_battles = true` (`BattleManager.gd:9`; candidate skip at `:1050`; `plan_player = "OBS"` at `:1236–1240` so `LandBattleAi.plan_day` `:140` will order the human's GER divisions)
3. victory-rule overrides
4. S3 runs **last**, after S4, M8, S2, S2b, and S1 in the same process

Soak `_boot_as` (`:78–92`) clears `LeaderManager.formations`, sets the flag false, clears `_open_land_battles`, then `CampaignLoopTestBoot.boot` (clock reset `:127–137` to day 0) and domain resets. It does **not** call `BattleManager.reset_ai_war1_for_test()` (`:2129–2133`), does **not** clear `_empty_hex_siege` (`:67`), and does **not** clear `SupplyManager.division_deployments`.

| Variant | Env | Result |
|---------|-----|--------|
| S3 alone (GER + flag + victory) | `CL1_S3_POL_1_VARIANTS=s3` `/tmp/cl1-s3-pol-1-s3.log` | **CAPITULATES day 154** progress=0 owned=0 stationed=16, latched decisive victory. Passes through 0.4460 owned=31 at day 108 stall=1, continues (day 112 0.4599). |
| S1 then S3, soak-identical boot, no extra wipe | `CL1_S3_POL_1_VARIANTS=s1,s3` `/tmp/cl1-s3-pol-1-s1s3.log` | S1 capitulates d154. S3 boot leftover: `cooldown_n=9 blocked_n=9 dep_n=10 siege={}` stall `last_progress_day=154` for POL and GER. S3 **STALLS day 161** progress=0.4425 owned=35. |
| S1 then S3, extra wipe after boot | `CL1_S3_POL_1_WIPE=1` `/tmp/cl1-s3-pol-1-wipe.log` | Leftover at S3 boot all zeros. S3 **CAPITULATES day 154** like S3-alone. |

GER-as-player + flag + victory overrides are **not** sufficient to stall. S3-alone with those knobs wins. The stall is leftover in-process AI-war / supply state that soak `_boot_as` leaves behind, combined with the S3 player/flag path. S1 after S2 leftover still PASSES because player=USA and the flag stays false (`:1050` skips the player tag; `plan_player` stays USA so GER is ordered as AI).

`flag_off` and `no_victory` were not run as separate variants. Not needed: S3-alone already has flag=true and the victory overrides and still capitulates.

WIPE=1 (measuring-test only, not committed into soak) after boot:

- `BattleManager.reset_ai_war1_for_test()` — clears `_retake_cooldown`, `_retake_blocked`, `_ai_stall`, `_attack_reject`
- `_empty_hex_siege = {}`
- `SupplyManager.division_deployments.clear()`

The three were not split-tested. Combo wipe unstuck S1-then-S3.

### Leftover levers (file:line)

**Retake cooldown keyed by pid, until-day from the previous clock.** `_set_retake_cooldown` (`:2357–2368`) stores `_ai_day() + _ai_cooldown_days()` (default 7, `:2173`). `_retake_blocked_for` (`:2342–2354`) returns true while `_ai_day() < until` for the previous owner/controller. After `_reset_clock` sets `total_days_elapsed = 0` (`CampaignLoopTestBoot.gd:136`), leftover until-days around 154–161 stay in the future for the entire new S3 run. `_bump_attack_reject("retake_cooldown")` at `:326–327` and `:1109–1110`. Measured: 9 cooldown keys + 9 blocked keys at S3 boot after S1.

**`_ai_stall.last_progress_day` from the previous war.** `_ai_stall_days` (`:2205–2211`) is `maxi(0, current_day - last_progress_day)`. Leftover `last_progress_day=154` with the clock at 0 yields stall_days=0 until the new clock passes 154, so this row does **not** fire the 90-day stall threshold (`:2167`) during a 161-day S3. It is leftover, and WIPE clears it, but it is not the measured 40-day soak stall by itself.

**`SupplyManager.division_deployments` (10 rows after S1).** Not cleared by soak `_boot_as`. Can leave prior-war station/supply rows under new division ids.

**`_empty_hex_siege`.** Empty at the leftover S3 boot and at stall. Cleared by WIPE for completeness.

`plan_player = "OBS"` (`:1238–1240`) works for S3-alone: GER is ordered and POL capitulates. Do not treat that branch as the stall.

## 4. Options for OP (none applied)

Any later fix needs its own OP GO, with a before/after on the identity / twin / trace pins and the d180 bands.

1. **Test-only wipe in soak `_boot_as` (smallest).** `HeadlessCampaignLoop1SoakTest._boot_as` calls `reset_ai_war1_for_test()`, clears `_empty_hex_siege`, clears `SupplyManager.division_deployments`. Measuring WIPE=1 already unstuck S1-then-S3 (capitulate d154). Expected S3 effect: in-suite S3 matches S3-alone. Identity / twin / trace / d180 unchanged if product boot is not touched. Soak-only. Risk: none to live play; soak S2 determinism md5 may move if leftover from S4/M8 currently feeds S2 (S2/S2b already PASS and match each other today).

2. **Product boot wipe.** `CampaignLoopTestBoot.boot` or `BattleManager` on player-tag change clears the same three maps. Broader. Expected S3 effect: same as (1) plus any other in-process harness that re-boots a player. Risk to identity / twin / trace and d180 if a live AI-war leftover currently changes later days.

3. **Narrower product: ignore leftover `_ai_stall.last_progress_day` when the clock rewinds.** Clamp or reset stall rows when `last_progress_day > _ai_day()`. May not be sufficient: leftover cooldown until-days are the stronger measured lever, and the combo wipe was not split.

4. **Do not change `plan_player = "OBS"` / `include_player_in_ai_land_battles`.** Working for S3-alone. Changing it would retarget a working path.

This slice does not apply any of them.

## 5. Measuring test

`scripts/core/HeadlessCl1S3Pol1Test.gd` (+ `.uid` created by Godot for this file).

```
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessCl1S3Pol1Test.gd
CL1_S3_POL_1_VARIANTS=s3,s1,flag_off,no_victory
CL1_S3_POL_1_WIPE=1    # optional extra wipe after boot; default off (soak-identical)
```

Not wired into `tools/eoa_full_test_gates.sh`.
