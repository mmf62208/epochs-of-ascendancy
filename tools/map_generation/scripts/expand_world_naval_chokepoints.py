#!/usr/bin/env python3
"""Expand world_full naval chokepoint set for playable naval feel.

Merges:
  - existing naval_chokepoints.json ids
  - all provinces with domain == strait
  - name heuristics (canal/strait/channel/hormuz/suez/…)
  - low-degree coastal articulation candidates from naval_analysis

Target: ≥30 chokepoint province ids on world_full.

Usage:
  python3 tools/map_generation/scripts/expand_world_naval_chokepoints.py \\
      --dir data/provinces_world_full [--write]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Set

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib import naval_analysis  # noqa: E402

NAME_RE = re.compile(
    r"(strait|channel|canal|hormuz|suez|gibraltar|malacca|bospor|dardan|"
    r"danish|tsushima|panama|kiel|skagger|aden|ormuz|sunda|lombok|"
    r"tsugaru|dover|bab\s*el|good hope|cape horn|ormuz|skagerrak|kattegat|"
    r"bosphorus|dardanelles|ormuz)",
    re.I,
)

MIN_CHOKEPOINTS = 30


def load_existing(path: Path) -> List[int]:
    if not path.exists():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    return [int(x) for x in (data.get("chokepoint_province_ids") or [])]


def expand(data_dir: Path) -> Dict[str, Any]:
    base = json.loads((data_dir / "provinces_base.json").read_text(encoding="utf-8"))
    geom_ids = {
        int(p["id"])
        for p in json.loads((data_dir / "provinces_geometry.json").read_text())["provinces"]
    }
    existing = set(load_existing(data_dir / "naval_chokepoints.json"))

    by_domain: Set[int] = set()
    by_name: Set[int] = set()
    for p in base.get("provinces") or []:
        pid = int(p["id"])
        if pid not in geom_ids:
            continue
        domain = str(p.get("domain") or "").lower()
        name = str(p.get("name") or "")
        if domain == "strait":
            by_domain.add(pid)
        if NAME_RE.search(name):
            # Prefer coastal/strait domains for name hits
            if domain in ("strait", "coastal_land", "sea", "land"):
                by_name.add(pid)

    layers = naval_analysis.load_all_layers(data_dir)
    adj = layers["adjacency"]
    coastal = naval_analysis.get_coastal_provinces(layers)
    artic = set(
        naval_analysis.find_potential_chokepoints(adj, min_degree=2, max_degree=4)
    )
    artic_coastal = {pid for pid in artic if pid in coastal and pid in geom_ids}

    # Cap articulation extras so we don't flood the set
    artic_extra = sorted(artic_coastal - existing - by_domain - by_name)[:24]

    all_ids = sorted(existing | by_domain | by_name | set(artic_extra))
    # Prefer quality: if still short, add more artic
    if len(all_ids) < MIN_CHOKEPOINTS:
        more = sorted(artic_coastal - set(all_ids))
        for pid in more:
            all_ids.append(pid)
            if len(all_ids) >= MIN_CHOKEPOINTS:
                break
        all_ids = sorted(set(all_ids))

    return {
        "meta": {
            "source": "expand_world_naval_chokepoints.py",
            "count": len(all_ids),
            "notes": (
                "Merged prior polish IDs + domain=strait + name heuristics + "
                "coastal articulation candidates for world naval feel."
            ),
        },
        "chokepoint_province_ids": all_ids,
        "sources": {
            "existing": sorted(existing),
            "domain_strait": sorted(by_domain),
            "name_heuristic": sorted(by_name),
            "articulation_extra": artic_extra,
        },
        "coastal_count": len(coastal & geom_ids),
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
    out = expand(data_dir)
    n = len(out["chokepoint_province_ids"])
    mode = "WROTE" if args.write and not args.dry_run else "DRY-RUN"
    print(f"[{mode}] chokepoints={n} (min {MIN_CHOKEPOINTS})")
    print("  sources counts:", {k: len(v) for k, v in out["sources"].items()})
    if args.write and not args.dry_run:
        path = data_dir / "naval_chokepoints.json"
        path.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"  wrote {path}")
    if n < MIN_CHOKEPOINTS:
        print("FAIL: fewer than min chokepoints", file=sys.stderr)
        return 1
    print("PASS naval chokepoint expansion")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
