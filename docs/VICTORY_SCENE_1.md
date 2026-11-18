# VICTORY-SCENE-1

Campaign win and loss end scenes for the Ink end screen and the CL1 end screen. Scope v2 (`~/eoa_inputs/victory_scene/VICTORY_SCENE_1_SCOPE.md`, md5 `82d65417f8cec5332dc58f62025509be`). Base `5d099346`. Branch `grok/victory-scene-1`.

Killswitch: `EOA_VICTORY_SCENE=0` keeps today's panels and does not add a stage. Any other value, including unset, shows the scene.

## What landed

- `VictorySceneModel` maps victory-path, Ink, national-defeat, and CL1 outcomes onto WIN / DEFEAT / SHEET, including `ascendant` (fallback `score`) and `eclipsed` (no particles).
- `data/campaign/victory_scene.json` holds headlines, nation rows, and layout. No new save fields. Provinces-at-start read a capitulation snapshot when `snapshotted` is set, otherwise the read-only `res://` ownership file for the scenario era.
- `VictorySceneStage` / `DefeatSceneStage` draw the picture. Legacy labels stay on a hidden readout so existing tests still see `OutcomeTitle`, `PathTitle`, `Title`, `Reason`, `Date`, `Stats`, and the `Btn*` names. Ink win adds `BtnLoadSave` ("Load"). The killswitch win panel does not.
- `CampaignEndScreen.get_end_model()` returns `_model.duplicate(true)`.
- `VictoryPathsDomain._present()` adds `held`, `total`, `hold`, `need`, `pct`, `streak`, and `score` beside the unchanged `stats` string.
- Stings stay `end_victory_sting` and `end_defeat_sting`. Skip does not replay them. Esc does not dismiss the screen.

## Test

```bash
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessVictoryScene1Test.gd
```

Cases 1–12 cover the mapper, stages, generic-flag fallback, burn, skip, clock lock, stings, no save/owner-index writes, RNG isolation, provinces-at-start, the killswitch, and the CL1 host. Ship wires this into `tools/eoa_full_test_gates.sh --quick` after PR #194. This branch does not edit that script.

## Deviations

- Ink's package is at `~/eoa_inputs/victory_scene/` (MD5SUMS md5 `3b2f4385c1eb9cbceac205084d1c54ff`, `md5sum -c` OK). The brief's `ink/` subdirectory was not staged.
- Art paths are `res://assets/graphics/victory_scene/<tag>/` and `_shared/`. Flags for the seven majors plus `generic.png` and `generic_field_mask.png` live under `assets/graphics/flags/`. `FLAGS_MANIFEST.md` is copied with them. Minor flags (including POL) are not, so those tags use the generic flag.
- Fonts are only `assets/fonts/montserrat/Montserrat[wght].ttf` and `assets/fonts/gelasio/Gelasio-Italic[wght].ttf`, each with its own `OFL.txt`. `assets/fonts/OFL.txt` is untouched. `FONTS_MANIFEST` is not copied.
- Layout lives under the `layout` key of `data/campaign/victory_scene.json`.
- `CPUParticles2D.new()` calls the global RNG in its constructor. The scene warms a fixed pool on the first mapper call and reuses those nodes, so a later defeat open (the D7 check) does not construct more. Headless never emits. Software renderers use half the particle count.
- The two new straight-alpha wordmarks request mipmaps in their `.import` sidecars. Filter is set on the node (Godot 4.7 texture imports have no filter key).
- `docs/CURRENT_STATE.md` and `docs/TESTING_PLAN.md` are unchanged.
