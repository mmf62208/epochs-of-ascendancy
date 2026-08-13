#!/usr/bin/env python3
"""GIS coastline ingest — real align metrics + guarded pilot write.

Default is dry-run. Geometry mutation requires **both** `--write` and `--pilot`.
Ids are never renumbered. Offline pilot source is built from coastal province
rings when `--source` is omitted.

See docs/GIS_COASTLINE_INGEST_DESIGN.md.

Usage:
  python3 tools/map_generation/scripts/ingest_gis_coastlines.py \\
      --dir data/provinces_world_full
  python3 tools/map_generation/scripts/ingest_gis_coastlines.py \\
      --dir data/provinces_world_full --write --pilot --pilot-limit 12
  python3 tools/map_generation/scripts/ingest_gis_coastlines.py \\
      --dir data/provinces_world_full --source path/to/gis.json --dry-run
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from gis_coastline_ingest import (  # noqa: E402
    build_pilot_fixture_from_geometry,
    coastal_province_ids_from_base,
    coastal_province_ids_from_terrain,
    expand_coastal_id_pool,
    format_metrics_report,
    load_geometry_payload,
    load_gis_features,
    run_align_pipeline,
)

DESIGN = ROOT / "docs" / "GIS_COASTLINE_INGEST_DESIGN.md"
DEFAULT_FIXTURE = (
    ROOT
    / "tools"
    / "map_generation"
    / "fixtures"
    / "gis_coastline_pilot_rings.json"
)


def _resolve_dir(raw: str) -> Path:
    p = Path(raw)
    if not p.is_absolute():
        p = ROOT / p
    return p


def _load_coastal_ids(
    data_dir: Path,
    *,
    include_littoral: bool = False,
    littoral_depth: int = 1,
) -> list:
    terrain_path = data_dir / "province_terrain_layer.json"
    base_path = data_dir / "provinces_base.json"
    adj_path = data_dir / "province_adjacency.json"
    ids: list = []
    if terrain_path.is_file():
        terrain = json.loads(terrain_path.read_text(encoding="utf-8"))
        if include_littoral and adj_path.is_file():
            adj = json.loads(adj_path.read_text(encoding="utf-8"))
            ids = expand_coastal_id_pool(
                terrain,
                adj,
                include_littoral=True,
                littoral_depth=max(1, int(littoral_depth)),
                limit=0,
            )
        else:
            ids = coastal_province_ids_from_terrain(terrain)
    if not ids and base_path.is_file():
        base = json.loads(base_path.read_text(encoding="utf-8"))
        ids = coastal_province_ids_from_base(base)
    return ids


def _load_or_build_features(
    data_dir: Path,
    geom_payload: dict,
    source: str,
    pilot_limit: int,
    *,
    include_littoral: bool = False,
    littoral_depth: int = 1,
    prefer_built_in: bool = False,
) -> tuple:
    """Return (features, source_label)."""
    limit = max(1, int(pilot_limit))
    if source:
        sp = Path(source)
        if not sp.is_absolute():
            sp = ROOT / sp
        if not sp.is_file():
            raise FileNotFoundError("GIS source not found: %s" % sp)
        return load_gis_features(sp)[:limit], str(sp)

    # Prefer built-in expansion when littoral expand requested or fixture too small
    coastal = _load_coastal_ids(data_dir, include_littoral=include_littoral, littoral_depth=littoral_depth)
    if not coastal:
        coastal = [
            int(p["id"])
            for p in (geom_payload.get("provinces") or [])
            if len(p.get("points") or []) >= 3
        ][:pilot_limit]

    use_fixture = (
        DEFAULT_FIXTURE.is_file()
        and not prefer_built_in
        and not include_littoral
    )
    if use_fixture:
        feats = load_gis_features(DEFAULT_FIXTURE)
        if feats and len(feats) >= min(limit, 24):
            # Fixture covers request when large enough; else rebuild from pool
            if len(feats) >= limit or not coastal:
                return feats[:limit], str(DEFAULT_FIXTURE)

    if coastal:
        feats = build_pilot_fixture_from_geometry(
            geom_payload.get("provinces") or [],
            coastal,
            limit=limit,
        )
        label = "built-in pilot from coastal%s geometry (limit=%d pool=%d)" % (
            ("+littoral d%d" % max(1, int(littoral_depth))) if include_littoral else "",
            limit,
            len(coastal),
        )
        return feats, label

    return [], "empty"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", default="data/provinces_world_full")
    ap.add_argument(
        "--source",
        default="",
        help="Optional GIS JSON/GeoJSON. If empty, use fixture or built-in coastal pilot.",
    )
    ap.add_argument(
        "--dry-run",
        action="store_true",
        default=True,
        help="Report metrics only (default).",
    )
    ap.add_argument(
        "--write",
        action="store_true",
        help="Mutate geometry (requires --pilot).",
    )
    ap.add_argument(
        "--pilot",
        action="store_true",
        help="Approve pilot write subset (required with --write).",
    )
    ap.add_argument(
        "--pilot-limit",
        type=int,
        default=24,
        help="Max coastal GIS rings for built-in/fixture pilot (default 24).",
    )
    ap.add_argument(
        "--include-littoral",
        action="store_true",
        help="Expand pilot pool with land provinces adjacent to water (beyond coastal_land).",
    )
    ap.add_argument(
        "--littoral-depth",
        type=int,
        default=1,
        help="With --include-littoral: 1=water-adjacent, 2+=inland rings (default 1).",
    )
    ap.add_argument(
        "--rebuild-features",
        action="store_true",
        help="Force built-in geometry features instead of shipped fixture (use with expand).",
    )
    ap.add_argument(
        "--out",
        default="",
        help="Optional output geometry path (default: in-place provinces_geometry.json).",
    )
    ap.add_argument(
        "--backup",
        action="store_true",
        help="Backup provinces_geometry.json to .bak before in-place write.",
    )
    ap.add_argument(
        "--min-vertices",
        type=int,
        default=16,
        help="Min vertices after pilot write densify (default 16).",
    )
    ap.add_argument(
        "--write-fixture",
        default="",
        help="If set, write the built-in pilot features JSON to this path and exit after dry-run metrics.",
    )
    args = ap.parse_args(argv)

    data_dir = _resolve_dir(args.dir)
    geom_path = data_dir / "provinces_geometry.json"
    if not geom_path.is_file():
        print("ERROR: missing geometry %s" % geom_path, file=sys.stderr)
        return 1

    # Gate write without pilot
    if args.write and not args.pilot:
        print(
            "REFUSED: --write requires --pilot for guarded coastline pilot. "
            "See docs/GIS_COASTLINE_INGEST_DESIGN.md.",
            file=sys.stderr,
        )
        return 2

    geom = load_geometry_payload(geom_path)
    try:
        features, source_label = _load_or_build_features(
            data_dir,
            geom,
            args.source,
            max(1, int(args.pilot_limit)),
            include_littoral=bool(args.include_littoral),
            littoral_depth=max(1, int(args.littoral_depth)),
            prefer_built_in=bool(args.rebuild_features or args.include_littoral),
        )
    except FileNotFoundError as exc:
        print("ERROR: %s" % exc, file=sys.stderr)
        return 1

    if not features:
        print("ERROR: no GIS features to align", file=sys.stderr)
        return 1

    if args.write_fixture:
        out_f = Path(args.write_fixture)
        if not out_f.is_absolute():
            out_f = ROOT / out_f
        out_f.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "meta": {
                "kind": "gis_coastline_pilot_fixture",
                "source": source_label,
                "count": len(features),
            },
            "features": features,
        }
        out_f.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        print("Wrote fixture:", out_f, "features:", len(features))

    do_write = bool(args.write and args.pilot)
    metrics = run_align_pipeline(
        geom,
        features,
        min_vertices=int(args.min_vertices),
        apply_write=do_write,
    )

    print(format_metrics_report(metrics, dry_run=not do_write))
    print("  design:", DESIGN if DESIGN.is_file() else "MISSING")
    print("  target_dir:", data_dir)
    print("  source:", source_label)
    print("  geometry_path:", geom_path)
    if metrics.get("matched_ids"):
        print(
            "  matched_ids_sample:",
            metrics["matched_ids"][:8],
            ("..." if len(metrics["matched_ids"]) > 8 else ""),
        )

    # Quality gate for any write
    if do_write:
        ga = metrics.get("geometry_after") or {}
        if not metrics.get("id_stable"):
            print("ERROR: id_stable=false after write — aborting disk write", file=sys.stderr)
            return 3
        if int(ga.get("triangles") or 0) != 0:
            print("ERROR: triangles!=0 after pilot write", file=sys.stderr)
            return 3
        if int(ga.get("min") or 0) < int(args.min_vertices):
            print(
                "ERROR: min vertices %s < %s after pilot write"
                % (ga.get("min"), args.min_vertices),
                file=sys.stderr,
            )
            return 3
        changed = int(metrics.get("changed_provinces") or 0)
        if changed < 1:
            # Idempotent re-apply of the same pilot rings is OK (quality still gated).
            print(
                "  note: changed_provinces=0 (idempotent re-apply of existing pilot rings)"
            )

        out_path = Path(args.out) if args.out else geom_path
        if not out_path.is_absolute():
            out_path = ROOT / out_path
        if args.backup and out_path == geom_path:
            bak = geom_path.with_suffix(geom_path.suffix + ".bak")
            shutil.copy2(geom_path, bak)
            print("  backup:", bak)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(
            json.dumps(metrics["payload"], indent=2),
            encoding="utf-8",
        )
        print("  wrote:", out_path)
        print(
            "PASS: pilot write id_stable=true matched=%s changed=%s triangles=0"
            % (metrics.get("matched"), changed)
        )
        return 0

    # Dry-run success criteria
    if int(metrics.get("matched") or 0) < 1:
        print("ERROR: dry-run matched=0 (expected real alignment)", file=sys.stderr)
        return 4
    if not metrics.get("id_stable"):
        print("ERROR: id_stable=false on dry-run", file=sys.stderr)
        return 4
    print("PASS: dry-run real metrics; world_full geometry unchanged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
