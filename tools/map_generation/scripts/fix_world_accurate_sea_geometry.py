#!/usr/bin/env python3
"""Reposition world_accurate sea/strait polygons to correct equirect centroids.

Playtest (2026-08): Danish Straits + English Channel rendered over Spain/Med
because many 950xxx seas keep wrong centroids after hybrid board assembly.
Land NUTS geometry is fine; seas/straits need name→(lon,lat) re-anchor.

Writes in place under data/provinces_world_accurate/provinces_geometry.json
(with .bak). Does not renumber IDs.
"""
from __future__ import annotations

import json
import math
import shutil
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[3]
BOARD = ROOT / "data" / "provinces_world_accurate"
W = 8192.0
H = 4096.0

# Name substring → (lon, lat). First match wins (order matters for specificity).
SEA_ANCHORS: List[Tuple[str, float, float]] = [
    ("danish straits", 12.0, 55.5),
    ("english channel", 1.0, 50.5),
    ("north sea", 3.0, 56.0),
    ("norwegian sea", 5.0, 64.0),
    ("baltic", 19.0, 56.0),
    ("gibraltar", -5.5, 36.0),
    ("bospor", 29.0, 41.1),
    ("suez", 32.3, 30.5),
    ("hormuz", 56.5, 26.5),
    ("malacca", 100.0, 3.0),
    ("tsushima", 129.5, 34.5),
    ("black sea", 34.0, 43.0),
    ("red sea", 38.0, 20.0),
    ("persian gulf", 52.0, 27.0),
    ("east china", 125.0, 30.0),
    ("south china", 114.0, 12.0),
    ("sea of japan", 135.0, 40.0),
    ("caribbean", -70.0, 15.0),
    ("gulf of mexico", -90.0, 25.0),
    ("north atlantic", -30.0, 50.0),
    ("tropical atlantic", -30.0, 15.0),
    ("south atlantic", -10.0, -20.0),
    ("mid indian", 70.0, -10.0),
    ("south indian", 80.0, -30.0),
    ("sargasso", -50.0, 30.0),
    ("bering", -170.0, 58.0),
    ("philippine", 135.0, 18.0),
    ("tasman", 160.0, -35.0),
    ("mozambique", 42.0, -18.0),
    ("aden", 48.0, 12.0),
    ("bay of bengal", 90.0, 15.0),
    ("westpac", 150.0, 20.0),
    ("cape basin", 15.0, -35.0),
    ("south pacific", -140.0, -20.0),
]


def lonlat_to_xy(lon: float, lat: float) -> Tuple[float, float]:
    x = (float(lon) + 180.0) / 360.0 * W
    y = (90.0 - float(lat)) / 180.0 * H
    return x, y


def centroid(pts: list) -> Optional[Tuple[float, float]]:
    if not pts:
        return None
    xs: List[float] = []
    ys: List[float] = []
    for p in pts:
        if isinstance(p, dict):
            xs.append(float(p.get("x", 0.0)))
            ys.append(float(p.get("y", 0.0)))
        elif isinstance(p, (list, tuple)) and len(p) >= 2:
            xs.append(float(p[0]))
            ys.append(float(p[1]))
    if not xs:
        return None
    return sum(xs) / len(xs), sum(ys) / len(ys)


def translate_points(pts: list, dx: float, dy: float) -> list:
    out = []
    for p in pts:
        if isinstance(p, dict):
            q = dict(p)
            q["x"] = float(p.get("x", 0.0)) + dx
            q["y"] = float(p.get("y", 0.0)) + dy
            out.append(q)
        elif isinstance(p, (list, tuple)) and len(p) >= 2:
            out.append([float(p[0]) + dx, float(p[1]) + dy])
        else:
            out.append(p)
    return out


def anchor_for_name(name: str) -> Optional[Tuple[float, float]]:
    nm = (name or "").lower()
    for key, lon, lat in SEA_ANCHORS:
        if key in nm:
            return lon, lat
    return None


def main() -> int:
    base_path = BOARD / "provinces_base.json"
    geo_path = BOARD / "provinces_geometry.json"
    base_raw = json.loads(base_path.read_text(encoding="utf-8"))
    geo_raw = json.loads(geo_path.read_text(encoding="utf-8"))
    bpro = base_raw.get("provinces", base_raw)
    gpro = geo_raw.get("provinces", geo_raw)
    if isinstance(bpro, list):
        bby: Dict[int, dict] = {int(p["id"]): p for p in bpro if isinstance(p, dict)}
    else:
        bby = {int(k): v for k, v in bpro.items()}
    if isinstance(gpro, list):
        g_list = gpro
        gby = {int(p["id"]): p for p in gpro if isinstance(p, dict)}
        geo_is_list = True
    else:
        gby = {int(k): v for k, v in gpro.items()}
        g_list = None
        geo_is_list = False

    moved = 0
    details = []
    for pid, p in bby.items():
        domain = str(p.get("domain", "")).lower()
        if domain not in ("sea", "strait", "ocean"):
            continue
        name = str(p.get("name") or "")
        anch = anchor_for_name(name)
        if anch is None:
            continue
        g = gby.get(pid)
        if not g:
            continue
        pts = g.get("points") or []
        c = centroid(pts)
        if c is None:
            continue
        tx, ty = lonlat_to_xy(anch[0], anch[1])
        dx, dy = tx - c[0], ty - c[1]
        # Only move if meaningfully wrong (map units in base equirect).
        dist = math.hypot(dx, dy)
        if dist < 40.0:
            continue
        g["points"] = translate_points(pts, dx, dy)
        # Keep label_anchor if present
        la = g.get("label_anchor")
        if isinstance(la, (list, tuple)) and len(la) >= 2:
            g["label_anchor"] = [float(la[0]) + dx, float(la[1]) + dy]
        elif isinstance(la, dict):
            la = dict(la)
            la["x"] = float(la.get("x", 0.0)) + dx
            la["y"] = float(la.get("y", 0.0)) + dy
            g["label_anchor"] = la
        meta = g.get("meta") if isinstance(g.get("meta"), dict) else {}
        meta["sea_reanchor_v1"] = {
            "lon": anch[0],
            "lat": anch[1],
            "dx": round(dx, 2),
            "dy": round(dy, 2),
            "dist": round(dist, 2),
        }
        g["meta"] = meta
        moved += 1
        details.append((pid, name, round(dist, 1), round(tx, 0), round(ty, 0)))

    bak = geo_path.with_suffix(".json.bak_pre_sea_reanchor")
    if not bak.exists():
        shutil.copy2(geo_path, bak)
    if geo_is_list:
        # write list form
        geo_raw["provinces"] = g_list
    else:
        geo_raw["provinces"] = {str(k): v for k, v in gby.items()}
    geo_path.write_text(json.dumps(geo_raw, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Reanchored {moved} sea/strait zones → {geo_path}")
    for row in details[:25]:
        print(" ", row)
    if moved == 0:
        print("No seas needed move (already near anchors).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
