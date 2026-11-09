# CAMPAIGN-SAVE-1 near-capitulation fixture

Play mouse path for **player capitulation** and **Continue as…**. Do **not** turn on `eoa/dev_menu`. Do **not** add `override.cfg`. This file is a test fixture, not a shipped user save.

Fixture: `tests/fixtures/campaign_save_1/near_capitulation.json`

Germany (GER) is at war with France. France already holds enough of Germany’s 1936 land that the **next unpaused day** will capitulate Germany.

## Copy into the game saves folder

Command Center loads `user://saves/`. Copy the JSON there (name it whatever you like; `near_capitulation.json` is fine):

```bash
# Typical Linux Godot user data:
mkdir -p ~/.local/share/godot/app_userdata/Epochs-of-Ascendancy/saves
cp tests/fixtures/campaign_save_1/near_capitulation.json \
  ~/.local/share/godot/app_userdata/Epochs-of-Ascendancy/saves/near_capitulation.json
```

On this machine the Command Center save list shows the folder path at the bottom of the panel (`Folder: …`). Paste the file there if the path differs.

## Load by mouse

1. F5 / Begin as usual (Victory Paths stays unchecked).
2. Open **Command Center** (Esc or Menu).
3. Select **near_capitulation** and **Load**.
4. Unpause (1× is enough). On the next day Germany capitulates.
5. **One** overlay: **Defeat**, date in long form (not `YYYY-MM-DD`). Clock paused. No second VICTORY panel, no Leadership Transition on top.
6. Click **Continue as…** for the successor picker (`Choose nation to continue playing as`). Confirm a nation, or Cancel back to Defeat.
7. **Load** / **Main menu** / **Return to Title** still work from that overlay and from Command Center.

Regenerate the JSON (does not enable the debug menu):

```bash
tools/run_godot.sh --headless --path . \
  -s res://scripts/core/HeadlessCampaignSave1NearCapitulationFixture.gd
```
