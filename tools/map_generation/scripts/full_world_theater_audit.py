#!/usr/bin/env python3
"""Audit named land provinces: theater keyword match vs geometry centroid.

Reports ok / misplaced / unclassified counts. Does not mutate data.
Use after densify relocates to track remaining debt.

  python3 tools/map_generation/scripts/full_world_theater_audit.py
"""
from __future__ import annotations

import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3] / "data" / "provinces_world_full"

TH = {
    "uk_ie": (4120, 1275, 250, 160),
    "france": (4150, 1360, 250, 180),
    "iberia": (4000, 1470, 300, 200),
    "italy": (4220, 1420, 180, 180),
    "germany": (4220, 1270, 200, 140),
    "benelux": (4185, 1270, 120, 100),
    "scandi": (4240, 1180, 220, 180),
    "cee": (4300, 1300, 250, 180),
    "balkans": (4320, 1480, 220, 180),
    "anatolia": (4320, 1420, 200, 160),
    "russia_w": (4400, 1200, 400, 280),
    "high_north": (4300, 950, 350, 180),
    "maghreb": (4100, 1800, 300, 220),
    "egypt": (4290, 1450, 140, 120),
    "e_africa": (4900, 2000, 280, 240),
    "w_africa": (3950, 1920, 300, 240),
    "s_africa": (4650, 2700, 300, 240),
    "mena_east": (4400, 1450, 220, 180),
    "india": (4550, 1600, 280, 220),
    "china": (4650, 1400, 280, 200),
    "japan_kr": (4700, 1380, 220, 160),
    "se_asia": (4650, 1700, 280, 240),
    "na_east": (2300, 1150, 450, 280),
    "na_west": (1500, 1250, 450, 280),
    "latam_n": (2300, 1900, 500, 380),
    "latam_s": (2700, 2800, 450, 320),
    "oceania": (7400, 2850, 550, 300),
    "caucasus": (4450, 1450, 200, 160),
    "central_asia": (4800, 1200, 450, 280),
}

PHRASES = [
    ("new orleans", "na_east"),
    ("new york", "na_east"),
    ("los angeles", "na_west"),
    ("cape town", "s_africa"),
    ("addis ababa", "e_africa"),
    ("lagos coast", "w_africa"),
    ("buenos aires", "latam_s"),
    ("australia sydney", "oceania"),
    ("mexico city", "latam_n"),
]

# Minimal word map for audit (extend as needed)
WORDS: dict[str, str] = {}
for th, blob in {
    "uk_ie": "london liverpool glasgow edinburgh cardiff belfast dublin",
    "france": "paris lyon marseille bordeaux",
    "iberia": "madrid barcelona lisbon porto seville",
    "italy": "rome milan naples",
    "germany": "berlin hamburg munich",
    "maghreb": "casablanca algiers tunis",
    "egypt": "cairo alexandria",
    "china": "beijing shanghai",
    "japan_kr": "tokyo seoul osaka",
    "se_asia": "bangkok jakarta singapore manila",
    "na_east": "chicago boston miami",
    "na_west": "seattle portland denver",
    "oceania": "sydney melbourne brisbane perth",
    "s_africa": "johannesburg pretoria durban",
    "india": "delhi mumbai kolkata",
    "latam_s": "montevideo",
    "russia_w": "moscow kazan",
}.items():
    for w in blob.split():
        WORDS[w] = th


def poly_centroid(pts):
    if not pts:
        return None
    return [sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)]


def theater_for(nm: str):
    n = nm.lower()
    for phrase, th in sorted(PHRASES, key=lambda x: -len(x[0])):
        if phrase in n:
            return th
    for t in re.findall(r"[a-z0-9']+", n):
        if t in WORDS:
            return WORDS[t]
    return None


def in_th(c, th):
    cx, cy, hw, hh = TH[th]
    return abs(c[0] - cx) <= hw and abs(c[1] - cy) <= hh


def main() -> None:
    base = {
        int(p["id"]): p
        for p in json.loads((ROOT / "provinces_base.json").read_text())["provinces"]
    }
    geo = {
        int(p["id"]): p
        for p in json.loads((ROOT / "provinces_geometry.json").read_text())["provinces"]
    }
    ok = mis = unc = 0
    by = defaultdict(int)
    for pid, p in base.items():
        if pid not in geo:
            continue
        if str(p.get("terrain", "")).lower() in ("sea", "ocean"):
            continue
        th = theater_for(p["name"])
        if not th:
            unc += 1
            continue
        c = poly_centroid(geo[pid]["points"])
        if c and in_th(c, th):
            ok += 1
        else:
            mis += 1
            by[th] += 1
    print(f"ok={ok} misplaced={mis} unclassified={unc}")
    for th, n in sorted(by.items(), key=lambda x: -x[1]):
        print(f"  {th}: {n}")


if __name__ == "__main__":
    main()
