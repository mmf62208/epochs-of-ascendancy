#!/usr/bin/env python3
"""Europe NUTS-3 pilot harden QC — names, hierarchy, adjacency, NE land hit.

Does not mutate data. Exit 0 if pilot meets gold-standard gates.

  python3 tools/map_generation/scripts/europe_nuts3_harden_qc.py
  python3 tools/map_generation/scripts/europe_nuts3_harden_qc.py --min-land-hit 0.85
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "scripts"))

# import sibling qc
from map_accuracy_qc import run_qc  # type: ignore  # noqa: E402
from ne_full_geometry_align import DEFAULT_NE_LAND  # noqa: E402

DEFAULT_DIR = ROOT / "data" / "provinces_pilot_europe_nuts3"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", default=str(DEFAULT_DIR))
    ap.add_argument("--min-land-hit", type=float, default=0.85)
    ap.add_argument("--json-out", default="")
    args = ap.parse_args(argv)

    data_dir = Path(args.dir)
    if not data_dir.is_absolute():
        data_dir = ROOT / data_dir
    if not data_dir.is_dir():
        print("ERROR: missing NUTS-3 dir", data_dir, file=sys.stderr)
        return 1

    report = run_qc(data_dir, ne_path=DEFAULT_NE_LAND if Path(DEFAULT_NE_LAND).is_file() else Path(DEFAULT_NE_LAND))
    errors = list(report.get("errors") or [])

    # Extra harden gates
    base = json.loads((data_dir / "provinces_base.json").read_text(encoding="utf-8"))
    rows = base.get("provinces") or []
    names = [str(p.get("name", "")).strip() for p in rows if isinstance(p, dict)]
    unique = len(set(names))
    empty = sum(1 for n in names if not n)
    report["unique_names"] = unique
    report["name_count"] = len(names)
    report["empty_names_strict"] = empty
    if empty > 0:
        errors.append(f"empty names: {empty}")
    if unique < len(names) * 0.98:
        errors.append(f"name uniqueness low: {unique}/{len(names)}")

    # Manifest honesty
    man_path = data_dir / "manifest_pilot_europe_nuts3.json"
    if man_path.is_file():
        man = json.loads(man_path.read_text(encoding="utf-8"))
        report["manifest_method"] = man.get("method") or (man.get("stats") or {}).get("method")
        report["gis_source"] = man.get("gis_source")
        if "nuts" not in str(report.get("manifest_method", "")).lower() and "eurostat" not in str(
            report.get("gis_source", "")
        ).lower():
            errors.append("manifest does not claim NUTS/Eurostat GIS")

    rate = report.get("ne_land_hit_rate")
    min_hit = float(args.min_land_hit)
    if rate is None:
        errors.append("NE land hit rate unavailable")
    elif rate < min_hit:
        errors.append(f"NE land hit {rate} < {min_hit}")

    if not report.get("ok_hard"):
        errors.append("hard orphan/poly gate failed")

    # Hierarchy + adjacency quality (shipped JSON, not reimplemented geometry)
    base_ids = {int(p["id"]) for p in rows if isinstance(p, dict) and "id" in p}
    mem_path = data_dir / "hierarchy_membership_1936.json"
    if mem_path.is_file():
        mem = json.loads(mem_path.read_text(encoding="utf-8"))
        p2r = mem.get("province_to_region", {}) if isinstance(mem, dict) else {}
        assigned = 0
        for pid in base_ids:
            rid = int(p2r.get(str(pid), p2r.get(pid, 0)) or 0)
            if rid > 0:
                assigned += 1
        report["province_region_assigned"] = assigned
        if assigned < len(base_ids):
            errors.append(f"province→region incomplete: {assigned}/{len(base_ids)}")
    else:
        errors.append("missing hierarchy_membership_1936.json")

    sr_path = data_dir / "strategic_regions.json"
    if sr_path.is_file():
        sr = json.loads(sr_path.read_text(encoding="utf-8"))
        regs = sr.get("regions", []) if isinstance(sr, dict) else []
        generic = 0
        for r in regs:
            if not isinstance(r, dict):
                continue
            n = str(r.get("name", "")).strip()
            if not n or n.startswith("Strategic Region "):
                generic += 1
        report["strategic_region_count"] = len(regs)
        report["generic_region_names"] = generic
        if generic > 0:
            errors.append(f"generic strategic region names: {generic}")
        if len(regs) < 5:
            errors.append(f"too few strategic regions: {len(regs)}")
    else:
        errors.append("missing strategic_regions.json")

    adj_path = data_dir / "province_adjacency.json"
    if adj_path.is_file():
        adj_doc = json.loads(adj_path.read_text(encoding="utf-8"))
        method = str(adj_doc.get("method", "")) if isinstance(adj_doc, dict) else ""
        adj_map = adj_doc.get("adjacency", adj_doc) if isinstance(adj_doc, dict) else {}
        if not isinstance(adj_map, dict):
            adj_map = {}
        adj_ids = set()
        zeros = 0
        for k, v in adj_map.items():
            if str(k).startswith("_"):
                continue
            try:
                adj_ids.add(int(k))
            except Exception:
                continue
            if isinstance(v, list):
                deg = len(v)
            elif isinstance(v, dict):
                deg = len(v.get("neighbors") or v.get("ids") or [])
            else:
                deg = 0
            if deg == 0:
                zeros += 1
        report["adjacency_method"] = method
        report["adjacency_ids"] = len(adj_ids)
        report["adjacency_cover"] = len(adj_ids & base_ids)
        report["adjacency_zero_degree"] = zeros
        report["adjacency_stats"] = adj_doc.get("stats") if isinstance(adj_doc, dict) else {}
        if "shared_edge" not in method and method not in ("shared_edge", "shared_edge_plus_knn_fallback"):
            # still accept if coverage full and zeros 0
            if len(adj_ids & base_ids) < len(base_ids):
                errors.append(f"adjacency method not shared-edge and incomplete: {method}")
        if len(adj_ids & base_ids) < len(base_ids):
            errors.append(
                f"adjacency incomplete: {len(adj_ids & base_ids)}/{len(base_ids)}"
            )
        if zeros > 0:
            errors.append(f"adjacency zero-degree provinces: {zeros}")
    else:
        errors.append("missing province_adjacency.json")

    own_path = data_dir / "province_ownership_1936.json"
    if own_path.is_file():
        own = json.loads(own_path.read_text(encoding="utf-8"))
        owners = own.get("owners", {}) if isinstance(own, dict) else {}
        owned = sum(1 for pid in base_ids if str(pid) in owners or pid in owners)
        report["ownership_1936_assigned"] = owned
        if owned < len(base_ids):
            errors.append(f"ownership incomplete: {owned}/{len(base_ids)}")
    else:
        report["warnings"] = list(report.get("warnings") or []) + ["no province_ownership_1936.json"]

    report["errors"] = errors
    report["ok_europe_gold"] = len(errors) == 0

    if args.json_out:
        out = Path(args.json_out)
        if not out.is_absolute():
            out = ROOT / out
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print("Wrote", out)

    print("EUROPE NUTS-3 HARDEN QC")
    print(f"  ok_europe_gold={report['ok_europe_gold']} matched={report.get('matched')}")
    print(f"  names unique={unique}/{len(names)} empty={empty}")
    print(f"  NE land hit={rate} (min {min_hit})")
    print(f"  method={report.get('manifest_method')} source={report.get('gis_source')}")
    for e in errors:
        print("  ERR:", e)
    return 0 if report["ok_europe_gold"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
