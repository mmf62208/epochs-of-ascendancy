---
name: eoa-portraits
description: >
  EOA leader portrait and HUD chrome pipeline. Use when generating or wiring
  portraits, empty-seat fallback, _64 UI crops, historical_leaders JSON,
  army/navy/air commanders, or when the user mentions leader art. Slash:
  /eoa-portraits. Load imagine + game-asset-core + game-character-consistency
  before generating.
---

# EOA portraits

Roster is JSON, not invented names in GDScript:

- `data/leaders/historical_leaders_1936.json`
- `data/leaders/historical_leaders_1918.json`
- `data/leaders/historical_leaders_2026.json`

Loader: `scripts/leaders/LeaderManager.gd`.

## Files

- Full: `assets/graphics/portraits/leaders/<slug>.png` (128×128 after ingest)
- UI: `assets/graphics/portraits/leaders/<slug>_64.png`
- Empty seat: `assets/graphics/ui/leader_empty_seat.png` (+ `_64`)

Slug pattern: `tag_role_year` (e.g. `arg_air_1936`, `aus_mitchell_2026`) or a unique leader slug. `.import` only for `*_64.png` unless the tree already has a full-size import.

## Rules

1. Set JSON `portrait` **only** when the PNG exists on disk.
2. Named real people: `image_edit` from a real reference after search — not a fresh `image_gen` from the name.
3. Generic role seats (Aviation Commander): invented dieselpunk uniform, 1:1, no text, plain/keyable background.
4. `_64` is an edit-chain / PIL LANCZOS crop of the same full image, not a second generation.
5. Empty-seat PNGs exist under `assets/graphics/ui/` but are **not wired**. `LeaderDetailScreen` hides the TextureRect when `portrait_path` is empty. Wiring empty-seat as fallback is a real product task, not already done.
6. Load `imagine` + `game-asset-core` + `game-character-consistency` before generating a set.
7. Disk PNG without JSON `portrait` is invisible at runtime. Do not claim coverage from git-untracked files.

Counts in `docs/leader_portraits_bulk_summary.md` go stale — recount from disk + JSON before claiming coverage.
