# Asset Pass 50 — Bulk pin focus · Heat swatch · Drag-resize · Multi-window

Skills: `game-asset-core` · `game-ui-icons`

## Pin focus filtered by bulk / Left packs

| UI | **Pin Foc** (bulk bar) |
|----|------------------------|
| Bulk tags/groups | Focus candidates from matching library packs + loaded pins |
| Left selection | Restrict / soft-match by pack name |
| Empty filter | All loaded minimap pins by risk |
| Shift | Lowest risk first |
| Cycle toast | `label · i/n · prov · source` |

APIs:

- `_pack_focus_candidates(filter)`
- `focus_pack_pin_by_risk(cycle, highest_first, filter)`
- `focus_pack_pin_by_risk_info(...)` → `{pid, total, index, label, source, risk}`

Filter keys: `tags`, `groups`, `pack_names`, `tag_or`, `group_or`.

## Heat ramp swatch legend

| Where | Minimap top-right |
|-------|-------------------|
| Content | Cool→hot gradient segments + ramp id + `lo→hi` |
| Gate | Heat on, pins present, intensity > 0 |
| UI | **Swatch** checkbox on compare card |
| API | `MapMinimap.set/get_show_heat_ramp_legend` |

Risk histogram bars also use active heat ramp colors.

## Library drag-resize

| Grip | `◢` bottom-right of library panel |
|------|-----------------------------------|
| Drag | Grow/shrink width & height (400–1200 × 360–1000) |
| Persist | `pack_library_w` / `pack_library_h` in prefs `v: 5` |

Layout presets still reset chrome; open restores last drag size when `use_saved_size`.

## Multi-window library

| Control | Behavior |
|---------|----------|
| **Lib** | Replaces primary `PackLibraryPopup` |
| **Shift+Lib** | Opens `PackLibraryPopup_N` (stacked offset) |

Title shows `· N` for secondary windows.

## Code

| File | Change |
|------|--------|
| `MapMinimap.gd` | Heat swatch legend + hist ramp colors |
| `MapRenderer.gd` | Bulk pin filter, resize grip, multi-window, prefs v5 |

## Limits / Pass 51 ideas

- Secondary library windows are independent (no shared selection).  
- Pin filter uses library tags on slot labels (label must match pack stem).  
- Pass 51 candidates: dockable library, pin focus camera zoom, shared bulk across windows, heat swatch click-to-cycle ramp.
