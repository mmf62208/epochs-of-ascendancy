# CAMPAIGN-SAVE-1 near-capitulation fixture

Play mouse path for **player capitulation** and **Continue as…**. Do **not** turn on `eoa/dev_menu`. Do **not** add `override.cfg`. This file is a test fixture, not a shipped user save.

Fixture: `tests/fixtures/campaign_save_1/near_capitulation.json`

Germany (GER) is at war with France. France already holds enough of Germany’s 1936 land that the **real daily tick** (not a direct latch call) capitulates Germany.

**N = 1** in-game day at 1× through `TimeManager.advance_live_f5_equivalent_days` / the live F5 day flush (`_campaign_after_battles` → `CapitulationDomain.check_all`). Headless cap is 15 days. JSON `by_pid` keys are strings after load; `CapitulationDomain` coerces them so occupation weight survives Command Center Load.

## Copy into the game saves folder

Command Center loads `user://saves/`. Copy the JSON there (name it whatever you like; `near_capitulation.json` is fine):

```bash
# Typical Linux Godot user data:
mkdir -p ~/.local/share/godot/app_userdata/Epochs-of-Ascendancy/saves
cp tests/fixtures/campaign_save_1/near_capitulation.json \
  ~/.local/share/godot/app_userdata/Epochs-of-Ascendancy/saves/near_capitulation.json
```

On this machine the Command Center save list shows the folder path at the bottom of the panel (`Folder: …`). Paste the file there if the path differs.

## Play (1) — capitulation in N days

1. F5 / Begin as usual (Victory Paths stays unchecked).
2. Open **Command Center** (Esc or Menu).
3. Select **near_capitulation** and **Load**. HUD shows **At war: France**. Some German land is French-controlled (occupation).
4. Unpause at **1×**. Do not declare, move, or fight. On the **next day** (N=1; wait up to 15 if the first flush is deferred) Germany capitulates.
5. **One** overlay: **Defeat**, date in long form (not `YYYY-MM-DD`). Clock paused. No second VICTORY panel, no Leadership Transition on top. Verdict line once (title is not repeated in the body).
6. Click **Continue as…** for the successor picker (`Choose nation to continue playing as`). Confirm a nation, or Cancel back to Defeat.
7. **Load** / **Main menu** / **Return to Title** still work from that overlay and from Command Center.

## Play (2) — Return to Title then Begin must not leak war

1. Load **near_capitulation** as above (At war: France).
2. Open Command Center → **Return to Title**.
3. **Begin** a new 1 January 1936 game (Victory Paths still unchecked).
4. HUD must **not** show At war: France. Clock 1 Jan 1936. No campaign-end overlay, no leader-event hold.

## Play (4) / (5) — Continue as Germany, then Esc

1. Reach the Defeat overlay (1949 timeout or this fixture).
2. The keep-going button is labelled **Continue as Germany** (not “Keep playing”). Same behaviour: dismiss overlay, clock runs, no nation switch.
3. Click it, then **Esc** on the map. **Paused** Command Center must open.

Regenerate the JSON (does not enable the debug menu):

```bash
tools/run_godot.sh --headless --path . \
  -s res://scripts/core/HeadlessCampaignSave1NearCapitulationFixture.gd
```
