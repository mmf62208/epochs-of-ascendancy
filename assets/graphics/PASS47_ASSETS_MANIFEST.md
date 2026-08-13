# Asset Pass 47 — Legend opacity · Hist file dialogs · Filter cancel · Chip keys

Skills: `game-asset-core` · `game-ui-icons`

## Pack legend opacity

| UI | HSlider next to heat intensity on compare card |
|----|------------------------------------------------|
| Range | 0.0–1.0 (step 0.05) |
| Effect | Scales minimap pack pin legend swatch/label alpha |
| API | `MapMinimap.set/get_pack_legend_opacity` |

Persisted in `user://route_packs/_map_prefs.json` (`v: 2`) + save `pack_legend_opacity`.

## History file dialogs

| Control | Default click | Modifier |
|---------|---------------|----------|
| **Exp Hist** | Write default export path | **Ctrl/Alt/Meta** → Save FileDialog |
| **Imp Hist** | Import default path | **Ctrl/Alt/Meta** → Open FileDialog |

Import still: **Shift** = replace mode (with or without dialog).

## Filter cancel token

| State | UI |
|-------|----|
| Pending | Flat button `Updating… ✕` (clickable) |
| Cancel | Click button **or Esc** in search field → bumps gen token, shows `Cancelled` |
| Done | Cleared when `fill_lists` finishes |

Stale debounce timers no-op after cancel (same gen token as keystroke debounce).

## Chip menu keyboard shortcuts

While context menu open:

| Key | Action |
|-----|--------|
| **F** | Filter |
| **A** | Assign |
| **C** | Copy |
| **X** | Clear |

Labels show accelerators: `Filter (F)`, etc.

## Code

| File | Change |
|------|--------|
| `MapMinimap.gd` | Legend opacity state + draw |
| `MapRenderer.gd` | Prefs v2, legend slider, FileDialogs, cancel, accelerators |

## Limits / Pass 48 ideas

- FileDialogs use `ACCESS_USERDATA` only (not full filesystem).  
- Legend opacity 0 hides hit targets (intentional).  
- Pass 48 candidates: native OS file dialogs, heat color ramp picker, library layout presets, bulk chip multi-select.
