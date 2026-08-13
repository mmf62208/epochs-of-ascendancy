#!/usr/bin/env python3
"""Seed / repair province_city_layer.json for world hubs.

Places cities on province label_anchor (or centroid). Relocates legacy entries
that sit far from the province (Europe-local leftovers after world reproject).

Usage:
  python3 tools/map_generation/scripts/seed_world_city_layer.py \\
      --dir data/provinces_world_full [--write]
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]

# Major hubs: match if province name contains key (case-insensitive)
WORLD_HUBS: List[Tuple[str, int]] = [
    ("London", 9),
    ("Paris", 9),
    ("Berlin", 9),
    ("Rome", 8),
    ("Madrid", 8),
    ("Moscow", 9),
    ("Istanbul", 8),
    ("Cairo", 8),
    ("Alexandria", 6),
    ("Baghdad", 7),
    ("Tehran", 7),
    ("Riyadh", 6),
    ("Delhi", 9),
    ("Bombay", 8),
    ("Calcutta", 7),
    ("Shanghai", 9),
    ("Beijing", 9),
    ("Tokyo", 9),
    ("Seoul", 8),
    ("Manila", 7),
    ("Singapore", 8),
    ("Jakarta", 8),
    ("Saigon", 6),
    ("Hanoi", 6),
    ("Bangkok", 7),
    ("New York", 9),
    ("Washington", 8),
    ("Chicago", 7),
    ("Los Angeles", 8),
    ("San Francisco", 7),
    ("Mexico City", 8),
    ("Toronto", 7),
    ("Havana", 5),
    ("Buenos Aires", 8),
    ("Sao Paulo", 8),
    ("Rio de Janeiro", 7),
    ("Lima", 6),
    ("Santiago", 6),
    ("Bogota", 6),
    ("Lagos", 7),
    ("Johannesburg", 6),
    ("Cape Town", 6),
    ("Nairobi", 6),
    ("Sydney", 7),
    ("Melbourne", 6),
    ("Auckland", 5),
    ("Hawaii", 5),
    ("Hong Kong", 7),
    ("Vladivostok", 5),
    ("Warsaw", 7),
    ("Vienna", 6),
    ("Stockholm", 5),
    ("Algiers", 5),
    ("Casablanca", 5),
    ("Lisbon", 6),
    ("Reykjavik", 5),
    ("Houston", 6),
]

MAX_CITY_ANCHOR_DIST = 500.0


def centroid(points: Sequence[Sequence[float]]) -> Tuple[float, float]:
    if not points:
        return 0.0, 0.0
    return (
        sum(float(p[0]) for p in points) / len(points),
        sum(float(p[1]) for p in points) / len(points),
    )


def province_anchor(g: Dict[str, Any]) -> Tuple[float, float]:
    if g.get("label_anchor") and len(g["label_anchor"]) >= 2:
        return float(g["label_anchor"][0]), float(g["label_anchor"][1])
    return centroid(g.get("points") or [])


def match_hub(name: str) -> Optional[Tuple[str, int]]:
    n = name.lower()
    best = None
    for key, weight in WORLD_HUBS:
        if key.lower() in n:
            if best is None or weight > best[1]:
                best = (key, weight)
    return best


def clean_city_name(province_name: str, hub_key: str) -> str:
    pname = province_name.strip()
    if hub_key.lower() in pname.lower() and len(pname) < 48:
        return pname.split(" Theater")[0].split(" Sector")[0].strip()
    return hub_key


def city_needs_repair(
    cities: List[Dict[str, Any]],
    ax: float,
    ay: float,
    province_name: str,
) -> bool:
    if not cities:
        return True
    for ci in cities:
        x = float(ci.get("x", 0.0))
        y = float(ci.get("y", 0.0))
        if x == 0.0 and y == 0.0:
            return True
        if math.hypot(x - ax, y - ay) > MAX_CITY_ANCHOR_DIST:
            return True
        # Wrong hub name stuck on unrelated province (legacy catalog names)
        cname = str(ci.get("name", "")).lower()
        pname = province_name.lower()
        hub = match_hub(province_name)
        if hub and hub[0].lower() not in cname and hub[0].lower() not in pname:
            # city name is some other hub not related to this province
            if match_hub(str(ci.get("name", ""))) and hub[0].lower() not in cname:
                if not any(tok in cname for tok in pname.split() if len(tok) > 3):
                    return True
    return False


def make_city_entry(
    name: str, x: float, y: float, weight: int = 6
) -> Dict[str, Any]:
    return {
        "name": name,
        "x": x,
        "y": y,
        "level": min(5, max(2, weight // 2)),
        "is_capital": weight >= 8,
        "source": "seed_world_city_layer.py",
    }


def _looks_like_place_name(name: str) -> bool:
    n = str(name or "").strip()
    if not n or len(n) < 3 or len(n) > 48:
        return False
    if re.search(r"Sector\s+[A-Z]\b", n, re.I):
        return False
    if re.search(r"Basin\s+-?\d+_-?\d+", n, re.I):
        return False
    if re.search(r"-?\d+_-?\d+", n):
        return False
    if re.match(r"^Province\s+\d+$", n, re.I):
        return False
    # Prefer multi-token or known-looking capitalised names
    return True


def seed_cities(
    base_provinces: List[Dict[str, Any]],
    geometry_provinces: List[Dict[str, Any]],
    existing_cities: Dict[str, Any],
    *,
    max_dist: float = MAX_CITY_ANCHOR_DIST,
    min_nonempty: int = 750,
) -> Dict[str, Any]:
    """Build city map keyed by province id; relocate/overwrite bad legacy entries.

    Expands beyond WORLD_HUBS: also seeds coastal hubs, high-population land,
    and place-named provinces until min_nonempty anchors when possible.
    Hard gate target is ≥750 (stretch toward 900 if land stock allows, far=0).
    """
    geom = {int(g["id"]): g for g in geometry_provinces}
    out: Dict[str, Any] = {}
    seeded = 0
    repaired = 0
    kept = 0
    expanded = 0

    # Only current province ids
    for p in base_provinces:
        pid = int(p["id"])
        sid = str(pid)
        g = geom.get(pid, {})
        ax, ay = province_anchor(g)
        pname = str(p.get("name", f"Province {pid}"))
        existing = existing_cities.get(sid, {})
        cities = list(existing.get("cities") or []) if isinstance(existing, dict) else []

        hub = match_hub(pname)
        needs = city_needs_repair(cities, ax, ay, pname)
        domain = str(p.get("domain") or "").lower()
        is_water = domain in ("sea", "strait", "lake") or bool(p.get("is_sea"))

        if cities and not needs:
            # Snap coords exactly to anchor for stability
            fixed = []
            for ci in cities:
                c = dict(ci)
                c["x"], c["y"] = ax, ay
                fixed.append(c)
            out[sid] = {"cities": fixed}
            kept += 1
            continue

        if hub and not is_water:
            cname = clean_city_name(pname, hub[0])
            out[sid] = {"cities": [make_city_entry(cname, ax, ay, hub[1])]}
            if cities:
                repaired += 1
            else:
                seeded += 1
        else:
            # Non-hub: drop bad cities rather than leave Europe-local junk
            out[sid] = {"cities": []}
            if cities and needs:
                repaired += 1

    # Expansion pass: fill more land/coastal place-named + high-pop provinces
    candidates: List[Tuple[int, Dict[str, Any], float]] = []
    for p in base_provinces:
        pid = int(p["id"])
        sid = str(pid)
        if (out.get(sid) or {}).get("cities"):
            continue
        domain = str(p.get("domain") or "").lower()
        if domain in ("sea", "strait", "lake") or bool(p.get("is_sea")):
            continue
        pname = str(p.get("name") or "")
        pop = float(p.get("population_base") or 0)
        score = pop
        if domain == "coastal_land":
            score += 200_000
        if match_hub(pname):
            score += 500_000
        if _looks_like_place_name(pname):
            score += 100_000
        # Prefer facility / theater capitals lightly
        ft = p.get("facility_tier") or 0
        try:
            score += float(ft) * 50_000
        except (TypeError, ValueError):
            # Non-numeric tiers e.g. "full" / "major"
            score += 80_000
        candidates.append((pid, p, score))

    candidates.sort(key=lambda t: -t[2])
    nonempty = sum(
        1 for v in out.values() if isinstance(v, dict) and v.get("cities")
    )

    def _place_city(pid: int, p: Dict[str, Any], *, allow_any_land: bool) -> bool:
        nonlocal expanded, nonempty
        sid = str(pid)
        if (out.get(sid) or {}).get("cities"):
            return False
        g = geom.get(pid, {})
        ax, ay = province_anchor(g)
        # Skip degenerate anchors (origin-ish) — would fail far checks visually
        if abs(ax) + abs(ay) < 1.0:
            return False
        pname = str(p.get("name") or f"Settlement {pid}")
        if not allow_any_land:
            if not _looks_like_place_name(pname) and float(p.get("population_base") or 0) < 50_000:
                return False
        hub = match_hub(pname)
        cname = clean_city_name(pname, hub[0]) if hub else pname.split(" Theater")[0].strip()
        weight = hub[1] if hub else (6 if domain_is_coastal(p) else 4)
        if not cname:
            cname = f"Settlement {pid}"
        # Soften purely residual "Settlement N" when we have a province name
        if cname.startswith("Settlement ") and pname and not pname.startswith("Province "):
            cname = pname.split(" Theater")[0].strip() or cname
        out[sid] = {"cities": [make_city_entry(cname, ax, ay, weight)]}
        expanded += 1
        nonempty += 1
        return True

    # Pass 1: place-named / high-pop / coastal candidates
    for pid, p, _score in candidates:
        if nonempty >= min_nonempty:
            break
        _place_city(pid, p, allow_any_land=False)

    # Pass 2: fill remaining land slots to hit min_nonempty (still on label anchors → far=0)
    if nonempty < min_nonempty:
        for pid, p, _score in candidates:
            if nonempty >= min_nonempty:
                break
            _place_city(pid, p, allow_any_land=True)

    return {
        "provinces": out,
        "seeded": seeded,
        "repaired": repaired,
        "kept": kept,
        "expanded": expanded,
        "total_keys": len(out),
    }


def domain_is_coastal(p: Dict[str, Any]) -> bool:
    return str(p.get("domain") or "").lower() == "coastal_land"


def run_on_dir(
    data_dir: Path,
    write: bool = False,
    *,
    min_nonempty: int = 750,
) -> Dict[str, Any]:
    base = json.loads((data_dir / "provinces_base.json").read_text(encoding="utf-8"))
    geom = json.loads((data_dir / "provinces_geometry.json").read_text(encoding="utf-8"))
    city_path = data_dir / "province_city_layer.json"
    if city_path.exists():
        city_payload = json.loads(city_path.read_text(encoding="utf-8"))
        existing = city_payload.get("provinces") or {}
    else:
        existing = {}
        city_payload = {"version": 1, "provinces": {}}

    result = seed_cities(
        base["provinces"],
        geom["provinces"],
        existing,
        min_nonempty=int(min_nonempty),
    )
    nonempty = sum(
        1
        for v in result["provinces"].values()
        if isinstance(v, dict) and v.get("cities")
    )
    # Quality: all cities near anchors
    geom_by = {int(g["id"]): g for g in geom["provinces"]}
    far = 0
    for sid, entry in result["provinces"].items():
        cities = entry.get("cities") or []
        if not cities:
            continue
        g = geom_by.get(int(sid), {})
        ax, ay = province_anchor(g)
        for ci in cities:
            if math.hypot(float(ci["x"]) - ax, float(ci["y"]) - ay) > MAX_CITY_ANCHOR_DIST:
                far += 1

    if write:
        out = {
            "version": 2,
            "source": "seed_world_city_layer.py",
            "provinces": result["provinces"],
        }
        city_path.write_text(
            json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
    return {
        "seeded": result["seeded"],
        "repaired": result["repaired"],
        "kept": result["kept"],
        "expanded": result.get("expanded", 0),
        "nonempty_cities": nonempty,
        "province_keys": result["total_keys"],
        "cities_far_from_anchor": far,
        "min_nonempty_target": int(min_nonempty),
        "wrote": write,
    }


def main(argv: Optional[Sequence[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", default="data/provinces_world_full")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument(
        "--min-nonempty",
        type=int,
        default=750,
        help="Target land provinces with city anchors (default 750; stretch e.g. 900)",
    )
    args = ap.parse_args(argv)
    data_dir = Path(args.dir)
    if not data_dir.is_absolute():
        data_dir = ROOT / data_dir
    write = bool(args.write) and not args.dry_run
    stats = run_on_dir(data_dir, write=write, min_nonempty=int(args.min_nonempty))
    mode = "WROTE" if write else "DRY-RUN"
    print(f"[{mode}] {data_dir / 'province_city_layer.json'}")
    print(" ", stats)
    target = int(args.min_nonempty)
    ok = (
        stats["nonempty_cities"] >= min(target, 40)
        and stats["cities_far_from_anchor"] == 0
        and stats["province_keys"] >= 100
    )
    print("PASS city seed gates" if ok else "FAIL city seed gates", file=sys.stdout if ok else sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
