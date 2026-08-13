#!/usr/bin/env python3
"""Backfill terrain / resources / economy layers for provinces_world_full.

- Terrain: every province id must appear (Europe core often only has base.terrain).
- Resources + economy: densified land (hotspot_densify) must have non-empty entries.
Preserves existing layer rows; only fills gaps.

Usage:
  python3 tools/map_generation/scripts/backfill_world_province_layers.py \\
      --dir data/provinces_world_full [--write]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]

# Theater → primary resource seeds (grand-strategy readable, not GIS-accurate).
THEATER_RESOURCES: Dict[str, List[Tuple[str, float]]] = {
    "europe_core": [("coal", 4.0), ("steel", 3.0), ("grain", 2.0)],
    "mena_africa": [("oil", 6.0), ("chromium", 2.0)],
    "far_east": [("coal", 4.0), ("rare_earths", 3.0), ("rubber", 2.0)],
    "north_america": [("oil", 4.0), ("steel", 3.0), ("grain", 3.0)],
    "south_america": [("rubber", 3.0), ("oil", 3.0), ("copper", 2.0)],
    "africa": [("chromium", 4.0), ("rubber", 3.0), ("oil", 2.0), ("gold", 2.0)],
    "central_asia": [("oil", 3.0), ("cotton", 2.0), ("uranium", 1.0)],
    "pacific": [("phosphate", 2.0), ("fish", 2.0)],
    "oceania": [("coal", 3.0), ("iron", 2.0), ("wool", 2.0)],
    "sea": [],
}

HUB_RESOURCE_HINTS: Dict[str, Tuple[str, float]] = {
    "Africa Nigeria Coast": ("oil", 7.0),
    "Africa Congo Basin": ("rubber", 6.0),
    "Africa Katanga": ("copper", 8.0),
    "Africa South Africa Highveld": ("gold", 7.0),
    "Africa Gold Coast": ("gold", 5.0),
    "Africa Angola Coast": ("oil", 6.0),
    "SE Asia Sumatra": ("oil", 5.0),
    "SE Asia Borneo": ("oil", 5.0),
    "SE Asia Malaya": ("rubber", 6.0),
    "SE Asia Burma Corridor": ("oil", 4.0),
    "China Manchuria": ("coal", 6.0),
    "China Sichuan Basin": ("coal", 4.0),
    "India Gangetic Plain": ("grain", 5.0),
    "USA Midwest Industrial": ("steel", 6.0),
    "USA Northeast Corridor": ("steel", 5.0),
    "SA Chile Central": ("copper", 7.0),
    "SA Venezuela Coast": ("oil", 7.0),
    "SA Peru Coast": ("copper", 4.0),
    "CA Kazakhstan Steppe": ("oil", 5.0),
    "CA Uzbekistan Oasis": ("cotton", 4.0),
    "CA Xinjiang West": ("oil", 4.0),
    "Oceania SE Australia": ("coal", 5.0),
    "Oceania Perth Coast": ("iron", 5.0),
    "Brazil Southeast": ("iron", 5.0),
    "Pacific Marianas": ("phosphate", 2.0),
}


def _hub_from_name(name: str) -> str:
    import re

    m = re.match(r"^(?P<hub>.+?)\s+\d+\s*$", str(name).strip())
    if m:
        return m.group("hub").strip()
    # After rename, match gazetteer reverse is hard; use name_source meta not available.
    return ""


def movement_cost_for_terrain(terrain: str) -> float:
    t = (terrain or "plains").lower()
    return {
        "plains": 1.0,
        "urban": 0.9,
        "forest": 1.3,
        "hills": 1.4,
        "mountain": 1.8,
        "mountains": 1.8,
        "desert": 1.5,
        "marsh": 1.6,
        "jungle": 1.7,
        "sea": 1.0,
        "ocean": 1.0,
    }.get(t, 1.1)


def make_terrain_entry(prov: Dict[str, Any]) -> Dict[str, Any]:
    domain = str(prov.get("domain") or "land")
    terrain = str(prov.get("terrain") or ("sea" if domain in ("sea", "strait", "lake") else "plains"))
    return {
        "terrain": terrain,
        "movement_cost": movement_cost_for_terrain(terrain),
        "source": "backfill_world_province_layers",
        "domain": domain,
        "facility_tier": prov.get("facility_tier") or ("none" if domain == "sea" else "full"),
        "island_class": prov.get("island_class") or ("none" if domain == "sea" else "mainland"),
    }


def pick_resource(prov: Dict[str, Any], index: int = 0) -> Dict[str, Any]:
    domain = str(prov.get("domain") or "land")
    if domain in ("sea", "strait", "lake"):
        return {"resources": {}, "resource_score": 0.0, "primary_resource": ""}

    name = str(prov.get("name") or "")
    theater = str(prov.get("theater") or "")
    hub = str(prov.get("hotspot_hub") or "") or _hub_from_name(name)

    primary = ""
    amount = 3.0
    if hub and hub in HUB_RESOURCE_HINTS:
        primary, amount = HUB_RESOURCE_HINTS[hub]
    else:
        for key, (res, amt) in HUB_RESOURCE_HINTS.items():
            token = key.split()[-1].lower()
            if token and token in name.lower():
                primary, amount = res, amt
                break
        if not primary:
            pool = THEATER_RESOURCES.get(theater) or [("grain", 2.0)]
            primary, amount = pool[index % len(pool)]

    # Slight variation by id for diversity
    pid = int(prov.get("id") or 0)
    amount = round(amount + (pid % 5) * 0.2, 1)
    return {
        "resources": {primary: amount},
        "resource_score": float(amount),
        "primary_resource": primary,
    }


def make_economy_entry(prov: Dict[str, Any], res_entry: Dict[str, Any]) -> Dict[str, Any]:
    domain = str(prov.get("domain") or "land")
    pop_base = int(prov.get("population_base") or 0)
    if pop_base <= 0:
        pop_base = 250000 if domain not in ("sea", "strait", "lake") else 0
    resources = dict(res_entry.get("resources") or {})
    score = float(res_entry.get("resource_score") or 0.0)
    if domain in ("sea", "strait", "lake"):
        return {
            "population": 0,
            "factories": 0,
            "infrastructure": 0,
            "development_level": 0.0,
            "resources": {},
        }
    factories = 1 if score >= 4.0 else 0
    if prov.get("hotspot_densify"):
        factories = max(factories, 1 if score >= 5.0 else 0)
    infra = 2 if score >= 3.0 else 1
    dev = round(1.5 + min(score, 8.0) * 0.25, 2)
    return {
        "population": pop_base,
        "factories": factories,
        "infrastructure": infra,
        "development_level": dev,
        "resources": resources,
    }


def entry_nonempty_resources(entry: Any) -> bool:
    if not isinstance(entry, dict):
        return False
    resources = entry.get("resources")
    if isinstance(resources, dict) and resources:
        return True
    # Some legacy entries may only have primary_resource
    return bool(entry.get("primary_resource"))


def entry_nonempty_economy(entry: Any) -> bool:
    if not isinstance(entry, dict):
        return False
    if int(entry.get("population") or 0) > 0:
        return True
    if int(entry.get("factories") or 0) > 0:
        return True
    if float(entry.get("development_level") or 0.0) > 0:
        return True
    resources = entry.get("resources")
    return isinstance(resources, dict) and bool(resources)


def backfill_layers(
    provinces: List[Dict[str, Any]],
    terrain: Dict[str, Any],
    resources: Dict[str, Any],
    economy: Dict[str, Any],
) -> Dict[str, Any]:
    terr_added = 0
    res_added = 0
    econ_added = 0

    for i, p in enumerate(provinces):
        sid = str(p["id"])
        if sid not in terrain or not isinstance(terrain.get(sid), dict):
            terrain[sid] = make_terrain_entry(p)
            terr_added += 1

        is_hot_land = bool(p.get("hotspot_densify")) and str(p.get("domain") or "land") not in (
            "sea",
            "strait",
            "lake",
        )
        if is_hot_land:
            if not entry_nonempty_resources(resources.get(sid)):
                resources[sid] = pick_resource(p, index=i)
                res_added += 1
            if not entry_nonempty_economy(economy.get(sid)):
                res_e = resources.get(sid) if isinstance(resources.get(sid), dict) else pick_resource(p, i)
                economy[sid] = make_economy_entry(p, res_e)  # type: ignore[arg-type]
                econ_added += 1

    return {
        "terrain_added": terr_added,
        "resources_added": res_added,
        "economy_added": econ_added,
        "terrain_count": len(terrain),
        "resources_count": len(resources),
        "economy_count": len(economy),
        "province_count": len(provinces),
    }


def quality_gates(
    provinces: List[Dict[str, Any]],
    terrain: Dict[str, Any],
    resources: Dict[str, Any],
    economy: Dict[str, Any],
) -> Dict[str, Any]:
    ids = {str(p["id"]) for p in provinces}
    terr_ids = set(map(str, terrain.keys()))
    hot_land = [
        p
        for p in provinces
        if p.get("hotspot_densify") and str(p.get("domain") or "land") not in ("sea", "strait", "lake")
    ]
    hot_missing_res = [
        str(p["id"]) for p in hot_land if not entry_nonempty_resources(resources.get(str(p["id"])))
    ]
    hot_missing_econ = [
        str(p["id"]) for p in hot_land if not entry_nonempty_economy(economy.get(str(p["id"])))
    ]
    sea = sum(1 for p in provinces if p.get("domain") in ("sea", "strait", "lake"))
    share = sea / max(1, len(provinces))
    return {
        "terrain_full_coverage": ids <= terr_ids and len(terr_ids) >= len(ids),
        "terrain_count": len(terr_ids),
        "province_count": len(ids),
        "hot_land_count": len(hot_land),
        "hot_missing_resources": len(hot_missing_res),
        "hot_missing_economy": len(hot_missing_econ),
        "sea_share": share,
        "sea_share_ok": 0.10 <= share <= 0.45,
    }


def run_on_dir(data_dir: Path, write: bool = False) -> Dict[str, Any]:
    base = json.loads((data_dir / "provinces_base.json").read_text(encoding="utf-8"))
    provinces = base["provinces"]
    terr_path = data_dir / "province_terrain_layer.json"
    res_path = data_dir / "province_resources_layer.json"
    econ_path = data_dir / "province_economy_layer.json"

    terr_doc = json.loads(terr_path.read_text(encoding="utf-8")) if terr_path.exists() else {"provinces": {}}
    res_doc = json.loads(res_path.read_text(encoding="utf-8")) if res_path.exists() else {"provinces": {}}
    econ_doc = json.loads(econ_path.read_text(encoding="utf-8")) if econ_path.exists() else {"provinces": {}}

    terrain = dict(terr_doc.get("provinces") or {})
    resources = dict(res_doc.get("provinces") or {})
    economy = dict(econ_doc.get("provinces") or {})

    stats = backfill_layers(provinces, terrain, resources, economy)
    gates = quality_gates(provinces, terrain, resources, economy)
    stats["gates"] = gates

    if not write:
        stats["wrote"] = False
        return stats

    terr_doc["provinces"] = terrain
    terr_doc["count"] = len(terrain)
    terr_doc["version"] = terr_doc.get("version") or 1
    terr_doc["source"] = "backfill_world_province_layers.py"

    res_doc["provinces"] = resources
    res_doc["version"] = res_doc.get("version") or 1

    econ_doc["provinces"] = economy
    econ_doc["version"] = econ_doc.get("version") or 1

    terr_path.write_text(json.dumps(terr_doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    res_path.write_text(json.dumps(res_doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    econ_path.write_text(json.dumps(econ_doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    meta = dict(base.get("meta") or {})
    meta["layers_backfilled"] = {
        "terrain_added": stats["terrain_added"],
        "resources_added": stats["resources_added"],
        "economy_added": stats["economy_added"],
    }
    base["meta"] = meta
    (data_dir / "provinces_base.json").write_text(
        json.dumps(base, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    stats["wrote"] = True
    return stats


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
    g = stats.get("gates") or {}
    ok = (
        g.get("terrain_full_coverage")
        and g.get("hot_missing_resources", 1) == 0
        and g.get("hot_missing_economy", 1) == 0
        and g.get("sea_share_ok")
    )
    print("PASS layer backfill" if ok else "FAIL layer backfill", file=sys.stdout if ok else sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
