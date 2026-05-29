#!/usr/bin/env python3
"""
Map Generation Pipeline - Phase 1: Europe Focus
================================================

Goal:
    Take the current ~100 province starter map (Europe + major powers focused)
    and intelligently expand/refine it toward 350-450 high-quality provinces
    with strong attention to naval geography (coastlines, straits, islands).

This is the first concrete script in the Map Generation Pipeline.

Current philosophy:
- Work with the existing layered JSON system (geometry + terrain + resources + economy + states + special sites)
- Start from the current playable 100-province set as the seed
- Use the larger 840-province base catalog as reference data where helpful
- Prioritize naval play from day one (straits, ports, sea access, island groups)

Usage (once more complete):
    python tools/map_generation/scripts/generate_europe_phase1.py --output tools/map_generation/output/phase1_europe

"""

import json
import os
from pathlib import Path
from typing import Dict, List, Any, Optional
import sys
from pathlib import Path

# Allow running this script directly while still importing from lib/
sys.path.append(str(Path(__file__).parent.parent))
from lib import naval_analysis, subdivision_utils

# =============================================================================
# CONFIGURATION
# =============================================================================

BASE_DIR = Path(__file__).parent.parent
# Data lives at the project root, not inside the tools folder
PROJECT_ROOT = BASE_DIR.parent.parent
DATA_DIR = PROJECT_ROOT / "data" / "provinces"
OUTPUT_DIR = BASE_DIR / "output" / "phase1_europe"

# Current playable geometry (our seed)
CURRENT_GEOMETRY = DATA_DIR / "provinces_geometry.json"

# Larger reference data (840 provinces)
BASE_PROVINCES = DATA_DIR / "provinces_base.json"
TERRAIN_LAYER = DATA_DIR / "province_terrain_layer.json"
RESOURCES_LAYER = DATA_DIR / "province_resources_layer.json"
ECONOMY_LAYER = DATA_DIR / "province_economy_layer.json"
CITY_LAYER = DATA_DIR / "province_city_layer.json"
ADJACENCY = DATA_DIR / "province_adjacency.json"
STRATEGIC_REGIONS = DATA_DIR / "strategic_regions.json"
PROJECT_SITES = DATA_DIR / "project_sites.json"

# =============================================================================
# DATA LOADING HELPERS
# =============================================================================

def load_json(path: Path) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def load_current_geometry() -> Dict[str, Any]:
    """Load the current ~100 province geometry we actually use in-game."""
    return load_json(CURRENT_GEOMETRY)

def load_base_data() -> Dict[str, Any]:
    """Load the fuller 840-province reference catalog."""
    return load_json(BASE_PROVINCES)

# =============================================================================
# REGION DEFINITION (Europe Focus)
# =============================================================================

def identify_europe_provinces(geometry: Dict[str, Any], base: Dict[str, Any]) -> List[int]:
    """
    Identify which provinces belong to the Europe theater for Phase 1.

    Current heuristic (can be greatly improved later):
    - Use the existing 100-province geometry as the core Europe set.
    - Later we can expand using strategic regions, bounding boxes, or manual lists.
    """
    # For now, treat all current geometry provinces as "Europe core"
    # In a real implementation we would cross-reference with strategic regions,
    # latitude/longitude if available, or a curated list of important provinces.
    europe_ids = [p["id"] for p in geometry.get("provinces", [])]
    print(f"Identified {len(europe_ids)} core Europe provinces from current geometry.")
    return europe_ids

# =============================================================================
# NAVAL / STRAIT AWARENESS (Critical for Phase 1)
# =============================================================================

# Hardcoded major straits for early protection during subdivision.
# These must remain as single, high-value connections or get special treatment.
MAJOR_STRAITS = {
    # (province_a, province_b): importance
    (42, 43): "English Channel",           # Placeholder IDs - replace with real ones later
    (120, 121): "Danish Straits",
    (250, 251): "Gibraltar",
    (310, 311): "Bosporus",
    # Add more as we identify real province IDs from the data
}

