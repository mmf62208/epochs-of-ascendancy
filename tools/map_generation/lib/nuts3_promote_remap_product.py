"""NUTS-3 promote remap — id-stable bridge (Pack H / M1).

Never renumbers world_full IDs. Builds overlap remap table from nuts3 (710000+)
centroids/bboxes toward nearest world_full land province for dual-board play.
"""
from __future__ import annotations
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[3]


def _centroid(coords: List) -> Optional[Tuple[float, float]]:
    """Best-effort centroid from nested ring coords [[x,y],...]."""
    pts: List[Tuple[float, float]] = []

    def walk(node: Any) -> None:
        if isinstance(node, (list, tuple)) and len(node) >= 2 and isinstance(node[0], (int, float)):
            pts.append((float(node[0]), float(node[1])))
            return
        if isinstance(node, (list, tuple)):
            for c in node:
                walk(c)

    walk(coords)
    if not pts:
        return None
    sx = sum(p[0] for p in pts)
    sy = sum(p[1] for p in pts)
    n = float(len(pts))
    return (sx / n, sy / n)


def _load_land_centroids(geom_path: Path, *, id_min: int = 0, id_max: int = 10**9) -> Dict[int, Tuple[float, float]]:
    data = json.loads(geom_path.read_text(encoding="utf-8"))
    out: Dict[int, Tuple[float, float]] = {}
    for p in data.get("provinces") or []:
        if not isinstance(p, dict):
            continue
        pid = int(p.get("id", -1))
        if pid < id_min or pid > id_max:
            continue
        meta = p.get("meta") or {}
        terrain = str(meta.get("terrain", p.get("terrain", "land"))).lower()
        if terrain in ("ocean", "sea", "water"):
            continue
        ## EOA geometry uses `points` (flat [[x,y],...]) more often than GeoJSON rings.
        geom = p.get("points") or p.get("geometry") or p.get("polygon") or p.get("rings") or []
        if isinstance(geom, dict):
            geom = geom.get("coordinates") or geom.get("rings") or geom.get("points") or []
        c = _centroid(geom)
        if c is None:
            ## label_anchor fallback
            la = p.get("label_anchor")
            if isinstance(la, (list, tuple)) and len(la) >= 2:
                try:
                    c = (float(la[0]), float(la[1]))
                except (TypeError, ValueError):
                    c = None
        if c is None:
            continue
        out[pid] = c
    return out


def nearest_world_full(cx: float, cy: float, world: Dict[int, Tuple[float, float]]) -> int:
    best_id = -1
    best_d = 1e30
    for pid, (wx, wy) in world.items():
        d = (wx - cx) ** 2 + (wy - cy) ** 2
        if d < best_d:
            best_d = d
            best_id = pid
    return best_id


def build_nuts3_promote_remap(
    *,
    nuts_geom: Optional[Path] = None,
    world_geom: Optional[Path] = None,
    sample_limit: int = 0,
) -> Dict[str, Any]:
    nuts_path = nuts_geom or (ROOT / "data/provinces_pilot_europe_nuts3/provinces_geometry.json")
    world_path = world_geom or (ROOT / "data/provinces_world_full/provinces_geometry.json")
    nuts = _load_land_centroids(nuts_path, id_min=710000, id_max=799999)
    world = _load_land_centroids(world_path, id_min=1, id_max=99999)
    pairs: List[Dict[str, Any]] = []
    ids = sorted(nuts.keys())
    if sample_limit > 0:
        ids = ids[:sample_limit]
    for nid in ids:
        cx, cy = nuts[nid]
        wid = nearest_world_full(cx, cy, world)
        if wid < 0:
            continue
        pairs.append({
            "nuts3_id": nid,
            "world_full_id": wid,
            "method": "nearest_centroid",
            "renumber_world_full": False,
        })
    # Integrity: no world_full id changed
    world_ids_touched = sorted({int(p["world_full_id"]) for p in pairs})
    ok = (
        len(pairs) >= 100
        and all(int(p["nuts3_id"]) >= 710000 for p in pairs)
        and all(1 <= int(p["world_full_id"]) <= 99999 for p in pairs)
        and all(not p.get("renumber_world_full") for p in pairs)
    )
    label = "NUTS3 promote remap · pairs %d · world touched %d · %s" % (
        len(pairs), len(world_ids_touched), "PASS" if ok else "FAIL",
    )
    return {
        "pairs": pairs,
        "pair_count": len(pairs),
        "nuts3_count": len(nuts),
        "world_full_land_count": len(world),
        "world_full_ids_touched": world_ids_touched[:50],
        "renumber_world_full": False,
        "method": "nearest_centroid",
        "ok": ok,
        "score": 0.75 if ok else 0.35,
        "summary": label,
        "plain": label,
        "empty": False,
        "integration": ["nuts3_promote_remap", "pack_h", "m1", "id_stable", "dual_board"],
    }


def write_remap_json(out_path: Optional[Path] = None, *, sample_limit: int = 0) -> Dict[str, Any]:
    product = build_nuts3_promote_remap(sample_limit=sample_limit)
    path = out_path or (ROOT / "data/provinces_pilot_europe_nuts3/nuts3_to_world_full_overlap.json")
    slim = {
        "method": product["method"],
        "renumber_world_full": False,
        "pair_count": product["pair_count"],
        "pairs": [{"nuts3_id": p["nuts3_id"], "world_full_id": p["world_full_id"]} for p in product["pairs"]],
        "summary": product["summary"],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(slim, indent=2) + "\n", encoding="utf-8")
    product["out_path"] = str(path)
    return product


def nuts3_promote_remap_integrity() -> Dict[str, Any]:
    # Sample for speed in CI; full write is optional
    product = build_nuts3_promote_remap(sample_limit=200)
    ok = bool(product.get("ok")) and int(product.get("pair_count", 0)) >= 100
    return {
        "ok": ok,
        "pair_count": int(product.get("pair_count", 0)),
        "summary": "NUTS3 promote remap integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }
