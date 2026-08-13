#!/usr/bin/env python3
"""Relocate densify artifacts that landed in the UK/Europe band.

Some world_full densify "Reach/Interior/Maghreb" provinces were authored with
centroids over northern Europe, which stole UK land picks. This script
translates known artifact groups to North Africa coordinates and updates
hierarchy + strategic_regions membership.

Run from repo root:
  python3 tools/map_generation/scripts/relocate_uk_band_artifacts.py
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3] / "data" / "provinces_world_full"

# Target centroids (map space) for densify families that landed in the wrong theater.
RELOCATE_GROUPS: dict[str, dict[int, tuple[float, float]]] = {
    "maghreb_interior": {
        50913: (4120.0, 1780.0),
        50914: (4140.0, 1850.0),
        50915: (4220.0, 1820.0),
        50916: (4040.0, 1840.0),
        50917: (4130.0, 1810.0),
        50918: (4160.0, 1880.0),
    },
    "atlas_interior": {
        20032: (4100.0, 1750.0),
        20409: (4115.0, 1740.0),
        20410: (4085.0, 1765.0),
        20411: (4125.0, 1755.0),
        20412: (4075.0, 1745.0),
        20413: (4105.0, 1730.0),
        20414: (4090.0, 1775.0),
    },
    "tripoli_maghreb": {
        20013: (4240.0, 1850.0),
        20295: (4255.0, 1840.0),
        20296: (4225.0, 1860.0),
        20297: (4260.0, 1855.0),
        20298: (4220.0, 1845.0),
        20299: (4245.0, 1835.0),
        20300: (4230.0, 1865.0),
    },
    # Cape Town densify sat in Maghreb latitudes; pull to Cape Town Table band.
    "cape_town": {
        20023: (4545.0, 2819.0),
        20355: (4555.0, 2810.0),
        20356: (4535.0, 2830.0),
        20357: (4565.0, 2815.0),
        20358: (4525.0, 2825.0),
        20359: (4550.0, 2805.0),
        20360: (4540.0, 2835.0),
    },
    "pretoria": {
        9407: (4736.0, 2625.0),
    },
    # Southern France densify wrongly in Maghreb band.
    "southern_france": {
        9364: (4220.0, 1455.0),  # Marseille
        9195: (4120.0, 1475.0),  # Toulouse
        9252: (4180.0, 1465.0),  # Montpellier
        9194: (4050.0, 1420.0),  # Bordeaux
        9197: (4080.0, 1360.0),  # Nantes
        9365: (4120.0, 1355.0),  # Tours
    },
    # Russian densify parked on East Asia (stole Beijing / Seoul picks).
    "russia_misplaced": {
        10: (4300.0, 950.0),   # Vorkuta → High North
        25: (4450.0, 1150.0),  # Ufa → Western Russia / Urals
    },
    "uk_misplaced": {
        9424: (4140.0, 1255.0),  # Liverpool
        9374: (4120.0, 1295.0),  # Cardiff
    },
    "iberia_misplaced": {
        9011: (3850.0, 1400.0),  # Porto
        9026: (3900.0, 1520.0),  # Seville
        9192: (4220.0, 1410.0),  # Barcelona
    },
    "balkans_italy": {
        9358: (4285.0, 1510.0),  # Athens
        9382: (4380.0, 1420.0),  # Bucharest
        9402: (4240.0, 1480.0),  # Catanzaro
    },
    "oceania": {
        9332: (7100.0, 2880.0),   # Perth
        9337: (7600.0, 2750.0),   # Brisbane
        20074: (7500.0, 2840.0),  # Australia Sydney
    },
    "east_west_africa": {
        20020: (4900.0, 1950.0),  # Addis Ababa primary (+ family placed at run time)
        20022: (4000.0, 1950.0),  # Lagos Coast primary
    },
}

# pid -> strategic region id after relocate
REGION_FORCE: dict[int, int] = {}
for _pid in RELOCATE_GROUPS["maghreb_interior"]:
    REGION_FORCE[_pid] = 9
for _pid in RELOCATE_GROUPS["atlas_interior"]:
    REGION_FORCE[_pid] = 9
for _pid in RELOCATE_GROUPS["tripoli_maghreb"]:
    REGION_FORCE[_pid] = 9
for _pid in RELOCATE_GROUPS["cape_town"]:
    REGION_FORCE[_pid] = 34  # Southern Africa
for _pid in RELOCATE_GROUPS["pretoria"]:
    REGION_FORCE[_pid] = 34
for _pid in RELOCATE_GROUPS["southern_france"]:
    REGION_FORCE[_pid] = 14  # France
for _pid in RELOCATE_GROUPS["russia_misplaced"]:
    REGION_FORCE[_pid] = 17 if _pid == 10 else 6
for _pid in RELOCATE_GROUPS["uk_misplaced"]:
    REGION_FORCE[_pid] = 21
for _pid in RELOCATE_GROUPS["iberia_misplaced"]:
    REGION_FORCE[_pid] = 12
for _pid in RELOCATE_GROUPS["balkans_italy"]:
    REGION_FORCE[_pid] = 8 if _pid != 9402 else 11
for _pid in RELOCATE_GROUPS["oceania"]:
    REGION_FORCE[_pid] = 31
for _pid in RELOCATE_GROUPS["east_west_africa"]:
    REGION_FORCE[_pid] = 23

NORTH_AFRICA_REGION = 9
BRITISH_ISLES_REGION = 21


def poly_centroid(pts: list) -> list[float] | None:
    if not pts:
        return None
    if len(pts) < 3:
        return [sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)]
    a = cx = cy = 0.0
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        cross = x1 * y2 - x2 * y1
        a += cross
        cx += (x1 + x2) * cross
        cy += (y1 + y2) * cross
    a *= 0.5
    if abs(a) < 1e-9:
        return [sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)]
    return [cx / (6 * a), cy / (6 * a)]


def contains(pts: list, x: float, y: float) -> bool:
    n = len(pts)
    inside = False
    j = n - 1
    for i in range(n):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi + 1e-30) + xi):
            inside = not inside
        j = i
    return inside


def main() -> None:
    geo_path = ROOT / "provinces_geometry.json"
    doc = json.loads(geo_path.read_text())
    targets: dict[int, tuple[float, float]] = {}
    for group in RELOCATE_GROUPS.values():
        targets.update(group)

    moved = []
    for p in doc["provinces"]:
        pid = int(p["id"])
        if pid not in targets:
            continue
        pts = p.get("points") or []
        if len(pts) < 3:
            continue
        c = poly_centroid(pts)
        if c is None:
            continue
        tx, ty = targets[pid]
        dx, dy = tx - c[0], ty - c[1]
        p["points"] = [[pt[0] + dx, pt[1] + dy] for pt in pts]
        p["label_anchor"] = poly_centroid(p["points"])
        meta = p.get("meta") if isinstance(p.get("meta"), dict) else {}
        meta["relocated_from_uk_band"] = True
        meta["relocated_dx"] = dx
        meta["relocated_dy"] = dy
        p["meta"] = meta
        moved.append((pid, round(c[0], 1), round(c[1], 1), tx, ty))

    # Fix anchors outside own poly (all provinces)
    anchor_fixed = 0
    for p in doc["provinces"]:
        pts = p.get("points") or []
        if len(pts) < 3:
            continue
        a = p.get("label_anchor")
        c = poly_centroid(pts)
        if a is None or len(a) < 2 or not contains(pts, float(a[0]), float(a[1])):
            p["label_anchor"] = c
            anchor_fixed += 1

    bak = ROOT / "provinces_geometry.json.pre_uk_band_relocate"
    if not bak.exists():
        bak.write_text(geo_path.read_text())
    geo_path.write_text(json.dumps(doc, indent=2) + "\n")

    # Membership + strategic regions
    all_pids = set(targets)
    for era in ("1910", "1918", "1936", "2026"):
        path = ROOT / f"hierarchy_membership_{era}.json"
        if not path.exists():
            continue
        m = json.loads(path.read_text())
        p2r = m.get("province_to_region", {})
        for pid in all_pids:
            p2r[str(pid)] = int(REGION_FORCE.get(pid, NORTH_AFRICA_REGION))
        m["province_to_region"] = p2r
        path.write_text(json.dumps(m, indent=2) + "\n")

    sr_path = ROOT / "strategic_regions.json"
    sr = json.loads(sr_path.read_text())
    # Rebuild province_ids: remove relocated pids from every region, then add to forced region.
    for r in sr.get("regions", []):
        pids = set(int(x) for x in r.get("province_ids", []))
        pids -= all_pids
        rid = int(r.get("id", 0))
        for pid, dest in REGION_FORCE.items():
            if dest == rid:
                pids.add(pid)
        r["province_ids"] = sorted(pids)
        r["province_count"] = len(pids)
    sr_path.write_text(json.dumps(sr, indent=2) + "\n")

    # London must only contain itself after relocate
    london = next(p for p in doc["provinces"] if int(p["id"]) == 9275)
    la = london["label_anchor"]
    hits = []
    for p in doc["provinces"]:
        pts = p.get("points") or []
        if len(pts) >= 3 and contains(pts, float(la[0]), float(la[1])):
            hits.append(int(p["id"]))

    print(f"relocated {len(moved)} provinces; anchors_fixed={anchor_fixed}")
    for row in moved:
        print(" ", row)
    print("london_containers", hits)
    if hits != [9275]:
        raise SystemExit("London containment check failed")
    print("OK")


if __name__ == "__main__":
    main()
