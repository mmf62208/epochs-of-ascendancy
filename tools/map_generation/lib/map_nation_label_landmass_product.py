"""Pure policy: nation label sits on capital's contiguous owned landmass center.

Mirrors MapPoliticalLabelsLayer._capital_landmass_centroid selection (BFS component + weighted mean).
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Set, Tuple

ROOT = Path(__file__).resolve().parents[3]
LABELS_GD = ROOT / "scripts" / "map" / "MapPoliticalLabelsLayer.gd"
MENU_GD = ROOT / "scripts" / "ui" / "MainMenu.gd"
MENU_TSCN = ROOT / "scenes" / "ui" / "MainMenu.tscn"


def capital_landmass_centroid(
    owned_pids: List[int],
    centroids: Dict[int, Tuple[float, float]],
    neighbors: Dict[int, List[int]],
    capital_id: int,
    weights: Dict[int, float] | None = None,
) -> Tuple[float, float] | None:
    """BFS from capital through owned neighbors; return weighted centroid of that component."""
    owned: Set[int] = set(owned_pids)
    if not owned:
        return None
    seed = capital_id if capital_id in owned else next(iter(owned))
    seen: Set[int] = {seed}
    q: List[int] = [seed]
    component: List[int] = []
    while q:
        cur = q.pop(0)
        component.append(cur)
        for nid in neighbors.get(cur, []):
            if nid in seen or nid not in owned:
                continue
            if nid not in centroids:
                continue
            seen.add(nid)
            q.append(nid)
    sx = sy = wsum = 0.0
    for pid in component:
        if pid not in centroids:
            continue
        w = 1.0
        if weights and pid in weights:
            w = max(1.0, float(weights[pid]))
        cx, cy = centroids[pid]
        sx += cx * w
        sy += cy * w
        wsum += w
    if wsum <= 0:
        return None
    return (sx / wsum, sy / wsum)


def build_map_nation_label_landmass_product() -> Dict[str, Any]:
    # Synthetic UK-like: capital on coast (London-like), bulk of mass inland/west.
    # Capital at (10, 0); main mass around (0, 0).
    owned = [1, 2, 3, 4, 5]
    centroids = {
        1: (10.0, 0.0),  # capital coastal pin
        2: (2.0, 0.0),
        3: (0.0, 1.0),
        4: (-1.0, 0.0),
        5: (0.0, -1.0),
    }
    neighbors = {
        1: [2],
        2: [1, 3, 4, 5],
        3: [2],
        4: [2],
        5: [2],
    }
    weights = {1: 1.0, 2: 5.0, 3: 5.0, 4: 5.0, 5: 5.0}
    c = capital_landmass_centroid(owned, centroids, neighbors, capital_id=1, weights=weights)
    passes: List[str] = []
    fails: List[str] = []
    if c is None:
        fails.append("no_centroid")
    else:
        # Must be pulled toward mass (x near 0), not stuck on capital pin x=10
        if c[0] < 5.0:
            passes.append("not_on_capital_pin_x=%.2f" % c[0])
        else:
            fails.append("still_on_capital_pin_x=%.2f" % c[0])
        if abs(c[1]) < 2.0:
            passes.append("mass_y_ok")
        else:
            fails.append("mass_y_bad")

    # Isolated overseas province should not pull capital landmass if not connected
    owned2 = [1, 2, 99]
    centroids2 = {1: (0.0, 0.0), 2: (1.0, 0.0), 99: (100.0, 100.0)}
    neighbors2 = {1: [2], 2: [1], 99: []}
    c2 = capital_landmass_centroid(owned2, centroids2, neighbors2, capital_id=1, weights=None)
    if c2 is not None and c2[0] < 50:
        passes.append("excludes_disconnected_colony")
    else:
        fails.append("included_disconnected_colony")

    gd = LABELS_GD.read_text(encoding="utf-8") if LABELS_GD.is_file() else ""
    menu = MENU_GD.read_text(encoding="utf-8") if MENU_GD.is_file() else ""
    tscn = MENU_TSCN.read_text(encoding="utf-8") if MENU_TSCN.is_file() else ""
    if "func _capital_landmass_centroid" in gd and "_capital_landmass_centroid(" in gd:
        passes.append("gd_landmass_fn")
    else:
        fails.append("missing_gd_landmass")
    if "extends CanvasLayer" in menu and "CanvasLayer" in tscn:
        passes.append("menu_canvas_layer")
    else:
        fails.append("menu_not_overlay")
    if "save_game_detailed" in menu or "_save_to_slot" in menu:
        passes.append("menu_save_path")
    else:
        fails.append("menu_no_save")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "centroid": c,
        "pass": passes,
        "fail": fails,
        "summary": "nation_label_landmass · %s" % ("PASS" if ok else "FAIL"),
    }
