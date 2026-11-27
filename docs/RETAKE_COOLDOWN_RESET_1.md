# RETAKE-COOLDOWN-RESET-1

`BattleManager` stores retake cooldown as an absolute until-day (`_ai_day() + cooldown`). That integer is not rewritten when the clock returns to day 0. A later new game, or a load whose blob has no `land_war` dictionary, used to keep the old until-day in the future and block retakes.

`BattleManager.reset_ai_war1()` wraps `reset_ai_war1_for_test()` and clears `_attack_reject` again. `CampaignEndDomain.reset_session_for_new_game()` calls it, so empty-slot Begin and Return to Title both drop the maps. `SaveLoadManager._apply_save_data` calls it only when `land_war` is missing or not a Dictionary. A blob that includes `land_war` still restores the saved absolute until-days through `apply_save_data`.

Until-days stay absolute. The save writer is unchanged. `HeadlessCampaignLoop1SoakTest._boot_as` still wipes with the test helper.

Guard: `scripts/core/HeadlessRetakeCooldownReset1Test.gd`.
