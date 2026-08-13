# Asset Pass 40 — Merge replace · Untag · Risk hist · Folder groups

Skills: `game-asset-core` · `game-ui-icons`

## Replace-mode merge toggle

| UI | **Repl** checkbox next to Merge Idx |
|----|-------------------------------------|
| Off (default) | Union tags; note prefers local; fav OR; group prefers local |
| On | Index replaces tags / note / fav / group |

Toast shows mode: `Index union · N packs` or `Index replace · N packs`.

## Bulk untag

| Button | **Untag** |
|--------|-----------|
| Tags field filled | Remove those tags from selected packs |
| Tags field empty | Clear **all** tags on selected packs |
| Scope | Same as Bulk Tag (multi-select or all visible) |

API: `bulk_untag_route_pack_library(names, tags_str)`

## Risk histogram from pins

- Minimap: 5-bin histogram above the risk gradient scale  
- Bins from pin `risk` values (0–20% … 80–100%)  
- Label `hist n=` pin count  

## Library folder groups

| Field | **group** LineEdit on save row |
|-------|--------------------------------|
| **Group** button | Assign group to selected packs |
| Sort **Group** | Named groups first + section headers |
| List | `[group]` badge; `── name ──` headers when sorted by group |
| Filter | `@group:east` or free text matching group |
| Sidecar | `{ tags, note, favorite, group }` |

API: `set_route_pack_library_group`, `bulk_group_route_pack_library`, `list_all_pack_library_groups`

## Code

| File | Change |
|------|--------|
| `MapRenderer.gd` | Untag, groups, merge replace UI, list headers |
| `MapMinimap.gd` | Risk histogram + scale |

## Limits / Pass 41 ideas

- Groups are flat labels (no nested folders).  
- Histogram is pin-count only (not weighted by route length).  
- Pass 41 candidates: nested groups, drag pack between groups, risk heatmap export, library search history. **Done — see PASS41_ASSETS_MANIFEST.md.**
