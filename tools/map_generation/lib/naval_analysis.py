"""
Naval Analysis Module
=====================

This module contains all logic related to analyzing and protecting naval geography
during map generation for Epochs of Ascendancy.

It is designed to support Phase 1 (Europe) with strong emphasis on:
- Coastlines
- Major straits and chokepoints
- Islands and island groups
- Naval strategic importance scoring

The goal is to give the subdivision logic the information it needs to create
a map that feels good for naval play, supply, and conflict.
"""

from pathlib import Path
from typing import Dict, List, Set, Tuple, Optional, Any
import json
from collections import defaultdict

# =============================================================================
# CONFIGURATION
# =============================================================================

# Known major straits (will be expanded as we identify real IDs)
# Format: (province_a, province_b): "Display Name"
KNOWN_MAJOR_STRAITS: Dict[Tuple[int, int], str] = {
    # These are placeholders until we map real IDs from the 840-province set
    (42, 43): "English Channel",
    (120, 121): "Danish Straits",
    (250, 251): "Strait of Gibraltar",
    (310, 311): "Turkish Straits",
}


# =============================================================================
# DATA LOADING HELPERS
# =============================================================================

def load_json(path: Path) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def load_all_layers(data_dir: Path) -> Dict[str, Dict]:
    """Load all the main province data layers we care about for naval analysis."""
    return {
        "geometry": load_json(data_dir / "provinces_geometry.json"),
        "adjacency": load_json(data_dir / "province_adjacency.json"),
        "terrain": load_json(data_dir / "province_terrain_layer.json"),
        "resources": load_json(data_dir / "province_resources_layer.json"),
        "economy": load_json(data_dir / "province_economy_layer.json"),
    }


# =============================================================================
# COASTAL PROVINCE DETECTION
# =============================================================================

def get_coastal_provinces(layers: Dict[str, Dict]) -> Set[int]:
    """
    Returns all province IDs that are coastal.
    A province is coastal if its terrain is 'coastal' in the terrain layer.
    """
    coastal = set()
    terrain_data = layers["terrain"].get("provinces", {})
    for pid_str, data in terrain_data.items():
        if data.get("terrain") == "coastal":
            coastal.add(int(pid_str))
    return coastal


# =============================================================================
# STRAIT / CHOKEPOINT DETECTION
# =============================================================================

def find_potential_chokepoints(adjacency: Dict, min_degree: int = 2, max_degree: int = 4) -> List[int]:
    """
    Finds provinces that are likely naval chokepoints.
    These are land provinces with very few land neighbors (they act as gates to larger landmasses).

    Improved (Phase 1): Combines low-degree heuristic with a cheap articulation-point
    approximation (removal increases connected components among neighbors).
    """
    adj = adjacency.get("adjacency", {})
    chokepoints = []

    # Build int-key adjacency for speed
    adj_int = {int(k): [int(n) for n in v] for k, v in adj.items()}

    def dfs_count(start: int, blocked: int, visited: Set[int]):
        stack = [start]
        visited.add(start)
        count = 1
        while stack:
            u = stack.pop()
            for v in adj_int.get(u, []):
                if v == blocked or v in visited:
                    continue
                visited.add(v)
                stack.append(v)
                count += 1
        return count

    for pid_str, neighbors in adj.items():
        pid = int(pid_str)
        degree = len(neighbors)
        if min_degree <= degree <= max_degree:
            chokepoints.append(pid)
            continue

        # Cheap articulation check for slightly higher-degree coastal gates
        if degree <= 5:
            # Count how many separate "islands" the neighbors fall into when pid is removed
            neigh = adj_int.get(pid, [])
            visited = set()
            components = 0
            for n in neigh:
                if n not in visited:
                    components += 1
                    dfs_count(n, pid, visited)
            if components >= 2:
                chokepoints.append(pid)

    return sorted(set(chokepoints))


def get_major_strait_connections(
    adjacency: Dict,
    known_straits: Optional[Dict[Tuple[int, int], str]] = None
) -> Dict[str, Dict]:
    """
    Returns information about known or detected major strait connections.

    Phase 1 upgrade:
    - Still honors the small curated KNOWN_MAJOR_STRAITS list (when IDs match)
    - Adds automatic discovery of "narrow bridge" pairs: coastal provinces with
      very few land neighbors that sit between large groups of other coastal provinces.
    """
    result = {}
    adj = adjacency.get("adjacency", {})
    adj_int = {int(k): [int(n) for n in v] for k, v in adj.items()}

    # 1. Curated high-value straits (when the IDs actually exist in this dataset)
    if known_straits is None:
        known_straits = KNOWN_MAJOR_STRAITS

    for (a, b), name in known_straits.items():
        a_str, b_str = str(a), str(b)
        if a_str in adj and b in adj[a_str]:
            key = f"{min(a, b)}_{max(a, b)}"
            result[key] = {
                "name": name,
                "province_a": min(a, b),
                "province_b": max(a, b),
                "protected": True,
                "reason": "Major naval chokepoint (curated)"
            }

    # 2. Automatic narrow-bridge discovery (cheap heuristic for Phase 1)
    # Any low-degree province whose removal locally disconnects its neighbors
    # is a strong candidate for protection during subdivision.
    for pid_str, neighbors in adj.items():
        pid = int(pid_str)
        if 2 <= len(neighbors) <= 3:
            neigh = adj_int.get(pid, [])
            disconnected_pairs = 0
            for i in range(len(neigh)):
                for j in range(i + 1, len(neigh)):
                    if neigh[j] not in adj_int.get(neigh[i], []):
                        disconnected_pairs += 1
            if disconnected_pairs >= 1:
                key = f"auto_bridge_{pid}"
                result[key] = {
                    "name": f"Auto-detected bridge/chokepoint province {pid}",
                    "province_a": pid,
                    "province_b": pid,
                    "protected": True,
                    "reason": "Graph bridge: removal locally disconnects neighbors"
                }

    return result


