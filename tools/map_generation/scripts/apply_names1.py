#!/usr/bin/env python3
"""Apply NAMES-1 display names on world_accurate provinces_base.json.

Dry-run by default. ``--apply`` rewrites only the ``name`` string of land
provinces. Admin polygons are read from ``~/names1/scratch/geoboundaries``
(not committed). ``--fetch`` downloads missing geoBoundaries ADM1 simplified
files into that directory.

  python3 tools/map_generation/scripts/apply_names1.py
  python3 tools/map_generation/scripts/apply_names1.py --apply
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import random
import re
import sys
import urllib.request
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

SCRATCH = Path.home() / "names1" / "scratch" / "geoboundaries"
EVIDENCE = Path.home() / "names1" / "evidence"
BOARD = ROOT / "data" / "provinces_world_accurate" / "provinces_base.json"
OWN_PATH = ROOT / "data" / "provinces_world_accurate" / "province_ownership_1936.json"
GEOM_PATH = ROOT / "data" / "provinces_world_accurate" / "provinces_geometry.json"

# Same equirectangular frame as ne_full_geometry_align.WORLD_BBOX / WORLD_CANVAS.
WORLD_BBOX = (-180.0, -56.0, 180.0, 83.0)
WORLD_CANVAS = (8192.0, 4096.0)

from names1_product import (  # noqa: E402
    ADMIN_HITS,
    PINNED_NAME_IDS,
    SEA_ID,
    UNKNOWN,
    count_categories,
    disambiguate,
    name_categories,
    proposal_detail,
)


def _ensure_shapely():
    try:
        import shapely  # noqa: F401
    except ImportError:
        venv = Path.home() / "names1" / "venv" / "bin" / "python"
        if venv.exists() and Path(sys.executable).resolve() != venv.resolve():
            os.execv(str(venv), [str(venv), *sys.argv])
        raise SystemExit("shapely is required (venv at ~/names1/venv)")


def canvas_to_lonlat(x: float, y: float) -> Tuple[float, float]:
    lon_min, lat_min, lon_max, lat_max = WORLD_BBOX
    w, h = WORLD_CANVAS
    lon = lon_min + (float(x) / (w - 1.0)) * (lon_max - lon_min)
    lat = lat_max - (float(y) / (h - 1.0)) * (lat_max - lat_min)
    return lon, lat


def polygon_centroid(points: Sequence[Sequence[float]]) -> Tuple[float, float]:
    ring = list(points)
    if len(ring) >= 2 and ring[0] == ring[-1]:
        ring = ring[:-1]
    if not ring:
        return 0.0, 0.0
    n = float(len(ring))
    return sum(float(p[0]) for p in ring) / n, sum(float(p[1]) for p in ring) / n


def fetch_missing() -> None:
    SCRATCH.mkdir(parents=True, exist_ok=True)
    api_path = SCRATCH.parent / "gb_adm1_api.json"
    if not api_path.exists():
        url = "https://www.geoboundaries.org/api/current/gbOpen/ALL/ADM1/"
        api_path.write_bytes(urllib.request.urlopen(url, timeout=120).read())
    api = json.loads(api_path.read_text(encoding="utf-8"))
    for rec in api:
        iso = str(rec.get("boundaryISO") or "")
        url = str(rec.get("simplifiedGeometryGeoJSON") or "")
        if not iso or not url:
            continue
        dest = SCRATCH / f"geoBoundaries-{iso}-ADM1_simplified.geojson"
        if dest.exists() and dest.stat().st_size > 1000:
            continue
        print(f"fetch {iso}")
        try:
            dest.write_bytes(urllib.request.urlopen(url, timeout=120).read())
        except Exception as exc:  # noqa: BLE001
            print(f"  fail {iso}: {exc}")
    phl = SCRATCH / "geoBoundaries-PHL-ADM2_simplified.geojson"
    if not phl.exists():
        url = (
            "https://github.com/wmgeolab/geoBoundaries/raw/9469f09/"
            "releaseData/gbOpen/PHL/ADM2/geoBoundaries-PHL-ADM2_simplified.geojson"
        )
        print("fetch PHL ADM2")
        phl.write_bytes(urllib.request.urlopen(url, timeout=120).read())


def _load_level(level: int):
    from shapely.geometry import shape
    from shapely.strtree import STRtree

    geoms = []
    names = []
    isos = []
    for path in sorted(SCRATCH.glob(f"geoBoundaries-*-ADM{level}_simplified.geojson")):
        iso = path.name.split("-")[1]
        try:
            doc = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            print(f"skip bad json {path.name}")
            continue
        for feat in doc.get("features") or []:
            geom_d = feat.get("geometry")
            if not geom_d:
                continue
            try:
                geom = shape(geom_d)
            except Exception:
                continue
            if geom.is_empty:
                continue
            props = feat.get("properties") or {}
            geoms.append(geom)
            names.append(str(props.get("shapeName") or ""))
            isos.append(iso if level == 1 else str(props.get("shapeGroup") or iso))
    if not geoms:
        print(f"loaded ADM{level} 0 polygons")
        return None, [], [], []
    tree = STRtree(geoms)
    print(f"loaded ADM{level} {len(geoms)} polygons from {SCRATCH}")
    return tree, geoms, names, isos


def _hit_index(tree, geoms, names, isos, lon: float, lat: float) -> Optional[int]:
    from shapely.geometry import Point

    pt = Point(lon, lat)
    try:
        idxs = list(tree.query(pt, predicate="intersects"))
    except TypeError:
        idxs = [i for i in tree.query(pt) if geoms[int(i)].intersects(pt)]
    if idxs:
        idxs.sort(key=lambda i: geoms[int(i)].area)
        return int(idxs[0])
    try:
        idx = int(tree.nearest(pt))
    except Exception:
        return None
    if geoms[idx].distance(pt) <= 1.5:
        return idx
    return None


def build_hits(centroids: Dict[int, Tuple[float, float]]) -> None:
    tree, geoms, names, isos = _load_level(1)
    if tree is None:
        raise SystemExit(f"no ADM1 geojson in {SCRATCH} (run --fetch)")
    tree2, geoms2, names2, isos2 = _load_level(2)
    ADMIN_HITS.clear()
    for pid, (lon, lat) in centroids.items():
        idx = _hit_index(tree, geoms, names, isos, lon, lat)
        if idx is None:
            continue
        rec: Dict[str, object] = {
            "iso": isos[idx],
            "adm1": names[idx],
            "adm2": "",
            "lat": lat,
            "lon": lon,
        }
        if tree2 is not None and (isos[idx] == "PHL" or (50.5 <= lon <= 52.2 and 24.3 <= lat <= 26.4)):
            idx2 = _hit_index(tree2, geoms2, names2, isos2, lon, lat)
            if idx2 is not None:
                rec["adm2"] = names2[idx2]
        ADMIN_HITS[pid] = rec


def _owners() -> Dict[str, str]:
    doc = json.loads(OWN_PATH.read_text(encoding="utf-8"))
    return {str(k): str(v) for k, v in (doc.get("owners") or {}).items()}


def _centroids() -> Dict[int, Tuple[float, float]]:
    geo = json.loads(GEOM_PATH.read_text(encoding="utf-8"))
    out: Dict[int, Tuple[float, float]] = {}
    for rec in geo["provinces"]:
        pid = int(rec["id"])
        if pid >= SEA_ID:
            continue
        cx, cy = polygon_centroid(rec.get("points") or [])
        out[pid] = canvas_to_lonlat(cx, cy)
    return out


_NAME_LINE = re.compile(r'("id": (\d+),\n      "name": ")([^"]*)(")')


def _rewrite_names(text: str, new_names: Dict[int, str]) -> str:
    def repl(match: re.Match) -> str:
        pid = int(match.group(2))
        if pid not in new_names:
            return match.group(0)
        new = new_names[pid]
        if '"' in new or "\n" in new:
            raise SystemExit(f"unsafe name for {pid}: {new!r}")
        return f"{match.group(1)}{new}{match.group(4)}"

    out, n = _NAME_LINE.subn(repl, text)
    if n < 3000:
        raise SystemExit(f"name-line rewrite matched only {n} provinces")
    return out


def _check_berlin(centroids: Dict[int, Tuple[float, float]]) -> None:
    lon, lat = centroids[710300]
    if not (12.5 <= lon <= 14.5 and 51.5 <= lat <= 53.5):
        raise SystemExit(f"Berlin centroid {lon:.2f},{lat:.2f} is not equirectangular; refusing to rename")


def run(apply: bool) -> None:
    _ensure_shapely()
    text = BOARD.read_text(encoding="utf-8")
    doc = json.loads(text)
    prov_name = {int(p["id"]): str(p.get("name") or "") for p in doc["provinces"]}
    owners = _owners()
    centroids = _centroids()
    _check_berlin(centroids)
    # Hits only needed for placeholders. Build for every land id so numeric
    # area names and tag-direction blobs can resolve.
    build_hits(centroids)

    details: Dict[int, Dict[str, str]] = {}
    final_name: Dict[int, str] = {}
    rows = []
    for prov in doc["provinces"]:
        pid = int(prov["id"])
        old = str(prov.get("name") or "")
        final_name[pid] = old
        if pid >= SEA_ID:
            continue
        lon, lat = centroids[pid]
        detail = proposal_detail(pid, prov, (lon, lat))
        details[pid] = detail
        final_name[pid] = detail["new"]
        rows.append(
            {
                "pid": pid,
                "owner": owners.get(str(pid), ""),
                "name": detail["new"],
                "lat": lat,
                "lon": lon,
                "pinned": pid in PINNED_NAME_IDS,
            }
        )

    extra = disambiguate(rows)
    for change in extra:
        pid = int(change["pid"])
        final_name[pid] = str(change["new"])
        prev = details.get(pid) or {"old": change["old"], "rule": "disambiguate", "source": ""}
        # Keep the original stored name as old.
        base_old = str(prov_name[pid])
        rule = prev.get("rule") or "disambiguate"
        if rule in ("unchanged", "pinned", ""):
            rule = "disambiguate"
        elif rule != "disambiguate":
            rule = rule + "+disambiguate"
        details[pid] = {
            "old": base_old,
            "new": str(change["new"]),
            "rule": rule,
            "source": (prev.get("source") or "") + " compass",
        }

    by_id = prov_name
    renames = {pid: name for pid, name in final_name.items() if name != by_id.get(pid)}

    before = count_categories(
        by_id[pid] for pid in by_id if pid < SEA_ID
    )
    after_names = [final_name[pid] for pid in by_id if pid < SEA_ID]
    after = count_categories(after_names)
    unknown_left = [
        pid
        for pid, name in final_name.items()
        if pid < SEA_ID and pid not in PINNED_NAME_IDS and name_categories(name)
    ]
    print(
        f"tag-dir {before['tag-dir']}->{after['tag-dir']}  "
        f"area {before['area']}->{after['area']}  "
        f"nonlatin {before['nonlatin']}->{after['nonlatin']}  "
        f"oddity {before['oddity']}->{after['oddity']}  "
        f"renamed {len(renames)}  pinned {len(PINNED_NAME_IDS)}  "
        f"unknown_left {len(unknown_left)} frozen_unknown {len(UNKNOWN)}"
    )
    if unknown_left[:12]:
        for pid in unknown_left[:12]:
            print(f"  still {pid} {final_name[pid]!r} cats={name_categories(final_name[pid])}")
    if unknown_left and apply:
        raise SystemExit(f"refusing to apply; {len(unknown_left)} unresolved placeholders")

    EVIDENCE.mkdir(parents=True, exist_ok=True)
    table = EVIDENCE / "rename_table.csv"
    with table.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["pid", "owner", "old", "new", "rule", "source"])
        for pid in sorted(renames):
            detail = details.get(pid) or {}
            writer.writerow(
                [
                    pid,
                    owners.get(str(pid), ""),
                    by_id.get(pid, ""),
                    renames[pid],
                    detail.get("rule", ""),
                    detail.get("source", ""),
                ]
            )
    sample_path = EVIDENCE / "rename_sample_200.csv"
    rng = random.Random(19360101)
    sample_ids = sorted(renames)
    rng.shuffle(sample_ids)
    sample_ids = sample_ids[:200]
    with sample_path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["pid", "owner", "old", "new", "rule", "source"])
        for pid in sorted(sample_ids):
            detail = details.get(pid) or {}
            writer.writerow(
                [
                    pid,
                    owners.get(str(pid), ""),
                    by_id.get(pid, ""),
                    renames[pid],
                    detail.get("rule", ""),
                    detail.get("source", ""),
                ]
            )
    print(f"evidence {table} ({len(renames)} rows) sample {sample_path}")

    if not apply:
        print("dry-run (pass --apply to write provinces_base.json)")
        return
    rewritten = _rewrite_names(text, renames)
    # Prove non-name fields survive a parse round-trip comparison.
    new_doc = json.loads(rewritten)
    old_doc = json.loads(text)
    if [int(p["id"]) for p in new_doc["provinces"]] != [int(p["id"]) for p in old_doc["provinces"]]:
        raise SystemExit("id order changed")
    for new_p, old_p in zip(new_doc["provinces"], old_doc["provinces"]):
        pid = int(old_p["id"])
        if str(new_p.get("name") or "") != final_name[pid]:
            raise SystemExit(f"name not applied id={pid}")
        for key, value in old_p.items():
            if key == "name":
                continue
            if new_p.get(key) != value:
                raise SystemExit(f"non-name field changed id={pid} key={key}")
    BOARD.write_text(rewritten, encoding="utf-8")
    print(f"wrote {BOARD}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="write provinces_base.json")
    parser.add_argument("--fetch", action="store_true", help="download missing geoBoundaries files")
    args = parser.parse_args()
    if args.fetch:
        fetch_missing()
    run(apply=args.apply)


if __name__ == "__main__":
    main()