def protect_straits(adjacency: Dict[str, Any], europe_ids: List[int]) -> Dict[str, Any]:
    """
    Mark certain connections as 'strait' connections so subdivision logic
    treats them carefully (do not casually split the connection).

    Note: MAJOR_STRAITS currently contains placeholder IDs.
    Real IDs should be identified from the actual geometry + historical importance.
    """
    protected = {}
    adj = adjacency.get("adjacency", {})

    # For now we just document the concept. Real strait identification will happen
    # when we have better geographic data or manual tagging.
    print("Strait protection system initialized (placeholder logic).")
    print("Future: We will cross-reference real province IDs with major historical straits.")

    # Example of how real protection will look once we have proper IDs
    for (a, b), name in MAJOR_STRAITS.items():
        if a in europe_ids and b in europe_ids:
            protected[f"{min(a,b)}_{max(a,b)}"] = {
                "name": name,
                "protected": True,
                "reason": "Major naval strait - high strategic value"
            }

    print(f"Currently tracking {len(protected)} known major straits (will grow as we map real IDs).")
    return protected


# =============================================================================
# RICH OUTPUT + ATTRIBUTE HELPERS (Phase 1 improvements)
# =============================================================================

def _load_all_layers() -> Dict[str, Dict]:
    """Load every data layer we need for rich attribute inheritance and candidate generation."""
    return {
        "geometry": load_current_geometry(),
        "base": load_base_data(),
        "adjacency": load_json(ADJACENCY),
        "terrain": load_json(TERRAIN_LAYER),
        "resources": load_json(RESOURCES_LAYER),
        "economy": load_json(ECONOMY_LAYER),
        "cities": load_json(CITY_LAYER),
        "project_sites": load_json(PROJECT_SITES) if PROJECT_SITES.exists() else {},
    }


def _suggest_child_attributes(parent_id: int, layers: Dict) -> Dict:
    """
    High-quality attribute inheritance for a newly created child province.
    Pulls from the 840-province base catalog when available, then applies
    sensible Phase-1 mutations (smaller pop, split resources, slight terrain bias).
    """
    base = layers.get("base", {}).get("provinces", [])
    base_map = {p["id"]: p for p in base}

    parent = base_map.get(parent_id, {})
    terrain = parent.get("terrain", layers.get("terrain", {}).get("provinces", {}).get(str(parent_id), {}).get("terrain", "plains"))

    nat_res = parent.get("natural_resources", {})
    # Split resources across children (conservative)
    child_res = {k: max(1, int(v * 0.55)) for k, v in nat_res.items()} if nat_res else {}

    pop = int(parent.get("population_base", 450000) * 0.52)

    # Light coastal / naval bias for children of coastal parents
    special = list(parent.get("special_features", []))[:2]  # inherit a couple

    return {
        "terrain": terrain,
        "natural_resources": child_res,
        "population_base": pop,
        "special_features": special,
        "notes": "Phase 1 generated child — inherited + scaled from 840-province base catalog"
    }


def _generate_special_site_candidates(parent_id: int, child_id: str, layers: Dict, naval_data: Dict) -> List[Dict]:
    """
    Suggest plausible Special Site construction opportunities for a new child.
    Purely heuristic for Phase 1 (real construction will be player-driven later).
    """
    candidates = []
    is_coastal = parent_id in naval_data.get("coastal_provinces", [])
    is_choke = parent_id in naval_data.get("potential_chokepoints", [])

    if is_coastal:
        candidates.append({"type": "port", "tier": 1, "reason": "Coastal child province"})
    if is_choke or is_coastal:
        candidates.append({"type": "naval_base", "tier": 1, "reason": "Chokepoint or high naval value"})
    if is_coastal:
        candidates.append({"type": "airfield", "tier": 1, "reason": "Coastal air operations potential"})
    if is_choke:
        candidates.append({"type": "fortress", "tier": 1, "reason": "Strategic chokepoint defense"})
    return candidates


# =============================================================================
# SUBDIVISION LOGIC (Skeleton)
# =============================================================================

