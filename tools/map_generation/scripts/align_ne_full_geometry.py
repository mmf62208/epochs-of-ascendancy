#!/usr/bin/env python3
"""Align all world_full province rings to Natural Earth 10m land (id-stable).

Default is dry-run metrics. Mutation requires **both** `--write` and `--full`.

Usage:
  python3 tools/map_generation/scripts/align_ne_full_geometry.py \\
      --dir data/provinces_world_full
  python3 tools/map_generation/scripts/align_ne_full_geometry.py \\
      --dir data/provinces_world_full --write --full --backup
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import load_geometry_payload  # noqa: E402
from ne_full_geometry_align import (  # noqa: E402
    DEFAULT_NE_LAND,
    apply_ne_full_align,
    build_domain_map,
    geometry_stats,
    load_ne_land_features,
    ne_full_integrity_report,
    rasterize_land_mask,
)


def main(argv: list | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", default="data/provinces_world_full")
    ap.add_argument("--ne-land", default=str(DEFAULT_NE_LAND), help="Path to NE 10m land GeoJSON")
    ap.add_argument("--dry-run", action="store_true", help="Metrics only (default if no --write)")
    ap.add_argument("--write", action="store_true", help="Mutate geometry (requires --full)")
    ap.add_argument("--full", action="store_true", help="Approve full-world NE write")
    ap.add_argument("--backup", action="store_true", help="Backup provinces_geometry.json before write")
    ap.add_argument("--mask-width", type=int, default=2048)
    ap.add_argument("--mask-height", type=int, default=1024)
    ap.add_argument("--blend", type=float, default=0.85, help="Snap blend toward NE (0–1)")
    ap.add_argument("--out", default="", help="Optional output geometry path")
    args = ap.parse_args(argv)

    data_dir = Path(args.dir)
    if not data_dir.is_absolute():
        data_dir = ROOT / data_dir
    geom_path = data_dir / "provinces_geometry.json"
    terrain_path = data_dir / "province_terrain_layer.json"
    ne_path = Path(args.ne_land)
    if not ne_path.is_absolute():
        ne_path = ROOT / ne_path

    if args.write and not args.full:
        print(
            "REFUSED: --write requires --full for Natural Earth full-world align.",
            file=sys.stderr,
        )
        return 2
    if not geom_path.is_file():
        print("ERROR: missing", geom_path, file=sys.stderr)
        return 1
    if not ne_path.is_file():
        print("ERROR: missing NE land", ne_path, file=sys.stderr)
        return 1

    print("Loading geometry…", geom_path)
    geom = load_geometry_payload(geom_path)
    before_ids = {int(p["id"]) for p in geom.get("provinces") or []}
    before_n = len(geom.get("provinces") or [])
    stats_before = geometry_stats(geom.get("provinces") or [])

    domain_map: dict = {}
    if terrain_path.is_file():
        terrain = json.loads(terrain_path.read_text(encoding="utf-8"))
        domain_map = build_domain_map(terrain)

    print("Loading NE land…", ne_path)
    rings = load_ne_land_features(ne_path)
    print("  NE outer rings:", len(rings))
    print(
        "Rasterizing land mask %dx%d…"
        % (int(args.mask_width), int(args.mask_height))
    )
    mask = rasterize_land_mask(
        rings, width=int(args.mask_width), height=int(args.mask_height)
    )
    land_px = int((mask >= 128).sum())
    print("  land pixels:", land_px, "of", mask.size)

    print("Aligning all provinces to NE…")
    after = apply_ne_full_align(
        geom,
        mask,
        domain_map,
        blend=float(args.blend),
    )
    report = ne_full_integrity_report(after)
    after_ids = {int(p["id"]) for p in after.get("provinces") or []}
    id_stable = after_ids == before_ids and len(after.get("provinces") or []) == before_n

    print("[NE-FULL] Natural Earth full geometry align")
    print("  province_count:", before_n)
    print("  id_stable:", id_stable)
    print("  gis_ne_full_count:", report.get("gis_ne_full_count"))
    print("  gis_pilot_count:", report.get("gis_pilot_count"))
    print("  land/water:", (after.get("meta") or {}).get("gis_ne_land_count"), (after.get("meta") or {}).get("gis_ne_water_count"))
    print("  snapped_verts_total:", (after.get("meta") or {}).get("gis_ne_snapped_verts_total"))
    print("  geometry_before:", stats_before)
    print("  geometry_after:", report.get("stats"))
    print("  integrity:", report.get("summary"))

    do_write = bool(args.write and args.full)
    if not do_write:
        print("PASS: dry-run only; geometry unchanged on disk")
        return 0 if id_stable and int(report.get("gis_ne_full_count") or 0) >= before_n else 1

    if not id_stable:
        print("ERROR: id set changed — abort write", file=sys.stderr)
        return 3
    stats = report.get("stats") or {}
    if int(stats.get("triangles") or 0) != 0:
        print("ERROR: triangles != 0", file=sys.stderr)
        return 3
    if int(stats.get("min") or 0) < 16:
        print("ERROR: min vertices < 16", file=sys.stderr)
        return 3
    if int(report.get("gis_ne_full_count") or 0) < before_n:
        print("ERROR: not all provinces stamped", file=sys.stderr)
        return 3

    out_path = Path(args.out) if args.out else geom_path
    if not out_path.is_absolute():
        out_path = ROOT / out_path
    if args.backup and out_path == geom_path and geom_path.is_file():
        bak = geom_path.with_suffix(geom_path.suffix + ".ne_bak")
        shutil.copy2(geom_path, bak)
        print("  backup:", bak)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(after, separators=(",", ":")), encoding="utf-8")
    print("  wrote:", out_path)
    print(
        "PASS: NE full write id_stable=true stamped=%d triangles=0"
        % int(report.get("gis_ne_full_count") or 0)
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
