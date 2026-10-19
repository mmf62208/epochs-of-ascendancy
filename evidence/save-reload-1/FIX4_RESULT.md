# SAVE-RELOAD-1 FIX #4 — title Command Center close / swallow

**Merge HOLD. Draft. Play on 041d9104 was MIXED (FIX #3 items pass; this is the new FAIL).**

Branch `grok/save-reload-1` on top of FIX3 `041d9104`. Regular commit, no force-push.

## Bug 1 vs main `d00dc8ed`

**Reproduced on main.** `LivingTitleBoot.handle_live_escape` is sticky open-only (`_ensure_command_center_stays_open` / `_esc_routed_to_cc`). `MainMenu._input` refuses `_force_close` while the living title is up (`keep_cc` / `eoa_opened_from_living_title`). Title `window_input` / `_process` / `handle_live_pointer` still fire, so a click can hit Command Center **Exit to Desktop** and a title save row in one press. This is not unique to SR1 title-list work; SR1 still has to fix it because title-opened CC must close and must swallow.

## Product

1. **MUST — close + swallow.** First Esc / title CC button opens Command Center. A later Esc, ×, or Return to Title closes it. While it is up, `handle_live_pointer` returns `cc_block` for the whole screen: title save rows, Begin, and Exit underneath do not fire. `eoa_cc_open_latch` covers only the opening Esc so MainMenu cannot close the overlay it just opened.
2. **SHOULD — confirm pad.** `ConfirmMargin` top 32 px so “will be lost” sits below the frame art.
3. **SHOULD — one damaged toast.** 400 ms debounce in `_show_damaged_save_message` (button + pointer both used to toast).
4. **SHOULD — title ≠ map.** Title-up release is handled; `_try_open_land_chip_from_input` returns false while the title is up.
5. **SHOULD — session time.** “Unsaved progress since …” uses `SaveLoadManager.session_wall_time` (last successful save or load this session), not the newest file on disk.
6. **SHOULD — v1 migrate log.** `_migrate_save_data(..., from_v1_file)` prints only for a real v1 file. Fresh v2 still has body `save_version == 1` (`SAVE_VERSION` const stays 1); that is not a v1 file.
7. **SHOULD — camera.** `map_ui` stores camera pos/zoom. `restore_view_after_load` restores it, or centres the player capital. Title `_finish` defers that instead of a held-camera no-op that left the view in Brazil.

`world_full` IDs not renumbered. No GameData rewrite. No Godot bump. No `/home` paths. Seed `20fe9063` unedited.

## Tests (filled after the gate run)

| Test | PASS | FAIL | SCRIPT ERROR | RESULT |
|---|---:|---:|---:|---|
| `WindowedSaveReload1TitleCcTest` | — | — | — | pending |
| `HeadlessSaveReload1TitleListTest` | — | — | — | pending |
| `WindowedSaveReload1UiGuard` | — | — | — | pending |
| `HeadlessIx1LivingTitleEscBeginTest` | — | — | — | pending |
| `HeadlessSaveReload1CorruptTest` | — | — | — | pending |
| `--quick` | 14 known reds | — | 0 | pending |
