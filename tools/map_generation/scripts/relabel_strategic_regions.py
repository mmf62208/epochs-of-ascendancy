#!/usr/bin/env python3
"""Relabel generic 'Theater N' strategic regions with historical theater names.

Uses region center (or mean province centroid) + a world gazetteer of theater
seeds so mapmodes/inspector don't show raw k-means leftovers.

Usage:
  python3 tools/map_generation/scripts/relabel_strategic_regions.py \\
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

# Generic leftovers: "Theater 3", "Far East Theater 2", bare "Far East Theater"
_THEATER_N_RE = re.compile(r"^Theater\s+\d+\s*$", re.I)
_THEATER_SUFFIX_NUM_RE = re.compile(r"\bTheater\s+\d+\s*$", re.I)
_GENERIC_FAR_EAST_RE = re.compile(r"^Far East Theater\s*$", re.I)


def is_generic_region_name(name: str) -> bool:
    n = str(name or "").strip()
    if not n:
        return True
    if _THEATER_N_RE.match(n) or n.startswith("Theater "):
        return True
    if _THEATER_SUFFIX_NUM_RE.search(n):
        return True
    if _GENERIC_FAR_EAST_RE.match(n):
        return True
    if re.match(r"^Frontier Theater\s+\d+\s*$", n, re.I):
        return True
    return False


# World-native canvas seeds (approx equirectangular theater centers used by world_full).
# Expanded beyond Europe so Far East / Americas / Africa get real labels.
WORLD_THEATER_SEEDS: List[Tuple[str, float, float]] = [
    # Europe / MENA
    ("British Isles", 2000.0, 1200.0),
    ("France", 2300.0, 1500.0),
    ("Iberia", 1900.0, 1700.0),
    ("Low Countries", 2400.0, 1250.0),
    ("Germany", 2600.0, 1300.0),
    ("Italy", 2550.0, 1650.0),
    ("Alps & Danube", 2700.0, 1450.0),
    ("Scandinavia", 2700.0, 1000.0),
    ("Poland & Baltic", 2900.0, 1200.0),
    ("Balkans", 2900.0, 1600.0),
    ("Anatolia & Straits", 3200.0, 1550.0),
    ("Western Russia", 3400.0, 1200.0),
    ("Black Sea & Caucasus", 3400.0, 1500.0),
    ("North Africa Coast", 2400.0, 1900.0),
    ("Eastern Mediterranean", 3000.0, 1750.0),
    ("Levant & Near East", 3300.0, 1700.0),
    # Africa
    ("West Africa Coast", 2200.0, 2300.0),
    ("Sahel Belt", 2600.0, 2200.0),
    ("East Africa Highlands", 3200.0, 2400.0),
    ("Southern Africa", 3000.0, 2800.0),
    ("Congo Basin", 2800.0, 2500.0),
    # Asia
    ("Central Asia Steppes", 4000.0, 1400.0),
    ("Indian Subcontinent", 4200.0, 2000.0),
    ("Indochina & SE Asia", 4800.0, 2100.0),
    ("China Heartland", 5000.0, 1500.0),
    ("Manchuria & Korea", 5400.0, 1300.0),
    ("Japan & Home Islands", 5600.0, 1450.0),
    ("Siberia Far East", 5200.0, 1100.0),
    ("Pacific Island Chains", 6000.0, 2200.0),
    # Americas
    ("North American East", 900.0, 1400.0),
    ("North American West", 500.0, 1400.0),
    ("North American Midwest", 700.0, 1300.0),
    ("Caribbean & Gulf", 900.0, 1900.0),
    ("South American North", 1100.0, 2300.0),
    ("South American South", 1100.0, 2800.0),
    ("Andes Corridor", 900.0, 2500.0),
    # Oceans / frontier
    ("Atlantic Approaches", 1600.0, 1500.0),
    ("High North", 2800.0, 800.0),
    ("Eastern Frontiers", 3800.0, 1300.0),
    ("Siberian Far East", 5300.0, 1400.0),
    ("Maritime Far East", 5600.0, 1600.0),
    ("China Heartland", 5000.0, 1500.0),
    ("Yellow Sea Approaches", 5200.0, 1550.0),
    ("Sea of Okhotsk Approaches", 5800.0, 1200.0),
    ("South China Sea Approaches", 5100.0, 2000.0),
    ("Mediterranean East", 3100.0, 1700.0),
    ("Western Approaches", 1400.0, 1400.0),
    ("Central Pacific Theater", 6200.0, 2200.0),
    ("South Pacific Approaches", 6400.0, 2700.0),
]


def _dist2(a: Tuple[float, float], b: Tuple[float, float]) -> float:
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2


def region_center(
    region: Dict[str, Any],
    id_to_pt: Dict[int, Tuple[float, float]],
) -> Tuple[float, float]:
    c = region.get("center")
    if isinstance(c, (list, tuple)) and len(c) >= 2:
        return float(c[0]), float(c[1])
    pids = [int(x) for x in (region.get("province_ids") or [])]
    pts = [id_to_pt[p] for p in pids if p in id_to_pt]
    if not pts:
        return 0.0, 0.0
    return (
        sum(p[0] for p in pts) / len(pts),
        sum(p[1] for p in pts) / len(pts),
    )


def pick_label(cx: float, cy: float, used: set) -> str:
    ranked = sorted(WORLD_THEATER_SEEDS, key=lambda t: _dist2((cx, cy), (t[1], t[2])))
    for name, _, _ in ranked:
        if name not in used:
            used.add(name)
            return name
    n = 1
    while f"Frontier Theater {n}" in used:
        n += 1
    name = f"Frontier Theater {n}"
    used.add(name)
    return name


def relabel_payload(
    payload: Dict[str, Any],
    id_to_pt: Dict[int, Tuple[float, float]],
) -> Dict[str, Any]:
    regions = [dict(r) for r in (payload.get("regions") or [])]
    used = {
        str(r.get("name") or "")
        for r in regions
        if not is_generic_region_name(str(r.get("name") or ""))
    }
    changed = 0
    samples: List[Tuple[str, str, int]] = []
    for r in regions:
        name = str(r.get("name") or "")
        if not is_generic_region_name(name):
            used.add(name)
            continue
        cx, cy = region_center(r, id_to_pt)
        new_name = pick_label(cx, cy, used)
        if new_name != name:
            samples.append(
                (
                    name,
                    new_name,
                    int(r.get("province_count") or len(r.get("province_ids") or [])),
                )
            )
            r["name"] = new_name
            r["notes"] = (str(r.get("notes") or "") + " | relabeled from " + name).strip(" |")
            changed += 1
    out = dict(payload)
    out["regions"] = regions
    out["source"] = str(payload.get("source") or "strategic_regions") + "+relabel"
    out["relabeled_theater_n"] = changed
    out["_samples"] = samples
    return out



def run_on_dir(data_dir: Path, write: bool = False) -> Dict[str, Any]:
    reg_path = data_dir / "strategic_regions.json"
    geom_path = data_dir / "provinces_geometry.json"
    payload = json.loads(reg_path.read_text(encoding="utf-8"))
    geom = json.loads(geom_path.read_text(encoding="utf-8"))
    id_to_pt: Dict[int, Tuple[float, float]] = {}
    for g in geom.get("provinces") or []:
        pts = g.get("points") or []
        if not pts:
            continue
        pid = int(g["id"])
        if g.get("label_anchor") and len(g["label_anchor"]) >= 2:
            id_to_pt[pid] = (float(g["label_anchor"][0]), float(g["label_anchor"][1]))
        else:
            id_to_pt[pid] = (
                sum(float(p[0]) for p in pts) / len(pts),
                sum(float(p[1]) for p in pts) / len(pts),
            )
    out = relabel_payload(payload, id_to_pt)
    samples = out.pop("_samples", [])
    theater_left = sum(
        1 for r in out["regions"] if is_generic_region_name(str(r.get("name") or ""))
    )
    if write:
        # Drop internal samples key if present
        write_payload = {k: v for k, v in out.items() if not str(k).startswith("_")}
        reg_path.write_text(
            json.dumps(write_payload, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
    return {
        "wrote": write,
        "changed": int(out.get("relabeled_theater_n") or 0),
        "theater_n_remaining": theater_left,
        "region_count": len(out["regions"]),
        "samples": samples[:12],
        "path": str(reg_path),
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
    mode = "WROTE" if write else "DRY-RUN"
    print(f"[{mode}] {stats['path']}")
    print(
        f"  changed={stats['changed']} theater_n_left={stats['theater_n_remaining']} "
        f"regions={stats['region_count']}"
    )
    for old, new, n in stats.get("samples") or []:
        print(f"  {old} → {new} ({n})")
    ok = stats["theater_n_remaining"] == 0 and stats["region_count"] >= 12
    if not ok:
        print("FAIL relabel gates", file=sys.stderr)
        return 1
    print("PASS: no generic Theater leftovers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
