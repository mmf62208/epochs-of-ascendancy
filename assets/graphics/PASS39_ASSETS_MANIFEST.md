# Asset Pass 39 — ★ only · Index merge · Risk scale · Bulk tag

Skills: `game-asset-core` · `game-ui-icons`

## Favorites-only filter chip

| UI | **★ only** toggle next to Clear tags |
|----|--------------------------------------|
| Token | Injects `@fav` into search filter |
| Match | Also accepts `@favorite`, `:fav`, `★` |
| Sync | Chip follows filter text containing `@fav` |

Filter still ANDs with `#tag` tokens and free text.

## Import index merge

| Button | **Merge Idx** |
|--------|---------------|
| Source | `user://route_packs/_index.json` |
| Action | Union tags; note prefers local; favorite OR |
| Skip | Packs without a local `.eorp` file |
| Modes | API supports `union` (default) or `replace` |

API: `import_route_pack_library_index(path, merge_mode)` → `{ok, merged, skipped}`

## Risk legend scale

- Minimap bottom-right gradient bar when pack pins visible  
- Cool (lo) → hot (hi) matches pin risk coloring  
- Labels: `risk` · `lo` · `hi`  

## Pack bulk tag

| Button | **Bulk Tag** |
|--------|--------------|
| Scope | Multi-selected Left items, or all visible if none selected |
| Effect | Union tags from tags field onto each pack |
| List | Left list is multi-select (Ctrl/Shift) |

API: `bulk_tag_route_pack_library(names, tags_str, replace=false)`

## Code

| File | Change |
|------|--------|
| `MapRenderer.gd` | @fav filter, merge index, bulk tag, Lib UI |
| `MapMinimap.gd` | Risk scale bar |

## Limits / Pass 40 ideas

- Merge does not download missing pack files (metadata only).  
- Bulk tag is union-only from UI (API supports replace).  
- Risk scale is static legend (not live histogram).  
- Pass 40 candidates: replace-mode merge toggle, bulk untag, risk histogram from pins, library folder groups. **Done — see PASS40_ASSETS_MANIFEST.md.**
