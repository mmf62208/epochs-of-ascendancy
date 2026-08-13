#!/usr/bin/env python3
"""Polish robotic world_full province names for immersion.

Targets:
  - "Hub Sector A/B/C..." → human place-like names unique across the board
  - "Ocean Basin lat_lon" → named sea-area labels (no raw coordinates)
  - Soften bare "X Theater" hub labels when uniqueness allows

Does not touch Europe-core gazetteer-quality names that already look real.

Usage:
  python3 tools/map_generation/scripts/polish_world_province_names.py \\
      --dir data/provinces_world_full [--write] [--dry-run]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]

SECTOR_RE = re.compile(r"^(?P<hub>.+?)\s+Sector\s+(?P<letter>[A-Z])\s*$", re.I)
# Compound leftovers e.g. "Tunis Sector B South" after partial renames
SECTOR_ANY_RE = re.compile(r"^(?P<head>.+?)\s+Sector\s+(?P<letter>[A-Z])(?:\s+(?P<tail>.+))?$", re.I)
BASIN_COORD_RE = re.compile(
    r"^(?P<body>.+?)\s+Basin\s+(?P<lon>-?\d+)_(?P<lat>-?\d+)\s*$", re.I
)
THEATER_RE = re.compile(r"^(?P<hub>.+?)\s+Theater\s*$", re.I)
HAS_SECTOR_WORD = re.compile(r"\bSector\b", re.I)
# Residual: "Mid-Atlantic Waters 2", "Chilean Basin Waters 4"
WATERS_NUM_RE = re.compile(
    r"^(?P<body>.+?(?:Waters|Basin|Deep|Approaches|Edge|Rise|Gap))\s+(?P<num>\d+)\s*$",
    re.I,
)
DISTRICT_RE = re.compile(r"^(?P<body>.+?)\s+District\s*$", re.I)
# Real-world place names that legitimately end in District
KEEP_DISTRICT_NAMES = {
    "lake district",
}

SECTOR_SUFFIXES = [
    "North",
    "South",
    "East",
    "West",
    "Central",
    "Coastal",
    "Inland",
    "Upper",
    "Lower",
    "Outer",
    "Inner",
    "Greater",
    "Harbor Approaches",
    "River Bend",
    "Highland Pass",
    "Lowland Flats",
    "Trade Crossroads",
    "Mining District",
    "Agricultural Belt",
    "Frontier March",
    "Upland Ridge",
    "Coastal Belt",
    "Valley Floor",
    "Plateau Edge",
    "Industrial Spur",
    "Port District",
]

OCEAN_BANDS: Dict[str, List[str]] = {
    "atlantic": [
        "North Atlantic Deep",
        "Mid-Atlantic Waters",
        "South Atlantic Basin",
        "Labrador Approaches",
        "Sargasso Sea Waters",
        "Guinea Basin Waters",
        "Argentine Basin Waters",
        "Cape Basin Approaches",
        "Norwegian Sea Edge",
        "Caribbean Approaches",
    ],
    "pacific": [
        "North Pacific Deep",
        "Central Pacific Waters",
        "South Pacific Basin",
        "Kuril Approaches",
        "Philippine Sea Edge",
        "Coral Sea Approaches",
        "Tasman Sea Edge",
        "Bering Approaches",
        "Chilean Basin Waters",
        "Hawaii Approaches",
    ],
    "indian": [
        "Arabian Sea Deep",
        "Bay of Bengal Approaches",
        "Central Indian Basin",
        "Mozambique Channel Edge",
        "Andaman Sea Edge",
        "Mascarene Basin Waters",
        "Australian Bight Edge",
        "Gulf of Aden Approaches",
        "Red Sea Approaches",
        "South Indian Deep",
    ],
    "arctic": [
        "Barents Approaches",
        "Kara Sea Edge",
        "Laptev Approaches",
        "East Siberian Waters",
        "Beaufort Approaches",
        "Greenland Sea Edge",
    ],
    "default": [
        "Open Ocean North",
        "Open Ocean Central",
        "Open Ocean South",
        "Deep Basin West",
        "Deep Basin East",
        "Remote Sea Approaches",
    ],
}

# Extra unique sea labels for numbered Waters residuals (no trailing digits).
SEA_UNIQUE_POOL: List[str] = [
    "Azores Gap",
    "Canary Rise",
    "Bermuda Rise",
    "Cape Verde Basin",
    "Walvis Ridge Waters",
    "Rio Grande Rise",
    "Falkland Approaches",
    "Scotia Sea Edge",
    "Drake Passage Edge",
    "Agulhas Basin",
    "Crozet Basin",
    "Kerguelen Plateau Edge",
    "Ninetyeast Ridge Waters",
    "Wharton Basin",
    "Perth Basin Edge",
    "Tasman Abyssal",
    "Lord Howe Rise",
    "Coral Sea Deep",
    "Philippine Deep Approaches",
    "Marianas Basin Edge",
    "Emperor Seamount Chain",
    "Aleutian Abyssal",
    "Gulf of Alaska Edge",
    "California Current Waters",
    "Clipperton Fracture Zone",
    "East Pacific Rise North",
    "East Pacific Rise South",
    "Nazca Ridge Waters",
    "Peru-Chile Trench Edge",
    "Magellan Approaches",
    "Labrador Basin Deep",
    "Irminger Sea Edge",
    "Rockall Trough",
    "Bay of Biscay Approaches",
    "Western Approaches Deep",
    "Celtic Sea Edge",
    "North Sea Approaches",
    "Baltic Approaches",
    "Black Sea Approaches",
    "Aegean Approaches",
    "Levantine Basin Edge",
    "Tyrrhenian Approaches",
    "Adriatic Approaches",
    "Ionian Deep",
    "Red Sea Central",
    "Gulf of Aden Deep",
    "Arabian Sea Central",
    "Laccadive Sea Edge",
    "Andaman Deep",
    "South China Sea Edge",
    "East China Sea Edge",
    "Yellow Sea Approaches",
    "Sea of Japan Edge",
    "Okhotsk Approaches",
    "Bering Sea Central",
    "Chukchi Approaches",
    "Beaufort Sea Edge",
    "Greenland Sea Deep",
    "Norwegian Basin",
    "Barents Central",
]


def _used_lower(used: set) -> set:
    return {u.lower() for u in used}


def next_unique(candidate: str, used: set) -> str:
    base = (candidate or "Unnamed District").strip()
    if not base:
        base = "Unnamed District"
    lower = _used_lower(used)
    if base.lower() not in lower:
        used.add(base)
        return base
    n = 2
    while True:
        cand = f"{base} {n}"
        if cand.lower() not in lower:
            used.add(cand)
            return cand
        n += 1


def polish_sector_name(hub: str, letter: str, used: set) -> str:
    hub = hub.strip()
    # Drop trailing "Theater" from hub if present
    hub = re.sub(r"\s+Theater$", "", hub, flags=re.I).strip()
    idx = ord(letter.upper()) - ord("A")
    if idx < 0:
        idx = 0
    # Prefer hub + ordinal suffix
    suffixes = SECTOR_SUFFIXES
    for offset in range(len(suffixes)):
        suf = suffixes[(idx + offset) % len(suffixes)]
        cand = f"{hub} {suf}".strip()
        if cand.lower() not in _used_lower(used):
            used.add(cand)
            return cand
    return next_unique(f"{hub} District", used)


def polish_basin_name(body: str, lon: int, lat: int, used: set) -> str:
    body_l = body.lower()
    key = "default"
    for ocean in ("atlantic", "pacific", "indian", "arctic"):
        if ocean in body_l:
            key = ocean
            break
    pool = list(OCEAN_BANDS.get(key) or OCEAN_BANDS["default"])
    # Pick band by lat/lon coarsely for variety
    band_i = (abs(lat) // 12 + abs(lon) // 24) % len(pool)
    # Prefer lat-based hemisphere labels first
    if key == "atlantic":
        if lat > 40:
            prefer = "North Atlantic Deep"
        elif lat < -20:
            prefer = "South Atlantic Basin"
        else:
            prefer = pool[band_i]
    elif key == "pacific":
        if lat > 30:
            prefer = "North Pacific Deep"
        elif lat < -20:
            prefer = "South Pacific Basin"
        else:
            prefer = pool[band_i]
    elif key == "indian":
        if lon > 90:
            prefer = "Bay of Bengal Approaches"
        elif lat > 10:
            prefer = "Arabian Sea Deep"
        else:
            prefer = pool[band_i]
    else:
        prefer = pool[band_i]
    if prefer.lower() not in _used_lower(used):
        used.add(prefer)
        return prefer
    for name in pool:
        if name.lower() not in _used_lower(used):
            used.add(name)
            return name
    return next_unique(prefer, used)


def polish_theater_name(hub: str, used: set) -> str:
    hub = hub.strip()
    # "Tokyo Theater" → keep if unique short form, else "Tokyo Region"
    for cand in (hub, f"{hub} Region", f"{hub} Approaches", f"Greater {hub}"):
        if cand.lower() not in _used_lower(used):
            used.add(cand)
            return cand
    return next_unique(hub, used)


def is_robotic(name: str) -> bool:
    n = str(name or "").strip()
    if SECTOR_RE.match(n) or SECTOR_ANY_RE.match(n) or BASIN_COORD_RE.match(n):
        return True
    if HAS_SECTOR_WORD.search(n):
        return True
    if THEATER_RE.match(n):
        return True
    if re.search(r"-?\d+_-?\d+", n):
        return True
    return False


def is_residual_label(name: str) -> bool:
    """Broader residual set: robotic + numbered Waters + land District outliers."""
    n = str(name or "").strip()
    if not n:
        return False
    if is_robotic(n):
        return True
    if WATERS_NUM_RE.match(n):
        return True
    m = DISTRICT_RE.match(n)
    if m and m.group(0).lower() not in KEEP_DISTRICT_NAMES:
        return True
    return False


def polish_numbered_waters(body: str, used: set) -> str:
    """Replace 'Mid-Atlantic Waters 7' with a unique unnumbered sea label."""
    body = re.sub(r"\s+\d+$", "", (body or "").strip())
    body = body.strip() or "Open Ocean"
    # Prefer body without number if free
    if body.lower() not in _used_lower(used):
        used.add(body)
        return body
    # Body + cardinal / sea suffixes
    for suf in (
        "North",
        "South",
        "East",
        "West",
        "Central",
        "Outer",
        "Inner",
        "Deep",
        "Rise",
        "Trough",
        "Abyssal",
        "Approaches",
    ):
        cand = f"{body} {suf}".strip()
        # Avoid re-introducing pure "Waters N" style
        if re.search(r"\s+\d+$", cand):
            continue
        if cand.lower() not in _used_lower(used):
            used.add(cand)
            return cand
    for name in SEA_UNIQUE_POOL:
        if name.lower() not in _used_lower(used):
            used.add(name)
            return name
    return next_unique(body, used)


def polish_district_name(body: str, used: set) -> str:
    body = (body or "").strip()
    if not body:
        return next_unique("Frontier March", used)
    for cand in (
        body,
        f"{body} Province",
        f"{body} Highlands",
        f"Greater {body}",
        f"{body} Coast",
    ):
        if cand.lower() not in _used_lower(used):
            used.add(cand)
            return cand
    return next_unique(body, used)


def polish_names(provinces: List[Dict[str, Any]]) -> Dict[str, Any]:
    used: set = set()
    # Reserve all non-residual names first
    for p in provinces:
        n = str(p.get("name") or "").strip()
        if n and not is_residual_label(n):
            used.add(n)

    changed = 0
    sector_n = 0
    basin_n = 0
    theater_n = 0
    waters_n = 0
    district_n = 0
    samples: List[Tuple[int, str, str]] = []

    for p in provinces:
        old = str(p.get("name") or "").strip()
        if not old:
            continue
        new = old
        m = SECTOR_RE.match(old) or SECTOR_ANY_RE.match(old)
        if m:
            hub = m.groupdict().get("hub") or m.groupdict().get("head") or old
            letter = m.group("letter")
            # Strip accidental nested sector tokens from hub
            hub = re.sub(r"\s+Sector\s+[A-Z]\b", "", hub, flags=re.I).strip()
            new = polish_sector_name(hub, letter, used)
            sector_n += 1
        elif HAS_SECTOR_WORD.search(old):
            # e.g. "Sargasso Sea Sector" / "Sargasso Sea Sector 2"
            cleaned = HAS_SECTOR_WORD.sub("Waters", old).strip()
            cleaned = re.sub(r"\s+\d+$", "", cleaned).strip()
            new = next_unique(cleaned or "Open Ocean Waters", used)
            sector_n += 1
        else:
            m2 = BASIN_COORD_RE.match(old)
            if m2:
                new = polish_basin_name(
                    m2.group("body"),
                    int(m2.group("lon")),
                    int(m2.group("lat")),
                    used,
                )
                basin_n += 1
            else:
                m3 = THEATER_RE.match(old)
                if m3:
                    # Only rewrite if hub alone is free or we can form Region
                    hub = m3.group("hub")
                    if hub.lower() not in _used_lower(used) or f"{hub} Region".lower() not in _used_lower(
                        used
                    ):
                        # free old name slot then claim new
                        if old in used:
                            used.discard(old)
                        new = polish_theater_name(hub, used)
                        theater_n += 1
                    else:
                        used.add(old)
                else:
                    mw = WATERS_NUM_RE.match(old)
                    if mw:
                        if old in used:
                            used.discard(old)
                        new = polish_numbered_waters(mw.group("body"), used)
                        waters_n += 1
                    else:
                        md = DISTRICT_RE.match(old)
                        if md and old.lower() not in KEEP_DISTRICT_NAMES:
                            if old in used:
                                used.discard(old)
                            new = polish_district_name(md.group("body"), used)
                            district_n += 1
                        else:
                            used.add(old)
                            continue

        if new != old:
            p["name"] = new
            changed += 1
            if len(samples) < 16:
                samples.append((int(p["id"]), old, new))
        else:
            used.add(new)

    # Uniqueness hard check
    names = [str(p.get("name") or "") for p in provinces]
    uniq = len(set(names))
    residual_left = sum(1 for p in provinces if is_residual_label(str(p.get("name") or "")))
    return {
        "changed": changed,
        "sector_renamed": sector_n,
        "basin_renamed": basin_n,
        "theater_softened": theater_n,
        "waters_unnumbered": waters_n,
        "district_softened": district_n,
        "unique_names": uniq,
        "total": len(provinces),
        "samples": samples,
        "robotic_remaining": sum(1 for p in provinces if is_robotic(str(p.get("name") or ""))),
        "residual_remaining": residual_left,
    }


def run_on_dir(data_dir: Path, write: bool = False) -> Dict[str, Any]:
    base_path = data_dir / "provinces_base.json"
    payload = json.loads(base_path.read_text(encoding="utf-8"))
    provinces = payload.get("provinces") or []
    stats = polish_names(provinces)
    if write:
        payload["provinces"] = provinces
        base_path.write_text(
            json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
    stats["wrote"] = write
    stats["path"] = str(base_path)
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
    mode = "WROTE" if write else "DRY-RUN"
    print(f"[{mode}] {stats['path']}")
    print(
        "  changed={changed} sector={sector_renamed} basin={basin_renamed} "
        "theater={theater_softened} unique={unique_names}/{total} robotic_left={robotic_remaining}".format(
            **stats
        )
    )
    for pid, old, new in stats.get("samples") or []:
        print(f"  sample {pid}: {old!r} → {new!r}")
    ok = (
        stats["unique_names"] == stats["total"]
        and stats["robotic_remaining"] == 0
        and stats["changed"] >= 1
    )
    # dry-run after write may have changed=0 — still ok if robotic_left 0
    if write or stats["robotic_remaining"] == 0:
        ok = stats["unique_names"] == stats["total"] and stats["robotic_remaining"] == 0
    if not ok:
        print("FAIL name polish gates", file=sys.stderr)
        return 1
    print("PASS: unique names, zero Sector/Basin-coord robotic labels")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