def suggest_subdivisions(
    europe_ids: List[int],
    geometry: Dict[str, Any],
    base_data: Dict[str, Any],
    protected_straits: Dict[str, Any]
) -> List[Dict[str, Any]]:
    """
    Very early skeleton for subdivision suggestions.

    Real logic will consider:
    - Province size (point count / area)
    - Resource density and variety
    - Terrain diversity
    - Population / development potential (from economy layer)
    - Naval importance (coastal, near straits, has port potential)
    - Historical / strategic value

    For now this just returns a placeholder list so we can build the pipeline skeleton.
    """
    suggestions = []

    # Example stub logic: flag very large provinces for potential split
    for p in geometry.get("provinces", []):
        pid = p["id"]
        if pid not in europe_ids:
            continue

        point_count = len(p.get("points", []))
        if point_count > 25:  # Arbitrary threshold for "large"
            suggestions.append({
                "original_id": pid,
                "suggested_splits": 2,   # or 3, 4 depending on size/resources
                "reason": "Large geometry - candidate for subdivision",
                "naval_priority": False  # Will be set true for coastal/strait provinces
            })

    print(f"Generated {len(suggestions)} subdivision suggestions (stub logic).")
    return suggestions

# =============================================================================
# MAIN PIPELINE
# =============================================================================

