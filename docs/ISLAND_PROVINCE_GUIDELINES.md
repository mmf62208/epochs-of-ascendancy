# Island & Province Sizing Guidelines

Design reference for Epochs of Ascendancy map curation (aligned with Vic3, HOI4, EU4 conventions).

## Core rules

| Island scale | Province rule | Strategic region rule | Examples |
|---|---|---|---|
| **Micro** (Malta, Gozo, Åland) | **One province each** — never merge with mainland or distant islands | Group into nearest maritime macro (e.g. Western Mediterranean) | Malta solo; nearby micro-isles may share one province if touching |
| **Small cluster** (Hebrides, Cyclades, Balearics) | **One province per cluster** when islands are close and individually tiny | Same maritime region | Balearic chain → 1 prov; Hebrides → 1 prov |
| **Medium** (Corsica, Sardinia, Cyprus, Crete) | **2–4 provinces** by terrain/population chokepoints | Western Med / Greece & Aegean | Crete: Heraklion + Chania; Corsica: north/south |
| **Large** (Sicily, Ireland, Hokkaido-scale) | **4–8+ provinces** — treat like mini-mainlands | Dedicated or sub-regional split when UK-scale density arrives | Sicily: Palermo, Catania, Syracuse, Messina |
| **Archipelago nations** (UK, Japan, Philippines) | **Many provinces**; split by historical regions | **Multiple strategic regions** — never one blob | UK: 5 macro regions (see `strategic_regions.json`) |

## Canvas inflation (MapCanvasConfig)

- Global theater scale: `THEATER_SCALE` (currently 1.728×).
- Islands get extra centroid inflation: `ISLAND_EXTRA_SCALE` (+40%) and `ISLAND_TINY_EXTRA_SCALE` (+55%) for Malta-scale polygons so they remain clickable at operational zoom.

## UK macro split (current target)

When British Isles provinces are expanded, assign strategic regions as:

1. **Southern England** — London, Home Counties, south coast  
2. **Northern England & Midlands** — industrial north, Midlands corridor  
3. **Scotland** — Highlands, Central Belt  
4. **Wales** — western peninsula  
5. **Ireland** — island grouped as one strategic region; provinces remain separate (Republic + NI)

Regenerate assignments after adding provinces:

```bash
python3 tools/map_generation/build_curated_strategic_regions.py
```

## Map UX (operational zoom)

- **Region fill:** Vic3-style soft tint + thin border — **hovered region only** (`MapRegionHighlightLayer`).
- **Region label:** **cursor/hover only** — not all regions at once (`MapPoliticalLabelsLayer`).
- **Nation labels:** visible at strategic + operational zoom.
- **Province names:** tactical zoom only.

## References from major GS titles

- **Victoria 3:** Soft state/region tint at mid zoom; strategic regions for markets and migration.  
- **HOI4:** Strategic areas for supply hubs and AI planning; UK split into multiple areas.  
- **EU4:** Area → region hierarchy; islands often own province unless micro-cluster.

When in doubt: **gameplay readability beats geographic purity** — a province must be pickable, a region must read as a war-planning zone at operational zoom.
