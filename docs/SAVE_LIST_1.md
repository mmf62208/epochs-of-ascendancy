# SAVE-LIST-1 — truthful Load list after same-second overwrite

**Status:** draft **HOLD merge**. Branch `grok/save-list-1`. Base `5d099346`. Does **not** touch SAVELOAD-DESIGN-1 (stays PARKED).

Revives two parked ORDERS-PERF-FOLLOWUP items (finer saves fingerprint; `is_inside_tree` guard + deferred rebuild) and the #191 Play UX nit: autosave rows titled Session/Autosave never showed which file they were.

## Why

`OrderCommandPanel._saves_dir_fingerprint()` was `file count : newest mtime`. `FileAccess.get_modified_time` has 1-second resolution. Overwriting an existing slot (quicksave, autosave rotation) in the same wall-clock second leaves count and newest mtime unchanged, so `_saves_list_cache_valid` stays true and the Load list keeps the old game date and nation.

## What changed (fence)

| File | Change |
|------|--------|
| `scripts/autoload/SaveLoadManager.gd` | Runtime-only `_save_generation` bumped on every successful write/delete/rename via `_notify_save_list_refresh`. Public `get_save_generation()`. Never written to disk. Autosave row title keeps `Session`/`Autosave` and appends the rotator token (`Autosave 2 · 3 Feb 1936 · …`). |
| `scripts/ui/OrderCommandPanel.gd` | Fingerprint is `count:mtime:generation` when the getter exists; `count:mtime` remains the fallback. `refresh()` returns if not `is_inside_tree()` and `call_deferred` rebuilds on re-enter. |
| `scripts/core/HeadlessSaveList1Test.gd` | Standalone guard (not wired into `--quick`). |
| `docs/SAVE_LIST_1.md` | This note. |

Forbidden paths (`GameData.gd`, `TimeManager.gd`, gates runner, `docs/perf/`, `data/`, …) were not touched.

## Fail on base `5d099346` / pass on tip

```
  [FAIL] HeadlessSaveList1Test: case 1: quicksave row still shows 19 Jul 1936 after same-second overwrite: ⚡ quicksave · 19 Jul 1936 · Germany (GER) · saved 1 Jan 1970 00:01
  [FAIL] HeadlessSaveList1Test: case 2: session row missing slot token: Session · 3 Feb 1936 · Germany (GER) · saved 1 Jan 1970 00:05
  [FAIL] HeadlessSaveList1Test: case 3: refresh rebuilt while panel was not inside the tree
HeadlessSaveList1Test: RESULT=FAIL
```

Tip:

```
  [PASS] HeadlessSaveList1Test: case 1: same-second overwrite shows 20 Aug 1936
  [PASS] HeadlessSaveList1Test: case 2: Session/Autosave titles keep prefix and add slot tokens
  [PASS] HeadlessSaveList1Test: case 3: out-of-tree refresh is quiet; rebuild waits for re-enter
HeadlessSaveList1Test: RESULT=PASS
```

Standalone: `XDG_DATA_HOME=$(mktemp -d) tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessSaveList1Test.gd`

## Proof

Recorded on this run. Headless Godot 4.7.1 via `tools/run_godot.sh`. Fresh `XDG_DATA_HOME` each process.

| Check | Result |
|-------|--------|
| `HeadlessSaveList1Test` solo ×5 | PASS ×5 |
| `HeadlessAutosave1Test` unmodified | RESULT=PASS |
| `HeadlessCampaignSave1Test` unmodified | RESULT=PASS |
| `HeadlessSaveReload1DeterminismTest` identity_twin | RESULT=PASS |
| `tools/eoa_full_test_gates.sh --quick` | ALL PASSED · wall **524 s** |
| Orders-perf **b** warm reopen (max of 3) | 140 ms (134 / 140 / 134) |
| Orders-perf **d** map-select (max of 3) | 148 ms (146 / 148 / 140) |
| Seed `grep -o 'multi_ai_decisions=.*' log \| md5sum` | `20fe9063de285f19d4f9b8a105abfd31` |
| Identity | `d22b87cf` MATCH |
| Twin end / TRACE_MD5 | `7abd07c2` / `5fda7a57` MATCH |
| SCRIPT ERROR (product path) | 0 |

Default `SR1_DET_MODE=inproc` (3-day detour then load in one process) is not the standing identity gate; `tools/eoa_campaign_save1_identity.sh` runs `identity_twin`.
