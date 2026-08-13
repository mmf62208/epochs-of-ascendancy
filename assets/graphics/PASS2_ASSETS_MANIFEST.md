# Asset Pass 2 — Units · Tech Domains · Transitions · Wordmark

Skills: `game-asset-core` · `game-ui-icons` · `game-tilesets`

## Unit chips — `assets/graphics/units/retrowave/`

Retrowave NATO-style counters (64 + 32):

| Stem | Source |
|------|--------|
| infantry, artillery | Generated |
| medium_tank, light_tank*, heavy_tank* | Generated + brightness variants |
| fighter, bomber* | Generated + variant |
| destroyer, cruiser*, carrier*, submarine* | Generated + variants |
| logistics*, helicopter*, rocket* | Variants from base set |

`*` = derived variants (brightness/color) for coverage; regenerate for art-perfect uniqueness later.

**Wired:** `MapRenderer._prefer_retrowave_unit_icon` — prefers retrowave over `nato/ww2|modern` when files exist.

## Tech domain icons — `assets/graphics/icons/tech_domains/`

| Domain | Icon |
|--------|------|
| industry | generated |
| land_equipment | generated |
| naval_equipment | generated |
| air_equipment | generated |
| space_equipment | generated |
| doctrine | HUD agents alias |
| support | HUD technology alias |
| strategic_future | HUD space alias |

**Wired:** `TechnologyScreen` domain filter icons + row header icons; progress bars use `RetrowaveTheme.style_progress_bar`.

## Terrain transitions — `assets/graphics/tiles/transitions/`

| File | Role |
|------|------|
| `plains_hills_blend.png` | Continuous plains→hills strip |
| `plains_hills_edge.png` | Center edge sample (rotation-safe candidate) |
| `plains_fill_from_blend.png` / `hills_fill_from_blend.png` | End fills |
| `plains_hills_edge_2x2_preview.png` | Seam check |

Indexed in `TerrainTileLibrary.KEYS`.

## Branding — `assets/graphics/branding/`

| File | Role |
|------|------|
| `epochs_wordmark.png` | Title logo (read-back: **EPOCHS / OF ASCENDANCY** ✓) |
| `epochs_wordmark_512.png` | Smaller |

**Wired:** `LoadingScreen` wordmark + styled progress bar; chapter titles remain as text under the mark.

## Limits / next

- Bomber/sub/carrier still partial variants of fighter/destroyer (rate-limit truncated full regen).
- Transition tiles catalogued but not yet used in a live autotile painter.
- Wordmark not yet on main menu (loading only).

**Suggested Pass 3:** full unique bomber/sub/carrier/helo chips, doctrine/support dedicated icons, main menu wordmark, autotile painter using transition edge.