def run_phase1_europe(output_dir: Path):
    print("=== Epochs of Ascendancy - Phase 1 Europe Map Generation ===")
    print(f"Output directory: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)

    # Load all layers for rich inheritance + candidate generation
    print("\nLoading all data layers...")
    layers = _load_all_layers()
    geometry = layers["geometry"]
    base = layers["base"]
    adjacency = layers["adjacency"]

    base_provinces = {p["id"]: p for p in base.get("provinces", [])}
    print(f"  Current playable geometry: {len(geometry.get('provinces', []))} provinces")
    print(f"  840-province base catalog loaded: {len(base_provinces)} entries")

    # 1. Define Europe scope
    europe_ids = identify_europe_provinces(geometry, base)

    # 2. Run full naval analysis using the dedicated module
    print("\nRunning naval analysis (coastal + chokepoints + straits)...")
    naval_data = naval_analysis.analyze_naval_geography(
        data_dir=DATA_DIR,
        europe_ids=set(europe_ids)
    )

    print(f"  Coastal: {len(naval_data.get('coastal_provinces', []))} | "
          f"Chokepoints: {len(naval_data.get('potential_chokepoints', []))} | "
          f"Protected straits: {len(naval_data.get('protected_straits', {}))}")

    # 3. Analyze current connectivity
    adj_data = adjacency.get("adjacency", {})
    total_connections = sum(len(neighbors) for neighbors in adj_data.values()) // 2
    print(f"Current adjacency graph has {total_connections} undirected land connections.")

    europe_connections = 0
    for pid in europe_ids:
        for neighbor in adj_data.get(str(pid), []):
            if neighbor in europe_ids:
                europe_connections += 1
    europe_connections //= 2
    print(f"Of which ~{europe_connections} are internal to the current Europe seed set.")

    # 4. Use subdivision_utils to rank provinces for splitting (now using improved naval data)
    print("\nRanking provinces for subdivision (naval-weighted, relaxed for coarse seed)...")
    ranked = subdivision_utils.rank_provinces_for_subdivision(
        europe_ids, geometry, naval_data
    )

    suggestions = []
    split_proposals = []

    for pid, score in ranked[:40]:
        num_splits = subdivision_utils.suggest_number_of_splits(pid, geometry, naval_data)
        suggestions.append({
            "province_id": pid,
            "priority_score": round(score, 3),
            "suggested_splits": num_splits,
            "naval_importance": round(naval_data["naval_importance_scores"].get(pid, 0.0), 2),
            "is_coastal": pid in naval_data.get("coastal_provinces", []),
            "is_chokepoint": pid in naval_data.get("potential_chokepoints", [])
        })

        proposals = subdivision_utils.generate_split_geometry(
            pid, geometry, naval_data, num_splits
        )
        split_proposals.extend(proposals)

    print(f"  High-priority candidates: {len(suggestions)}")
    print(f"  Concrete child polygon proposals: {len(split_proposals)}")

    # Write a concrete example of what generated child provinces could look like
    example_new_provinces = []
    for proposal in split_proposals[:8]:
        attrs = _suggest_child_attributes(proposal["parent_id"], layers)
        example_new_provinces.append({
            "id": f"{proposal['parent_id']}_c{proposal['child_index']}",
            "parent_id": proposal["parent_id"],
            "points": proposal["suggested_points"],
            "center": proposal.get("suggested_center"),
            "suggested_attributes": attrs,
            "notes": proposal["notes"]
        })

    example_path = output_dir / "example_generated_children.json"
    with open(example_path, "w", encoding="utf-8") as f:
        json.dump({
            "phase": "1_europe",
            "generated_child_examples": example_new_provinces
        }, f, indent=2)
    print(f"Wrote concrete example of generated child provinces to: {example_path}")

    # 5. Build rich layered output for the top proposals (real Phase 1 deliverable)
    print("\nBuilding rich layered JSON output...")

    child_geometry = {
        "meta": {
            "phase": "1_europe",
            "source": "generated subdivision of current 100-province seed",
            "generated_at": "auto",
            "parent_geometry_version": geometry.get("meta", {}).get("version", 4)
        },
        "proposed_children": []
    }

    terrain_layer = {"version": 1, "provinces": {}}
    resources_layer = {"version": 1, "provinces": {}}
    economy_layer = {"version": 1, "provinces": {}}
    special_site_candidates = {"version": 1, "provinces": {}}

    parents_to_subdivide = set()

    for proposal in split_proposals:
        parent_id = proposal["parent_id"]
        parents_to_subdivide.add(parent_id)
        child_id = f"{parent_id}_c{proposal['child_index']}"

        attrs = _suggest_child_attributes(parent_id, layers)

        child_geometry["proposed_children"].append({
            "id": child_id,
            "parent_id": parent_id,
            "points": proposal["suggested_points"],
            "label_anchor": proposal.get("suggested_center", proposal["suggested_points"][0]),
            "suggested_center": proposal.get("suggested_center"),
            "approx_area": proposal.get("approx_area", 0)
        })

        # Terrain
        terrain_layer["provinces"][str(child_id)] = {
            "terrain": attrs.get("terrain", "plains"),
            "movement_cost": 1.0,
            "combat_modifier": 0.0,
            "notes": "Generated child — Phase 1"
        }

        # Resources (split from parent hints)
        res = attrs.get("natural_resources", {})
        if res:
            resources_layer["provinces"][str(child_id)] = {
                "resources": res,
                "resource_score": sum(res.values()),
                "primary_resource": max(res, key=res.get) if res else None
            }

        # Economy (scaled pop only for now)
        economy_layer["provinces"][str(child_id)] = {
            "population": attrs.get("population_base", 220000),
            "factories": 0,
            "infrastructure": 1,
            "development_level": 1,
            "notes": "Phase 1 generated child (pop scaled from base catalog)"
        }

        # Special site opportunities
        cands = _generate_special_site_candidates(parent_id, child_id, layers, naval_data)
        if cands:
            special_site_candidates["provinces"][str(child_id)] = {
                "candidates": cands,
                "parent_id": parent_id
            }

    # Write the rich layered outputs
    (output_dir / "proposed_children_geometry.json").write_text(
        json.dumps(child_geometry, indent=2), encoding="utf-8"
    )
    print(f"  Wrote proposed_children_geometry.json ({len(child_geometry['proposed_children'])} children)")

    (output_dir / "generated_terrain_phase1.json").write_text(
        json.dumps(terrain_layer, indent=2), encoding="utf-8"
    )
    print("  Wrote generated_terrain_phase1.json")

    if resources_layer["provinces"]:
        (output_dir / "generated_resources_phase1.json").write_text(
            json.dumps(resources_layer, indent=2), encoding="utf-8"
        )
        print("  Wrote generated_resources_phase1.json")

    (output_dir / "generated_economy_phase1.json").write_text(
        json.dumps(economy_layer, indent=2), encoding="utf-8"
    )
    print("  Wrote generated_economy_phase1.json")

    if special_site_candidates["provinces"]:
        (output_dir / "special_site_candidates_phase1.json").write_text(
            json.dumps(special_site_candidates, indent=2), encoding="utf-8"
        )
        print("  Wrote special_site_candidates_phase1.json")

    # 6. Merge / integration instructions (for future Godot-side or tooling validation)
    merge_plan = {
        "phase": "1_europe",
        "summary": f"Subdivide {len(parents_to_subdivide)} parents into {len(child_geometry['proposed_children'])} children",
        "parents_to_remove_or_replace": sorted(parents_to_subdivide),
        "new_child_ids": [c["id"] for c in child_geometry["proposed_children"]],
        "notes": [
            "These children are geometrically derived from the current coarse 6-point seed.",
            "Next step: visualize in Godot (InfrastructureOverlayLayer debug or new ProposedSplitOverlay).",
            "Adjacency, state, and strategic region updates will be required on integration.",
            "Special site candidates are only suggestions — player-driven construction is authoritative."
        ]
    }
    (output_dir / "merge_instructions_phase1.json").write_text(
        json.dumps(merge_plan, indent=2), encoding="utf-8"
    )
    print("  Wrote merge_instructions_phase1.json")

    # 7. Comprehensive plan / diagnostics file
    plan = {
        "phase": "1_europe",
        "target_province_count": "350-450",
        "seed_province_count": len(europe_ids),
        "naval_analysis": {
            "coastal": len(naval_data.get("coastal_provinces", [])),
            "chokepoints": len(naval_data.get("potential_chokepoints", [])),
            "protected_straits": len(naval_data.get("protected_straits", {})),
            "island_groups": len(naval_data.get("island_groups", {}))
        },
        "subdivision": {
            "candidates_ranked": len(suggestions),
            "children_proposed": len(split_proposals),
            "unique_parents_subdivided": len(parents_to_subdivide)
        },
        "high_priority_candidates": suggestions[:25],
        "top_naval_importance": [
            {"id": pid, "score": round(score, 2), "coastal": pid in naval_data.get("coastal_provinces", [])}
            for pid, score in sorted(naval_data.get("naval_importance_scores", {}).items(),
                                     key=lambda x: x[1], reverse=True)[:8]
        ],
        "output_files": [
            "proposed_children_geometry.json",
            "generated_terrain_phase1.json",
            "generated_resources_phase1.json",
            "generated_economy_phase1.json",
            "special_site_candidates_phase1.json",
            "merge_instructions_phase1.json",
            "phase1_europe_plan.json"
        ],
        "notes": [
            "Geometric splitting now uses densify + radial-arc + bisection for usable child polygons even from 6-pt input.",
            "Attribute inheritance pulls from the real 840-province base catalog.",
            "Next high-leverage work: Godot visualization of proposed splits + adjacency repair logic."
        ]
    }

    (output_dir / "phase1_europe_plan.json").write_text(json.dumps(plan, indent=2), encoding="utf-8")
    print(f"\nWrote updated phase1_europe_plan.json")

    # Console summary
    print("\n=== Phase 1 Run Complete ===")
    print(f"Parents selected for subdivision: {len(parents_to_subdivide)}")
    print(f"Total child proposals generated: {len(split_proposals)}")
    print("\nTop 6 naval importance provinces (from current seed):")
    for pid, score in sorted(naval_data.get("naval_importance_scores", {}).items(),
                             key=lambda x: x[1], reverse=True)[:6]:
        coastal = "coastal" if pid in naval_data.get("coastal_provinces", []) else ""
        print(f"  {pid}: {score:.2f} {coastal}")

    print("\nRecommended next actions:")
    print("  1. Inspect the new JSON layers in output/phase1_europe/")
    print("  2. Add a simple Godot debug overlay to render proposed_children_geometry.json")
    print("  3. Improve automatic strait/chokepoint discovery in naval_analysis.py")
    print("  4. Continue generating more naval-focused Special Site definitions")

if __name__ == "__main__":
    run_phase1_europe(OUTPUT_DIR)