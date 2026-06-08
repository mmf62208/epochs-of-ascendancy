# In-Game Province Editor & Flexible Province System — Design Document

**Status:** Design + Initial Implementation Started  
**Date:** June 2026  
**Priority:** Foundational for map flexibility, modding, and long-term content creation  
**Related:** 
- `data/provinces/SCHEMA.md`
- `scripts/data/Province.gd`
- `scripts/core/ScenarioLoader.gd`
- `scripts/map/MapManager.gd`
- `scripts/map/MapRenderer.gd` (existing "Map Visual Editor (Starter)" + object placement)
- `scripts/ui/DebugOverlay.gd`
- Python map generation tools in `tools/map_generation/`
- Current province layers (geometry, base, terrain, economy, etc.)

---

## 1. Executive Summary & Goals

The user wants the map **mostly blank** initially for maximum flexibility during design and modding. Provinces should be easy to create, edit, merge, split, and variant over time (1918 → 1936 → 2026+).

**Key Requirements:**
- Clean base map (parchment style with clear rivers, mountains, coastlines, lakes — no political borders or provinces drawn in).
- Powerful **in-game editor** (preferred over external tool for immediate feedback, modding accessibility, and designer iteration inside the actual game view + camera/zoom).
- Data-driven with full historical variant support.
- "Smart" assistance for realistic borders (rivers, mountains, chokepoints, population centers).
- Live or near-live preview of provinces as Polygon2D on the map.
- Easy export back to the layered JSON format used by ScenarioLoader / MapManager.

**Why In-Game Editor Wins:**
- Designer sees exact visual result with the real camera, lighting, overlays, and zoom levels.
- Immediate testing of movement costs, supply, combat width, etc.
- Excellent for modding community (no need to run external Python tools).
- Can be toggled via Debug or a dedicated "Map Design" mode.

---

## 2. Base Map Requirements

- A "clean" high-detail parchment/stylized background image with:
  - Clearly visible rivers and major waterways (critical for natural borders).
  - Mountain ranges and hills (visual + future terrain tags).
  - Coastlines, fjords, islands, lakes with high fidelity.
  - No province lines, country colors, or text.
- Current assets have several detailed versions. Recommend creating or using a dedicated `europe_clean_parchment_base.jpg` (or equivalent for other theaters) optimized for editing.
- The editor should allow switching between "terrain visual" and "clean political" views (see previous terrain layer toggle work).

---

## 3. In-Game Province Editor Features

### 3.1 Core Editing Tools (in DebugOverlay or dedicated ProvinceEditorPanel)

Accessible from F10 Debug → new section: **"Province Editor (In-Game)"** (or hotkey when map is focused).

**Drawing Tools:**
- **Point & Click Polygon**: Click to add vertices. Close polygon with double-click or "Finish Province" button. Creates live Polygon2D preview (semi-transparent fill + thick border).
- **Freehand / Lasso** (future): Drag to roughly draw, auto-simplify points.
- **Smart Split Assistant**:
  - Button: "Suggest Split Along River"
  - Button: "Suggest Borders by Terrain / Mountains"
  - Uses existing map data or simple geometry checks (distance to river lines if we have vector river data, or pixel analysis of the base texture).
- **Edit Existing**: Click a province → enter edit mode (move vertices, add/remove points, reshape).
- **Delete / Merge**: Select two adjacent provinces → "Merge". Or delete and let neighbors absorb.

**Attributes Panel (per province or bulk):**
- Name, Terrain type (dropdown: plains, hills, mountains, swamp, desert, forest, urban...).
- is_sea / has_port / coastal.
- Base development, population, resources (quick sliders or tags).
- Victory Points, special_features.
- Tags (for modding: "industrial_heartland", "alpine_pass", etc.).
- Historical note field.

**Live Preview:**
- Newly drawn/edited provinces appear immediately as Polygon2D under the map (similar to current editor object placement).
- They participate in picking (MapPickGrid can be updated or use a temporary editor overlay).
- Toggle "Show Proposed Provinces Only" vs "Full Current Map".

### 3.2 Smart Assistance & Validation
- Auto-detect natural borders using:
  - Pre-baked river/mountain masks (from map generation pipeline).
  - Simple pathfinding that prefers low-cost terrain for "realistic" borders.
- Validation warnings:
  - "Province too small"
  - "No land connection" (for non-sea)
  - "Missing adjacency to coast for port province"
- Auto-assign basic attributes on creation:
  - Size → population/development hints
  - Coastal check → has_port suggestion
  - Terrain sampling from base image or data layer

### 3.3 Historical Variants & Time Travel
Provinces support a `historical_variants` structure (see schema below).

Editor should have:
- "Add Variant for Year 1918 / 1945 / 2026"
- Easy copy current province into a variant and tweak (e.g. split Germany, add new states).
- Scenario overrides remain the primary way to load a specific era's map state.

