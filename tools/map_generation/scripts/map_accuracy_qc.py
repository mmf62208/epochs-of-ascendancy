#!/usr/bin/env python3
"""Map accuracy QC for province data dirs (orphans, names, NE land-mask hit rate).

Uses Natural Earth 10m land (cached) when available. Geometry is assumed to live
on the EOA world canvas (8192×4096, lon -180..180 lat -56..83) for NE sampling.
Scaffold densify boards may score low; NUTS-3 / GIS pilots should score high.

Usage:
  python3 tools/map_generation/scripts/map_accuracy_qc.py \\
      --dir data/provinces_world_full
  python3 tools/map_generation/scripts/map_accuracy_qc.py \\
      --dir data/provinces_pilot_europe_nuts3 --min-land-hit 0.90
  python3 tools/map_generation/scripts/map_accuracy_qc.py \\
      --dir data/provinces_world_full --json-out tools/map_generation/output/qc_world_full.json

Exit codes:
  0  all hard gates pass (orphans=0, geometry present; NE hit ≥ --min-land-hit if set)
  1  hard failure (orphans, missing files, empty board)
  2  soft NE threshold miss (only when --min-land-hit > 0)
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

_NE_DEPS_INSTALL = (
    "python3 -m pip install --user -r tools/map_generation/requirements.txt"
)
try:
    import numpy  # noqa: F401
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False
try:
    from PIL import Image  # noqa: F401
    HAS_PILLOW = True
except ImportError:
    HAS_PILLOW = False

from ne_full_geometry_align import (  # noqa: E402
    DEFAULT_NE_LAND,
    WORLD_CANVAS,
    load_ne_land_features,
    polygon_centroid,
    rasterize_land_mask,
    sample_mask,
)


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _province_list(doc: Any) -> List[dict]:
    if isinstance(doc, dict) and isinstance(doc.get("provinces"), list):
        return [p for p in doc["provinces"] if isinstance(p, dict)]
    if isinstance(doc, list):
        return [p for p in doc if isinstance(p, dict)]
    return []


def _ids(rows: Sequence[dict]) -> set:
    out = set()
    for p in rows:
        if "id" in p:
            out.add(int(p["id"]))
    return out


def _centroid_of(p: dict) -> Optional[Tuple[float, float]]:
    anchor = p.get("label_anchor")
    if isinstance(anchor, (list, tuple)) and len(anchor) >= 2:
        return float(anchor[0]), float(anchor[1])
    pts = p.get("points") or []
    if len(pts) < 1:
        return None
    return polygon_centroid(pts)


def _terrain_of(base_by_id: Dict[int, dict], pid: int) -> str:
    b = base_by_id.get(pid) or {}
    return str(b.get("terrain", "")).strip().lower()


def _is_sea(terr: str, domain: str = "") -> bool:
    t = terr.lower()
    d = domain.lower()
    return t in ("sea", "ocean", "water", "lake") or d in ("sea", "ocean", "naval", "water")


def run_qc(
    data_dir: Path,
    *,
    ne_path: Path,
    mask_w: int = 2048,
    mask_h: int = 1024,
    sample_limit: int = 0,
) -> Dict[str, Any]:
    base_path = data_dir / "provinces_base.json"
    geo_path = data_dir / "provinces_geometry.json"
    mem_path = data_dir / "hierarchy_membership_1936.json"
    if not mem_path.is_file():
        # try any membership
        cands = sorted(data_dir.glob("hierarchy_membership_*.json"))
        mem_path = cands[0] if cands else mem_path

    report: Dict[str, Any] = {
        "data_dir": str(data_dir.relative_to(ROOT) if data_dir.is_relative_to(ROOT) else data_dir),
        "ok_hard": False,
        "ok_ne": None,
        "errors": [],
        "warnings": [],
    }

    if not base_path.is_file() or not geo_path.is_file():
        report["errors"].append("missing provinces_base.json or provinces_geometry.json")
        return report

    base_rows = _province_list(_load_json(base_path))
    geo_rows = _province_list(_load_json(geo_path))
    base_ids = _ids(base_rows)
    geo_ids = _ids(geo_rows)
    only_base = sorted(base_ids - geo_ids)
    only_geo = sorted(geo_ids - base_ids)
    matched = base_ids & geo_ids

    base_by = {int(p["id"]): p for p in base_rows if "id" in p}
    geo_by = {int(p["id"]): p for p in geo_rows if "id" in p}

    land = sea = empty_name = 0
    densify_style = 0
    for pid in matched:
        b = base_by[pid]
        terr = str(b.get("terrain", "")).lower()
        domain = str(b.get("domain", "")).lower()
        nm = str(b.get("name", "")).strip()
        if not nm or nm.lower().startswith("province "):
            empty_name += 1
        if any(m in nm for m in (" Reach", " Spur", " Basin", " Ridge", " Belt", " Corridor", " Interior", " Upland")):
            densify_style += 1
        if _is_sea(terr, domain):
            sea += 1
        else:
            land += 1

    region_assigned = 0
    if mem_path.is_file():
        mem = _load_json(mem_path)
        p2r = mem.get("province_to_region", {}) if isinstance(mem, dict) else {}
        for pid in matched:
            rid = int(p2r.get(str(pid), p2r.get(pid, 0)) or 0)
            if rid > 0:
                region_assigned += 1

    report.update(
        {
            "total_base": len(base_ids),
            "total_geometry": len(geo_ids),
            "matched": len(matched),
            "orphan_base_only_count": len(only_base),
            "orphan_geo_only_count": len(only_geo),
            "orphan_base_sample": only_base[:20],
            "orphan_geo_sample": only_geo[:20],
            "land": land,
            "sea": sea,
            "empty_or_placeholder_names": empty_name,
            "densify_style_names": densify_style,
            "region_assigned": region_assigned,
            "region_assigned_pct": round(100.0 * region_assigned / max(1, len(matched)), 2),
        }
    )

    hard_ok = (
        len(matched) > 0
        and len(only_base) == 0
        and len(only_geo) == 0
        and all(len((geo_by[pid].get("points") or [])) >= 3 for pid in list(matched)[: min(500, len(matched))])
    )
    # full polygon check
    no_poly = sum(1 for pid in matched if len((geo_by[pid].get("points") or [])) < 3)
    report["geometry_no_polygon"] = no_poly
    hard_ok = hard_ok and no_poly == 0
    report["ok_hard"] = hard_ok
    if not hard_ok:
        report["errors"].append("hard coverage failed (orphans or empty board or missing polys)")

    # NE land mask for land centroids
    ne_hit = ne_total = 0
    ne_miss_samples: List[dict] = []
    if ne_path.is_file():
        try:
            rings = load_ne_land_features(ne_path)
            mask = rasterize_land_mask(rings, width=mask_w, height=mask_h)
            land_pids = [
                pid
                for pid in sorted(matched)
                if not _is_sea(
                    _terrain_of(base_by, pid),
                    str((base_by.get(pid) or {}).get("domain", "")),
                )
            ]
            if sample_limit > 0:
                land_pids = land_pids[:sample_limit]
            cw, ch = WORLD_CANVAS
            for pid in land_pids:
                c = _centroid_of(geo_by[pid])
                if c is None:
                    continue
                x, y = c
                # skip centroids wildly outside world canvas (densify packing residue)
                if x < -cw * 0.1 or x > cw * 1.1 or y < -ch * 0.1 or y > ch * 1.1:
                    continue
                ne_total += 1
                if sample_mask(mask, x, y):
                    ne_hit += 1
                elif len(ne_miss_samples) < 12:
                    ne_miss_samples.append(
                        {
                            "id": pid,
                            "name": str((base_by.get(pid) or {}).get("name", "")),
                            "centroid": [round(x, 2), round(y, 2)],
                        }
                    )
            report["ne_land_path"] = str(ne_path)
            report["ne_land_centroids_tested"] = ne_total
            report["ne_land_centroids_hit"] = ne_hit
            report["ne_land_hit_rate"] = round(ne_hit / max(1, ne_total), 4)
            report["ne_land_miss_samples"] = ne_miss_samples
            if ne_total < max(10, land // 20):
                report["warnings"].append(
                    "few centroids sampled against NE mask — geometry may not be on world canvas"
                )
        except Exception as exc:  # pragma: no cover
            report["warnings"].append(f"NE mask failed: {exc}")
            report["ne_land_hit_rate"] = None
    else:
        report["warnings"].append(f"NE land missing: {ne_path}")
        report["ne_land_hit_rate"] = None

    return report


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", default="data/provinces_world_full")
    ap.add_argument("--ne-land", default=str(DEFAULT_NE_LAND))
    ap.add_argument("--mask-width", type=int, default=2048)
    ap.add_argument("--mask-height", type=int, default=1024)
    ap.add_argument("--sample-limit", type=int, default=0, help="0 = all land")
    ap.add_argument(
        "--min-land-hit",
        type=float,
        default=0.0,
        help="If >0, require ne_land_hit_rate ≥ this (GIS boards e.g. 0.90)",
    )
    ap.add_argument("--json-out", default="", help="Write full report JSON")
    args = ap.parse_args(argv)

    if not HAS_NUMPY or not HAS_PILLOW:
        missing = []
        if not HAS_NUMPY:
            missing.append("numpy")
        if not HAS_PILLOW:
            missing.append("Pillow")
        print(
            "FAIL: %s required for map_accuracy_qc (NE land-mask)."
            % " and ".join(missing)
        )
        print(f"  {_NE_DEPS_INSTALL}")
        return 1

    data_dir = Path(args.dir)
    if not data_dir.is_absolute():
        data_dir = ROOT / data_dir
    ne_path = Path(args.ne_land)
    if not ne_path.is_absolute():
        ne_path = ROOT / ne_path

    report = run_qc(
        data_dir,
        ne_path=ne_path,
        mask_w=args.mask_width,
        mask_h=args.mask_height,
        sample_limit=args.sample_limit,
    )

    rate = report.get("ne_land_hit_rate")
    min_hit = float(args.min_land_hit)
    if min_hit > 0 and rate is not None:
        report["ok_ne"] = rate >= min_hit
        if not report["ok_ne"]:
            report["errors"].append(
                f"NE land hit rate {rate} < min {min_hit}"
            )
    elif min_hit > 0 and rate is None:
        report["ok_ne"] = False
        report["errors"].append("NE land hit rate unavailable but --min-land-hit set")
    else:
        report["ok_ne"] = True  # not gated

    out = args.json_out.strip()
    if out:
        out_path = Path(out)
        if not out_path.is_absolute():
            out_path = ROOT / out_path
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print("Wrote", out_path)

    # human summary
    print("MAP ACCURACY QC:", report.get("data_dir"))
    print(
        f"  hard_ok={report.get('ok_hard')} matched={report.get('matched')} "
        f"orphans_base={report.get('orphan_base_only_count')} orphans_geo={report.get('orphan_geo_only_count')}"
    )
    print(
        f"  land={report.get('land')} sea={report.get('sea')} "
        f"empty_names={report.get('empty_or_placeholder_names')} densify_style={report.get('densify_style_names')}"
    )
    print(
        f"  region_assigned={report.get('region_assigned')} ({report.get('region_assigned_pct')}%) "
        f"no_poly={report.get('geometry_no_polygon')}"
    )
    if rate is not None:
        print(
            f"  NE land hit rate={rate} "
            f"({report.get('ne_land_centroids_hit')}/{report.get('ne_land_centroids_tested')})"
        )
    for w in report.get("warnings") or []:
        print("  WARN:", w)
    for e in report.get("errors") or []:
        print("  ERR:", e)

    if not report.get("ok_hard"):
        return 1
    if min_hit > 0 and not report.get("ok_ne"):
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
