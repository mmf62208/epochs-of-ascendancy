#!/usr/bin/env python3
"""Replace regular hex/seed stubs with organic multi-lobe province shapes.

Targets hotspot_densify provinces and non-europe_core land seeds that still look
like geometric stubs. Preserves province ids, world-native meta, then densify.

Usage:
  python3 tools/map_generation/scripts/organicize_seed_geometry.py \\
      --dir data/provinces_world_full [--write]
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]

TARGET_THEATERS = {
    "far_east",
    "north_america",
    "south_america",
    "mena_africa",
    "africa",
    "central_asia",
    "oceania",
    "pacific",
    # Europe-core coastal stubs still benefit from organic lobes (not GIS coastlines)
    "europe_core",
}


def centroid(points: Sequence[Sequence[float]]) -> Tuple[float, float]:
    if not points:
        return 0.0, 0.0
    return (
        sum(float(p[0]) for p in points) / len(points),
        sum(float(p[1]) for p in points) / len(points),
    )


def mean_radius(points: Sequence[Sequence[float]], cx: float, cy: float) -> float:
    if not points:
        return 20.0
    return sum(math.hypot(float(p[0]) - cx, float(p[1]) - cy) for p in points) / len(points)


def is_stub_like(points: Sequence[Sequence[float]]) -> bool:
    """Detect densified hex/diamond stubs (few unique radii, regular spacing)."""
    n = len(points)
    if n < 6 or n > 20:
        return n <= 8  # very coarse always organicize
    cx, cy = centroid(points)
    radii = [math.hypot(float(p[0]) - cx, float(p[1]) - cy) for p in points]
    if not radii:
        return False
    r_mean = sum(radii) / len(radii)
    if r_mean < 1e-6:
        return True
    # Low radius variance => near-regular polygon
    var = sum((r - r_mean) ** 2 for r in radii) / len(radii)
    cv = math.sqrt(var) / r_mean
    return cv < 0.12  # regular hex densified still low CV


def organic_polygon(
    cx: float,
    cy: float,
    base_r: float,
    *,
    seed: int,
    n_points: int = 18,
) -> List[List[float]]:
    """Irregular coastal-ish ring: multi-frequency radial modulation."""
    # Deterministic pseudo-random from seed
    def rnd(i: int) -> float:
        x = math.sin(seed * 12.9898 + i * 78.233) * 43758.5453
        return x - math.floor(x)

    phase1 = rnd(1) * math.tau
    phase2 = rnd(2) * math.tau
    phase3 = rnd(3) * math.tau
    amp1 = 0.18 + 0.08 * rnd(4)
    amp2 = 0.10 + 0.06 * rnd(5)
    amp3 = 0.05 + 0.04 * rnd(6)
    # slight eccentricity
    sx = 0.92 + 0.16 * rnd(7)
    sy = 0.92 + 0.16 * rnd(8)

    pts: List[List[float]] = []
    for i in range(n_points):
        a = (i / n_points) * math.tau
        # multi-lobe coastline
        mod = (
            1.0
            + amp1 * math.sin(3.0 * a + phase1)
            + amp2 * math.sin(5.0 * a + phase2)
            + amp3 * math.sin(7.0 * a + phase3)
            + 0.04 * (rnd(10 + i) - 0.5)
        )
        r = base_r * max(0.55, mod)
        pts.append([cx + math.cos(a) * r * sx, cy + math.sin(a) * r * sy])
    return pts


def should_organicize(prov: Dict[str, Any], points: Sequence[Sequence[float]]) -> bool:
    domain = str(prov.get("domain") or "")
    if domain in ("sea", "strait", "lake"):
        return False
    if prov.get("hotspot_densify"):
        return True
    theater = str(prov.get("theater", ""))
    # Coastal land always organicize if still stub-like (naval feel)
    if domain == "coastal_land" and is_stub_like(points):
        return True
    if theater in TARGET_THEATERS and is_stub_like(points):
        return True
    # Seed expansion ids (20000+, 40000+, 50000+)
    pid = int(prov.get("id", 0))
    if pid >= 20000 and is_stub_like(points):
        return True
    return False


def organicize_geometry(
    base_provinces: List[Dict[str, Any]],
    geometry_provinces: List[Dict[str, Any]],
    *,
    n_points: int = 18,
) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    """Return new geometry list + stats. Pure transform."""
    by_base = {int(p["id"]): p for p in base_provinces}
    out: List[Dict[str, Any]] = []
    changed = 0
    skipped = 0
    for g in geometry_provinces:
        pid = int(g["id"])
        prov = by_base.get(pid, {})
        pts = g.get("points") or []
        entry = dict(g)
        if should_organicize(prov, pts):
            cx, cy = centroid(pts)
            if g.get("label_anchor") and len(g["label_anchor"]) >= 2:
                cx, cy = float(g["label_anchor"][0]), float(g["label_anchor"][1])
            br = mean_radius(pts, cx, cy)
            if br < 8.0:
                br = 22.0
            new_pts = organic_polygon(cx, cy, br, seed=pid * 17 + 3, n_points=n_points)
            entry["points"] = new_pts
            entry["label_anchor"] = [cx, cy]
            entry["organicized"] = True
            changed += 1
        else:
            skipped += 1
        out.append(entry)
    return out, {"changed": changed, "skipped": skipped, "total": len(out)}


def run_on_dir(data_dir: Path, write: bool = False) -> Dict[str, Any]:
    base_path = data_dir / "provinces_base.json"
    geom_path = data_dir / "provinces_geometry.json"
    base = json.loads(base_path.read_text(encoding="utf-8"))
    geom = json.loads(geom_path.read_text(encoding="utf-8"))
    new_geom, stats = organicize_geometry(base["provinces"], geom["provinces"])
    if not write:
        return {"wrote": False, **stats, "province_count": len(new_geom)}

    geom["provinces"] = new_geom
    meta = dict(geom.get("meta") or {})
    meta["organicized_seed_geometry"] = True
    meta["organicized_count"] = stats["changed"]
    meta["geometry_space"] = meta.get("geometry_space") or "world"
    meta["geometry_world_native"] = True
    geom["meta"] = meta
    geom_path.write_text(json.dumps(geom, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    # densify after reshape
    sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))
    from densify_province_geometry import run_on_dir as densify_dir

    dstat = densify_dir(data_dir, write=True, max_edge=14.0, min_vertices=16, max_vertices=72)
    # preserve organic flag after densify
    geom2 = json.loads(geom_path.read_text(encoding="utf-8"))
    gmeta = dict(geom2.get("meta") or {})
    gmeta["organicized_seed_geometry"] = True
    gmeta["organicized_count"] = stats["changed"]
    gmeta["geometry_space"] = "world"
    gmeta["geometry_world_native"] = True
    geom2["meta"] = gmeta
    geom_path.write_text(json.dumps(geom2, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    return {
        "wrote": True,
        **stats,
        "densify": dstat["after"],
        "province_count": len(new_geom),
    }


def main(argv: Optional[Sequence[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", default="data/provinces_world_full")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)
    data_dir = Path(args.dir)
    if not data_dir.is_absolute():
        data_dir = ROOT / data_dir
    write = bool(args.write) and not args.dry_run
    stats = run_on_dir(data_dir, write=write)
    print(("[WROTE]" if write else "[DRY-RUN]"), stats)
    ok = stats.get("changed", 0) >= 50
    if write:
        dens = stats.get("densify") or {}
        ok = ok and dens.get("triangles", 1) == 0 and dens.get("median", 0) >= 16
    print("PASS organicize" if ok else "FAIL organicize", file=sys.stdout if ok else sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
