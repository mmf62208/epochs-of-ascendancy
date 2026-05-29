# Map Generation Pipeline – Tools

This folder contains the tools and scripts used to generate and refine province data for *Epochs of Ascendancy*.

## Current Status (as of this commit)

- Phase 1 design document exists in `docs/MAP_GENERATION_PIPELINE_DESIGN.md`
- Main driver: `scripts/generate_europe_phase1.py`
- Shared logic modules (in `lib/`):
  - `naval_analysis.py` — Strait protection, coastal detection, island groups, naval importance scoring
  - `subdivision_utils.py` — Naval-aware subdivision ranking and splitting heuristics
- Europe-focused configuration: `config/europe_phase1.yaml`

## Goals for Phase 1 (Europe)

- Expand from current ~100 placeholder provinces to 350–450 high-quality provinces.
- Give strong attention to naval geography (coastlines, major straits, islands, sea access).
- Produce data that works with the existing layered JSON system (`MapManager`, `Province`, `SpecialSiteManager`, overlays, etc.).

## How to Run (Early Stage)

```bash
cd tools/map_generation
python scripts/generate_europe_phase1.py
```

This currently produces a planning JSON with subdivision suggestions and protected straits.

## Next Development Steps

1. Load and analyze the full layered data (terrain, resources, cities, economy, adjacency).
2. Implement real subdivision heuristics that protect important naval features.
3. Generate improved geometry + attribute layers.
4. Add validation against the existing data schema.
5. Iterate with manual artistic overrides where needed.

## Relationship to Existing Code

All output must remain compatible with:
- `data/provinces/` layered JSON format
- `scripts/map/MapManager.gd`
- `scripts/data/Province.gd`
- `scripts/map/SpecialSiteManager.gd`
- Overlay layers (`InfrastructureOverlayLayer`, etc.)

Do not break the current data loading pipeline.

## Naval Emphasis

Because naval play is strategically important, the pipeline must treat:
- Major straits as high-value connections
- Coastal provinces with higher density potential
- Island groups with special handling
- Port potential and sea zone connectivity

This is reflected in the configuration and will be enforced in the subdivision logic.