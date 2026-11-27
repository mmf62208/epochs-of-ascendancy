# LOAD-SCREEN-1

Point the Loading Screen wordmark at the alpha PNGs that VICTORY-SCENE-1 already uses. Base `e0388c58`. Branch `grok/load-screen-1`.

## What changed

`scripts/ui/LoadingScreen.gd` loads the brand mark in this order:

1. `res://assets/graphics/branding/epochs_wordmark_alpha.png` (`WORDMARK_PATH`, 768)
2. `res://assets/graphics/branding/epochs_wordmark_512_alpha.png` (`WORDMARK_PATH_512`)
3. `res://assets/graphics/branding/epochs_wordmark.png` (opaque fallback)
4. `res://assets/graphics/branding/epochs_wordmark_512.png` (opaque fallback)

The opaque files stay in the repo. No new art. The `Wordmark` TextureRect stays `custom_minimum_size` 200×48. The alpha and opaque 768 canvases are both 768×432, and the visible ink sits in the same region of that canvas, so the fitted mark scale is unchanged.

## Pins kept

- Layer `LOADING_LAYER` 80, group `loading_screen`.
- `HeroArt`, `BottomScrim` with `anchor_top = 0.89`.
- Four quarters in `LOADING_ART_QUARTERS`. At progress 0.30 the title stays `THE AGENT'S EPOCH`.
- `title_label` stays public, `autowrap_mode = AUTOWRAP_WORD_SMART`, `clip_text = false`, font size cap 20.
- `show_loading`, `update_progress`, `soft_unlock_input`, `hide_and_free`. Dismiss, the 120s safety timer, the 58% map-live dismiss, and the 98% complete dismiss stay.
- Title gold `Color(0.95, 0.86, 0.45)`, scrim, margins, and layer stay.
- The four JPGs under `assets/loading_screens/` stay.

## Deferred

The Command Center / Paused header in `scripts/ui/MainMenu.gd` still loads the opaque wordmarks (about L461–464 on this base). That file is in open draft #200 (B2-LIVE-1). This slice does not edit it. Swap the Command Center mark after #200 is closed, or when OP explicitly allows a MainMenu touch.

## Test

```bash
XDG_DATA_HOME=$(mktemp -d) XDG_CONFIG_HOME=$(mktemp -d) tools/run_godot.sh --headless --path . \
  -s res://scripts/core/HeadlessLoadScreen1Test.gd
```

Fails on base `e0388c58` (opaque `WORDMARK_PATH`). Passes on this tip (alpha 768 preferred). Not wired into `tools/eoa_full_test_gates.sh` (that script is in open #164 and #194). `HeadlessFirst20P1Test` is unchanged.