### 3.4 Data Export / Roundtrip
- "Export Current Editor Provinces" button → writes to `user://editor_provinces_geometry.json` + other layer stubs.
- Button to "Apply Editor Changes to Active Map" (live for testing).
- "Save as New Province Dataset" → creates a full set of layer JSONs in a new folder under `data/provinces_my_mod/`.
- Python tools can still ingest these for further processing or global map building.

**Recommended JSON Augmentation for Editor:**
Add to `provinces_geometry.json` (or a sidecar):
```json
{
  "editor_meta": {
    "created_by": "in_game_editor_v1",
    "last_edited": "2026-06-05",
    "base_map": "europe_clean_parchment_ultra.jpg"
  }
}
```

---

## 4. Technical Architecture

### 4.1 New / Extended Files
- `scripts/map/ProvinceEditor.gd` (or `scripts/ui/ProvinceEditorTool.gd`)
  - Manages current edited provinces (in-memory Dictionary of id → {points, attrs}).
  - Handles input (when active): mouse clicks for vertices.
  - Renders live Polygon2D previews (children of a "EditorProvinces" node under ProvinceContainers or a dedicated editor layer).
  - "Commit" function that generates proper geometry + base data and feeds to MapManager / ScenarioLoader.

- Extend `DebugOverlay.gd` — add "Province Editor" collapsible section with the drawing controls + list of current editor provinces + export buttons. Reuse the existing collapse / styling.

- Minor updates to `MapRenderer.gd`:
  - Support for a "clean_base_map" texture (separate from the styled political one).
  - `set_editor_mode(bool)` to show/hide normal province fills or lower their alpha heavily.
  - Live addition of editor polygons without full re-render.

- `MapManager.gd`:
  - Add `add_editor_provinces(temporary_data)` or better, a "working set" that can overlay/replace the loaded provinces for editor sessions.
  - Keep the main loaded data pristine.

### 4.2 Runtime vs Authoring
- The editor runs in debug builds or when a special "map_design_mode" flag is set.
- Normal gameplay always uses the loaded JSON data (no editor overhead).
- Editor changes are **not** automatically persisted to the main data/ folder — user must explicitly export.

### 4.3 Blank Map Support
- Add to ScenarioLoader / TestRunner the ability to load a "blank" scenario that only has the base texture + no (or minimal) provinces.
- Or a special "editor_base" province data dir with 0 provinces + the clean image.

---

## 5. Province Data Schema Extensions (for Editor & Variants)

Extend the existing layered system (see `data/provinces/SCHEMA.md`).

**New / Enhanced in `provinces_geometry.json` or a new `provinces_editor.json`:**
- `historical_variants`: array of year + delta (or full snapshot) for that province at different eras.
  Example:
  ```json
  "historical_variants": [
    {"year": 1918, "name": "Alsace-Lorraine", "owner_tag": "GER", ...},
    {"year": 1945, "name": "Rhineland", "special_features": ["demilitarized"]},
    {"year": 2026, "name": "European Union Admin Zone 3", "development_level": 9}
  ]
  ```

- `editor_notes`: string (designer comments, sources, "this border follows the 1937 river course").

- `modding_tags`: string[] (for scripts: "always_neutral", "high_vp_target", "alpine_fortification_zone").

This keeps the core runtime Province simple while giving huge flexibility for scenarios and mods.

---

## 6. Implementation Roadmap (Prioritized)

1. **Skeleton + Basic Drawing** (current task)
   - ProvinceEditor node
   - Basic point-click polygon creation + live Polygon2D preview in map space
   - Simple attribute panel (name + terrain)
   - Export to JSON (geometry + stub base)

2. **Integration with DebugOverlay**
   - Full section with toggle, tools, list of edited provinces, "Apply to Current Map (temp)", Export buttons.
   - Camera/zoom friendly (work in world coordinates).

3. **Smart Tools & Polish**
   - River/mountain snap suggestions (start with simple nearest-point on pre-defined lines if available, or manual "mark river" mode).
   - Vertex editing (select & drag points).
   - Merge / split existing provinces.
   - Bulk attribute application.

4. **Historical Variants UI**
   - Simple year-based variant editor.

5. **Basing + Gameplay Preview**
   - Drawn provinces immediately affect movement cost preview, supply throughput, etc. in tooltips.

6. **Roundtrip with Python Tools**
   - Make the output compatible with the existing generate_*.py pipeline so designer work can be fed into global map builds.

---

## 7. Open Questions
- How do we handle sea zones vs land provinces in the editor? (Separate "Draw Sea Zone" mode?)
- Performance: At 400+ provinces with live editing, do we need LOD or only show editor polys near camera?
- Multiplayer / mod sharing: Best format for sharing edited province sets?
- Undo stack for drawing operations.

---

This in-game editor, combined with the clean base map and historical variant system, will give the team (and future modders) an incredibly powerful and fun way to shape the world of Epochs of Ascendancy.

*End of Province Editor In-Game Design Document*