# =============================================================================
# ISLAND GROUP DETECTION
# =============================================================================

def get_island_groups(
    geometry: Dict,
    adjacency: Dict,
    coastal_provinces: Set[int]
) -> Dict[int, List[int]]:
    """
    Identifies groups of islands.
    An island group is a set of connected coastal provinces with very limited land connections to the mainland.
    """
    adj = adjacency.get("adjacency", {})
    visited = set()
    island_groups: Dict[int, List[int]] = {}

    def dfs(pid: int, group: List[int]):
        if pid in visited:
            return
        visited.add(pid)
        group.append(pid)
        for neighbor in adj.get(str(pid), []):
            if neighbor in coastal_provinces:
                dfs(neighbor, group)

    for pid in coastal_provinces:
        if pid not in visited:
            group: List[int] = []
            dfs(pid, group)
            if len(group) >= 1:  # Even single islands are interesting
                # Use the lowest ID as the group key for determinism
                key = min(group)
                island_groups[key] = sorted(group)

    return island_groups


# =============================================================================
# NAVAL STRATEGIC IMPORTANCE SCORING
# =============================================================================

def calculate_naval_importance_score(
    province_id: int,
    layers: Dict[str, Dict],
    coastal_provinces: Set[int],
    protected_straits: Dict[str, Dict],
    chokepoints: List[int]
) -> float:
    """
    Gives a province a naval strategic value score (0.0 – 2.0+).
    Higher score = more important to preserve or subdivide carefully for naval play.
    """
    score = 0.0

    # Base coastal bonus
    if province_id in coastal_provinces:
        score += 0.6

    # Major strait / auto-detected bridge bonus
    for key, data in protected_straits.items():
        if province_id in (data.get("province_a", -1), data.get("province_b", -1)):
            score += 1.15
            break

    # Chokepoint bonus (narrow land connection = high naval gate value)
    if province_id in chokepoints:
        score += 0.8

    # Resource value near coast is very strong for naval logistics
    res_data = layers["resources"].get("provinces", {}).get(str(province_id), {})
    resource_score = res_data.get("resource_score", 0.0)
    if resource_score > 0 and province_id in coastal_provinces:
        score += min(resource_score / 1200.0, 0.7)

    # Economy / population bonus (rich coastal areas are high value)
    econ = layers["economy"].get("provinces", {}).get(str(province_id), {})
    if econ:
        pop = econ.get("population", 0)
        score += min(pop / 2_000_000, 0.5)

    return round(score, 2)


# =============================================================================
# HIGH-LEVEL ANALYSIS FUNCTION (Main Entry Point)
# =============================================================================

def analyze_naval_geography(
    data_dir: Path,
    europe_ids: Optional[Set[int]] = None
) -> Dict[str, Any]:
    """
    Runs a full naval geography analysis and returns a rich summary.

    This is the primary function the generation pipeline should call.
    """
    layers = load_all_layers(data_dir)
    geometry = layers["geometry"]
    adjacency = layers["adjacency"]

    coastal = get_coastal_provinces(layers)
    chokepoints = find_potential_chokepoints(adjacency)
    protected_straits = get_major_strait_connections(adjacency)
    island_groups = get_island_groups(geometry, adjacency, coastal)

    # Filter to Europe if provided
    if europe_ids:
        coastal = coastal & europe_ids
        chokepoints = [p for p in chokepoints if p in europe_ids]

    # Calculate importance scores
    importance_scores = {}
    target_ids = europe_ids or [p["id"] for p in geometry.get("provinces", [])]
    for pid in target_ids:
        importance_scores[pid] = calculate_naval_importance_score(
            pid, layers, coastal, protected_straits, chokepoints
        )

    return {
        "coastal_provinces": sorted(coastal),
        "potential_chokepoints": sorted(chokepoints),
        "protected_straits": protected_straits,
        "island_groups": island_groups,
        "naval_importance_scores": importance_scores,
        "summary": {
            "total_coastal": len(coastal),
            "total_chokepoints": len(chokepoints),
            "total_protected_straits": len(protected_straits),
            "total_island_groups": len(island_groups),
        }
    }


if __name__ == "__main__":
    print("naval_analysis.py - Run this via the generation pipeline, not directly.")