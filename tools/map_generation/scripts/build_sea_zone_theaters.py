#!/usr/bin/env python3
"""Build named sea-zone theaters for world_full naval feel (prototype).

Groups domain sea/strait provinces into playable named sea zones using name
keywords + theater fallback. Output consumed by MapManager for inspector/tooltips.

Usage:
  python3 tools/map_generation/scripts/build_sea_zone_theaters.py \\
      --dir data/provinces_world_full [--write]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]

# Order matters — first match wins.
ZONE_RULES: List[Tuple[str, re.Pattern[str]]] = [
    ("Mediterranean Sea", re.compile(r"mediterr|tyrrhen|aegean|adriatic|ionian|levant", re.I)),
    ("English Channel & Approaches", re.compile(r"english channel|channel zone|dover", re.I)),
    ("North Sea", re.compile(r"north sea", re.I)),
    ("Baltic Sea", re.compile(r"baltic", re.I)),
    ("Black Sea", re.compile(r"black sea", re.I)),
    ("Red Sea & Aden", re.compile(r"red sea|aden|bab", re.I)),
    ("Persian Gulf & Hormuz", re.compile(r"hormuz|persian gulf|gulf of oman", re.I)),
    ("Caribbean Sea", re.compile(r"caribbean|gulf of mexico|sargasso", re.I)),
    ("North Atlantic", re.compile(r"north atlantic|labrador|norwegian|barents", re.I)),
    ("South Atlantic", re.compile(r"south atlantic|cape basin|guinea basin|argentine", re.I)),
    ("Mid-Atlantic", re.compile(r"mid[- ]?atlantic|atlantic", re.I)),
    ("North Pacific", re.compile(r"north pacific|bering|kuril|japan sea|okhotsk", re.I)),
    ("South Pacific", re.compile(r"south pacific|tasman|coral sea|chilean", re.I)),
    ("Central Pacific", re.compile(r"central pacific|hawaii|pacific", re.I)),
    ("Indian Ocean", re.compile(r"indian|arabian sea|bay of bengal|andaman|mascarene|mozambique", re.I)),
    ("South China & SE Asia Seas", re.compile(r"south china|malacca|java sea|celebes|philippine", re.I)),
    ("Arctic Ocean", re.compile(r"arctic|kara|laptev|beaufort|greenland sea", re.I)),
    ("Global Straits", re.compile(r"strait|approaches|canal zone", re.I)),
]

MIN_ZONES = 8
MIN_SEA_ASSIGNED = 200


def classify_zone(name: str, domain: str) -> str:
    n = name or ""
    for zone, rx in ZONE_RULES:
        if rx.search(n):
            return zone
    if domain == "strait":
        return "Global Straits"
    return "Open Ocean"


def build(data_dir: Path) -> Dict[str, Any]:
    base = json.loads((data_dir / "provinces_base.json").read_text(encoding="utf-8"))
    zones: Dict[str, List[int]] = {}
    pid_to_zone: Dict[str, str] = {}
    sea_count = 0
    for p in base.get("provinces") or []:
        domain = str(p.get("domain") or "").lower()
        if domain not in ("sea", "strait"):
            continue
        sea_count += 1
        pid = int(p["id"])
        zone = classify_zone(str(p.get("name") or ""), domain)
        zones.setdefault(zone, []).append(pid)
        pid_to_zone[str(pid)] = zone

    # Sort ids for stability
    for z in zones:
        zones[z] = sorted(set(zones[z]))

    payload = {
        "version": 1,
        "source": "build_sea_zone_theaters.py",
        "meta": {
            "sea_province_count": sea_count,
            "zone_count": len(zones),
            "notes": (
                "Prototype named sea-zone theaters for inspector/tooltips/naval feel. "
                "Not full blue-water operational sea zones."
            ),
        },
        "zones": [
            {
                "id": i + 1,
                "name": name,
                "province_ids": zones[name],
                "province_count": len(zones[name]),
            }
            for i, name in enumerate(sorted(zones.keys(), key=lambda n: (-len(zones[n]), n)))
        ],
        "province_to_zone": pid_to_zone,
    }
    return payload


def main(argv: Optional[Sequence[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", default="data/provinces_world_full")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)
    data_dir = Path(args.dir)
    if not data_dir.is_absolute():
        data_dir = ROOT / data_dir
    payload = build(data_dir)
    zc = int(payload["meta"]["zone_count"])
    sc = int(payload["meta"]["sea_province_count"])
    mode = "WROTE" if args.write and not args.dry_run else "DRY-RUN"
    print(f"[{mode}] sea={sc} zones={zc}")
    for z in payload["zones"][:12]:
        print(f"  - {z['name']}: {z['province_count']}")
    if len(payload["zones"]) > 12:
        print(f"  ... +{len(payload['zones']) - 12} more")
    if args.write and not args.dry_run:
        out = data_dir / "sea_zone_theaters.json"
        out.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"  wrote {out}")
    ok = zc >= MIN_ZONES and sc >= MIN_SEA_ASSIGNED and len(payload["province_to_zone"]) == sc
    if not ok:
        print("FAIL sea zone theaters gates", file=sys.stderr)
        return 1
    print("PASS sea zone theaters prototype")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
