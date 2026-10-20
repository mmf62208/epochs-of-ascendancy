#!/usr/bin/env python3
"""GAP-CHINA: split the 22 CHI blobs into 56 1936-style provinces.

Geometry is the live CHI rings clipped to lon/lat boxes. Natural Earth 10m
land is in the repo; admin-1 is not. The 22 blobs are the CHI land. Boxes
are rough 1936 ROC cuts. Paint order is coastal/small first so large western
boxes do not swallow them. CHI land still unclaimed after the 56 boxes
(the Manchuria-side leftover east of 117.5 E) is added to Chahar, the brief
default for that sliver.

18 kept IDs keep their numbers and take the named box. The 4 leftover blob
IDs 902487/902491/902496/902505 are reused for 4 of the 38 NEW names, by
largest overlap with the leftover's current ring, then the repo Beiping pin
for 902487, then nearest NEW centroid. The other 34 NEW names take
905855-905888 in CSV order.

Owners stay CHI in every era. Tags QNG/TIB/SIK/SHX/XSM/GXC/YUN/PRC/MAN do
not exist. Populations stay flavour-split by area. No new state tags.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Any, Callable, Dict, List, Mapping, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / "data" / "provinces_world_accurate"
NE_LAND = (
    ROOT
    / "tools"
    / "map_generation"
    / "data"
    / "cache"
    / "map_tiles"
    / "https_raw.githubusercontent.com_nvkelso_natural-earth-vector_master_geojson_ne_10m_land.geojson"
)
FIXTURE = ROOT / "tools" / "map_generation" / "fixtures" / "gap_china_parent_blobs.json"

CHI_BLOBS = (
    902487, 902491, 902493, 902496, 902504, 902505, 902514, 902521, 902523,
    902526, 902534, 902544, 902564, 902566, 902568, 902569, 902590, 902598,
    902601, 902633, 902634, 902646,
)
LEFTOVER_IDS = (902487, 902491, 902496, 902505)
NEW_ID_START = 905855
NEW_ID_END = 905888
ERA_YEARS = (1910, 1918, 1936, 1945, 2026)
STATE_CHN = 289
REGION_EAST_ASIA = 7
SUPER_EAST_ASIA = 3
KINMEN = 903981
YUEN_LONG = 902486
HONG_KONG = 905844
SEA_BENGAL = 950308

W_PX = 8192.0
H_PX = 4096.0
KM_PER_DEG = 111.32
# Pre-split CHI blob totals at the GAP-IBS tip. Re-read from these constants
# so a second run does not split already-split values.
PARENT_POP = 10865673
PARENT_FAC = 175
PARENT_COAL = 173
PARENT_TUNG = 346
ORIG_LEFTOVER_NAMES = {
    902487: "CHN North",
    902491: "CHN East",
    902496: "CHN North",
    902505: "CHN East",
}

Point = Tuple[float, float]
Ring = List[Point]

# name, rect(west,east,south,north), kept_id or 0, city or "".
SLOTS: List[Tuple[str, Tuple[float, float, float, float], int, str]] = [
    ("Dzungaria (Ili/Tacheng)", (80.0, 91.0, 43.4, 49.5), 902493, ""),
    ("Urumqi-Turfan", (86.0, 92.5, 41.5, 44.2), 0, "Urumqi"),
    ("Kumul (Hami)", (91.5, 97.5, 40.5, 45.2), 902514, "Hami"),
    ("Kashgaria", (73.5, 79.5, 36.0, 41.0), 902523, "Kashgar"),
    ("Aksu-Kucha", (79.0, 86.0, 39.8, 43.5), 902504, "Aksu"),
    ("Khotan-Lop", (77.5, 92.0, 35.5, 40.5), 902534, "Khotan"),
    ("Ngari (W. Tibet)", (78.0, 86.0, 29.5, 36.2), 902569, ""),
    ("U-Tsang (Lhasa)", (86.0, 94.0, 27.5, 32.2), 0, "Lhasa"),
    ("Changtang (N. Tibet)", (85.0, 94.5, 32.0, 36.5), 0, ""),
    ("Xikang West (Chamdo)", (94.0, 97.8, 28.5, 32.8), 902601, "Chamdo"),
    ("Xikang East (Kangding)", (97.5, 103.2, 27.8, 32.8), 0, "Kangding"),
    ("Qinghai East (Xining)", (97.0, 103.8, 34.0, 39.2), 0, "Xining"),
    ("Qinghai West (Tsaidam)", (90.0, 97.5, 34.0, 39.5), 902568, ""),
    ("Gansu Hexi Corridor", (94.5, 103.5, 37.4, 42.9), 902526, ""),
    ("Gansu East (Lanzhou)", (102.0, 108.5, 32.8, 37.6), 902566, "Lanzhou"),
    ("Ningxia", (104.0, 107.8, 36.6, 40.2), 0, "Yinchuan"),
    ("Suiyuan West (Hetao)", (106.0, 111.2, 39.4, 42.7), 902544, ""),
    ("Suiyuan East (Guisui)", (111.0, 114.6, 39.4, 42.6), 0, "Guisui"),
    ("Chahar", (112.5, 117.5, 40.5, 45.2), 902521, "Kalgan"),
    ("Shanxi North (Datong)", (111.0, 114.6, 38.4, 40.8), 0, "Datong"),
    ("Shanxi South (Taiyuan)", (110.5, 114.6, 35.4, 39.0), 0, "Taiyuan"),
    ("Shaanbei (Yanan)", (107.2, 111.6, 35.8, 39.6), 0, "Yanan"),
    ("Guanzhong (Xian)", (106.4, 110.6, 33.7, 36.0), 0, "Xian"),
    ("Shaannan (Hanzhong)", (105.4, 111.2, 31.4, 34.0), 0, "Hanzhong"),
    ("Hebei North (Peiping-Tientsin)", (114.4, 118.6, 38.4, 41.6), 0, "Peiping"),
    ("Hebei South (Baoding)", (114.4, 118.2, 36.0, 38.5), 0, "Baoding"),
    ("Shandong West (Jinan)", (115.4, 118.6, 34.5, 38.0), 902564, "Jinan"),
    ("Shandong East (Qingdao)", (118.4, 122.8, 35.0, 38.3), 0, "Qingdao"),
    ("Henan North (Kaifeng)", (110.4, 116.6, 33.4, 36.3), 0, "Kaifeng"),
    ("Henan South (Xinyang)", (110.4, 116.6, 31.2, 33.5), 0, "Xinyang"),
    ("Jiangsu North (Xuzhou)", (116.2, 120.6, 32.9, 35.1), 0, "Xuzhou"),
    ("Jiangsu South (Shanghai-Nanking)", (118.0, 122.2, 30.7, 33.1), 0, "Shanghai"),
    ("Anhui North (Bengbu)", (115.4, 118.6, 32.0, 34.5), 0, "Bengbu"),
    ("Anhui South (Anking)", (115.4, 119.6, 29.4, 32.1), 902590, "Anking"),
    ("Zhejiang North (Hangzhou)", (118.4, 122.6, 29.0, 31.3), 0, "Hangzhou"),
    ("Zhejiang South (Wenzhou)", (118.4, 122.6, 27.0, 29.1), 0, "Wenzhou"),
    ("Fujian North (Foochow)", (116.5, 120.6, 25.4, 28.4), 0, "Foochow"),
    ("Fujian South (Amoy)", (116.5, 120.8, 23.4, 25.5), 902633, "Amoy"),
    ("Jiangxi North (Nanchang)", (114.0, 118.5, 27.4, 30.2), 0, "Nanchang"),
    ("Jiangxi South (Ganzhou)", (113.5, 117.2, 24.4, 27.5), 0, "Ganzhou"),
    ("Hubei East (Wuhan)", (112.4, 116.1, 29.4, 32.6), 0, "Wuhan"),
    ("Hubei West (Yichang)", (108.4, 112.5, 29.3, 32.9), 0, "Yichang"),
    ("Hunan North (Changsha)", (110.4, 114.6, 27.4, 30.3), 902598, "Changsha"),
    ("Hunan South (Hengyang)", (109.4, 114.1, 24.5, 27.5), 0, "Hengyang"),
    ("Sichuan West (Chengdu)", (101.5, 105.6, 28.4, 32.6), 0, "Chengdu"),
    ("Sichuan North (Nanchong)", (105.4, 108.6, 30.4, 32.9), 0, "Nanchong"),
    ("Sichuan East (Chungking)", (105.4, 110.1, 28.0, 30.5), 0, "Chungking"),
    ("Guizhou", (103.5, 109.6, 24.4, 29.2), 0, "Kweiyang"),
    ("Yunnan East (Kunming)", (100.8, 106.0, 22.4, 27.6), 902634, "Kunming"),
    ("Yunnan West (Dali)", (97.4, 101.2, 22.8, 28.2), 0, "Dali"),
    ("Guangxi West (Nanning)", (104.4, 109.6, 21.4, 25.5), 0, "Nanning"),
    ("Guangxi East (Wuzhou)", (109.4, 112.6, 21.4, 25.5), 902646, "Wuzhou"),
    ("Guangdong Central (Canton)", (111.4, 115.6, 21.4, 25.4), 0, "Canton"),
    ("Guangdong East (Swatow)", (115.4, 117.6, 22.4, 24.9), 0, "Swatow"),
    ("Guangdong West (Leizhou)", (109.4, 112.2, 20.1, 22.5), 0, "Luichow"),
    ("Hainan", (108.5, 111.4, 18.1, 20.2), 0, "Haikou"),
]

PAINT_ORDER = [
    "Hainan", "Guangdong West (Leizhou)", "Guangdong East (Swatow)", "Guangdong Central (Canton)",
    "Fujian South (Amoy)", "Fujian North (Foochow)", "Zhejiang South (Wenzhou)", "Zhejiang North (Hangzhou)",
    "Jiangsu South (Shanghai-Nanking)", "Jiangsu North (Xuzhou)", "Shandong East (Qingdao)", "Shandong West (Jinan)",
    "Anhui South (Anking)", "Anhui North (Bengbu)", "Jiangxi South (Ganzhou)", "Jiangxi North (Nanchang)",
    "Hunan South (Hengyang)", "Hunan North (Changsha)", "Hubei East (Wuhan)", "Hubei West (Yichang)",
    "Shanxi South (Taiyuan)", "Shanxi North (Datong)",
    "Henan South (Xinyang)", "Henan North (Kaifeng)",
    "Hebei South (Baoding)", "Hebei North (Peiping-Tientsin)",
    "Guangxi East (Wuzhou)", "Guangxi West (Nanning)", "Guizhou", "Yunnan East (Kunming)", "Yunnan West (Dali)",
    "Sichuan East (Chungking)", "Sichuan North (Nanchong)", "Sichuan West (Chengdu)",
    "Shaannan (Hanzhong)", "Guanzhong (Xian)", "Shaanbei (Yanan)",
    "Ningxia",
    "Suiyuan East (Guisui)", "Suiyuan West (Hetao)", "Chahar",
    "Gansu East (Lanzhou)", "Gansu Hexi Corridor",
    "Qinghai East (Xining)", "Qinghai West (Tsaidam)",
    "Xikang East (Kangding)", "Xikang West (Chamdo)",
    "U-Tsang (Lhasa)", "Changtang (N. Tibet)", "Ngari (W. Tibet)",
    "Khotan-Lop", "Kashgaria", "Aksu-Kucha", "Urumqi-Turfan", "Kumul (Hami)", "Dzungaria (Ili/Tacheng)",
]


def emit_existing_id(pid: int) -> int:
    return int(pid)  # GAP_CHINA_PID identity


def use_all_leftovers() -> bool:
    return True  # GAP_CHINA_LEFTOVER


def _load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _dumps(doc: Any) -> str:
    return json.dumps(doc, indent=2, ensure_ascii=False) + "\n"


def _lonlat_to_canvas(lon: float, lat: float) -> Point:
    x = (lon - (-180.0)) / 360.0 * W_PX
    y = (lat - 83.0) / (-139.0) * H_PX
    return (x, y)


def _canvas_to_lonlat(x: float, y: float) -> Point:
    lon = -180.0 + (x / W_PX) * 360.0
    lat = 83.0 + (y / H_PX) * (-139.0)
    return (lon, lat)


def _ring_area(ring: Sequence[Point]) -> float:
    area = 0.0
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        area += x1 * y2 - x2 * y1
    return area / 2.0


def _area_centroid(ring: Sequence[Point]) -> Point:
    acc_a = 0.0
    cx = 0.0
    cy = 0.0
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        cross = x1 * y2 - x2 * y1
        acc_a += cross
        cx += (x1 + x2) * cross
        cy += (y1 + y2) * cross
    if abs(acc_a) < 1e-18:
        return (sum(p[0] for p in ring) / n, sum(p[1] for p in ring) / n)
    return (cx / (3.0 * acc_a), cy / (3.0 * acc_a))


def _open_ring(ring: Sequence[Point]) -> List[Point]:
    out = [(float(p[0]), float(p[1])) for p in ring]
    if len(out) >= 2 and out[0] == out[-1]:
        out = out[:-1]
    return out


def _ensure_ccw(ring: Sequence[Point]) -> List[Point]:
    out = _open_ring(ring)
    if _ring_area(out) < 0:
        out.reverse()
    return out


def _dedupe(ring: Sequence[Point]) -> List[Point]:
    cleaned: List[Point] = []
    for p in ring:
        if not cleaned or abs(p[0] - cleaned[-1][0]) > 1e-9 or abs(p[1] - cleaned[-1][1]) > 1e-9:
            cleaned.append((float(p[0]), float(p[1])))
    if len(cleaned) > 1 and abs(cleaned[0][0] - cleaned[-1][0]) < 1e-9 and abs(cleaned[0][1] - cleaned[-1][1]) < 1e-9:
        cleaned.pop()
    return cleaned


def bridge_rings(rings: Sequence[Sequence[Point]]) -> List[Point]:
    parts = [_ensure_ccw(r) for r in rings if len(r) >= 3]
    parts.sort(key=lambda r: (-abs(_ring_area(r)), r[0][0], r[0][1]))
    if not parts:
        return []
    acc = list(parts[0])
    for nxt in parts[1:]:
        best: Optional[float] = None
        bi = bj = 0
        for i, p in enumerate(acc):
            for j, q in enumerate(nxt):
                dist = (p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2
                if best is None or dist < best:
                    best = dist
                    bi, bj = i, j
        rotated = nxt[bj:] + nxt[:bj]
        acc = acc[: bi + 1] + rotated + [rotated[0], acc[bi]] + acc[bi + 1 :]
    return [(round(p[0], 6), round(p[1], 6)) for p in _open_ring(acc)]


def _clip_plane(
    poly: Sequence[Point],
    inside: Callable[[Point], bool],
    inter: Callable[[Point, Point], Point],
) -> List[Point]:
    if not poly:
        return []
    out: List[Point] = []
    prev = poly[-1]
    prev_in = inside(prev)
    for cur in poly:
        cur_in = inside(cur)
        if cur_in:
            if not prev_in:
                out.append(inter(prev, cur))
            out.append(cur)
        elif prev_in:
            out.append(inter(prev, cur))
        prev, prev_in = cur, cur_in
    return _dedupe(out)


def _inter_x(a: Point, b: Point, x: float) -> Point:
    den = b[0] - a[0]
    t = 0.0 if abs(den) < 1e-15 else (x - a[0]) / den
    return (x, a[1] + t * (b[1] - a[1]))


def _inter_y(a: Point, b: Point, y: float) -> Point:
    den = b[1] - a[1]
    t = 0.0 if abs(den) < 1e-15 else (y - a[1]) / den
    return (a[0] + t * (b[0] - a[0]), y)


def clip_to_rect(poly: Sequence[Point], rect: Sequence[float]) -> List[Point]:
    west, east, south, north = rect
    p = _clip_plane(list(poly), lambda q: q[0] >= west, lambda a, b: _inter_x(a, b, west))
    p = _clip_plane(p, lambda q: q[0] <= east, lambda a, b: _inter_x(a, b, east))
    p = _clip_plane(p, lambda q: q[1] >= south, lambda a, b: _inter_y(a, b, south))
    p = _clip_plane(p, lambda q: q[1] <= north, lambda a, b: _inter_y(a, b, north))
    return p


def outside_rect_parts(poly: Sequence[Point], rect: Sequence[float]) -> List[List[Point]]:
    west, east, south, north = rect
    left = _clip_plane(list(poly), lambda q: q[0] <= west, lambda a, b: _inter_x(a, b, west))
    right = _clip_plane(list(poly), lambda q: q[0] >= east, lambda a, b: _inter_x(a, b, east))
    slab = _clip_plane(list(poly), lambda q: q[0] >= west, lambda a, b: _inter_x(a, b, west))
    slab = _clip_plane(slab, lambda q: q[0] <= east, lambda a, b: _inter_x(a, b, east))
    bottom = _clip_plane(slab, lambda q: q[1] <= south, lambda a, b: _inter_y(a, b, south))
    top = _clip_plane(slab, lambda q: q[1] >= north, lambda a, b: _inter_y(a, b, north))
    parts: List[List[Point]] = []
    for part in (left, right, bottom, top):
        if len(part) >= 3 and abs(_ring_area(part)) > 1e-8:
            parts.append(part)
    return parts


def _round_ring(ring: Sequence[Point]) -> List[List[float]]:
    return [[round(p[0], 6), round(p[1], 6)] for p in ring]


def _canvas_from_ll(ring: Sequence[Point]) -> List[Point]:
    return [_lonlat_to_canvas(lon, lat) for lon, lat in ring]


def load_chi_rings() -> Dict[int, Ring]:
    """Always the pre-split rings. Live geometry is already the 56 boxes."""
    doc = _load(FIXTURE)
    out: Dict[int, Ring] = {}
    for key, ring in (doc.get("rings") or {}).items():
        out[int(key)] = [_canvas_to_lonlat(float(p[0]), float(p[1])) for p in ring]
    missing = [pid for pid in CHI_BLOBS if pid not in out]
    if missing:
        raise SystemExit("GAP-CHINA fixture missing %s" % missing)
    return out


def paint_boxes(chi_rings: Mapping[int, Ring]) -> Dict[str, List[Ring]]:
    remaining = [list(r) for r in chi_rings.values()]
    slots = {name: rect for name, rect, _kept, _city in SLOTS}
    got: Dict[str, List[Ring]] = {name: [] for name in slots}
    for name in PAINT_ORDER:
        rect = slots[name]
        new_rem: List[Ring] = []
        for ring in remaining:
            inside = clip_to_rect(ring, rect)
            if len(inside) >= 3 and abs(_ring_area(inside)) > 1e-6:
                got[name].append(inside)
            new_rem.extend(outside_rect_parts(ring, rect))
        remaining = new_rem
    for ring in remaining:
        if len(ring) >= 3 and abs(_ring_area(ring)) > 1e-6:
            got["Chahar"].append(ring)
    return got


def _slot_centroid(name: str, parts: Sequence[Ring]) -> Point:
    if parts:
        sized = max(parts, key=lambda r: abs(_ring_area(r)))
        return _area_centroid(sized)
    rect = next(r for n, r, _k, _c in SLOTS if n == name)
    west, east, south, north = rect
    return ((west + east) / 2.0, (south + north) / 2.0)


def leftover_pool() -> List[int]:
    if use_all_leftovers():
        return list(LEFTOVER_IDS)
    return list(LEFTOVER_IDS[:-1])


def assign_ids(chi_rings: Mapping[int, Ring], painted: Mapping[str, Sequence[Ring]]) -> Dict[str, int]:
    """kept IDs stay. Leftover IDs fill NEW names. Rest take 905855-905888."""
    name_to_pid: Dict[str, int] = {}
    new_names = [n for n, _r, kept, _c in SLOTS if kept == 0]
    for name, _rect, kept, _city in SLOTS:
        if kept:
            name_to_pid[name] = int(kept)
    pool = leftover_pool()
    used_names = set()
    used_pids = set()

    def overlap(pid: int, name: str) -> float:
        src = chi_rings[pid]
        rect = next(r for n, r, _k, _c in SLOTS if n == name)
        inter = clip_to_rect(src, rect)
        return abs(_ring_area(inter)) if len(inter) >= 3 else 0.0

    ranks = []
    for pid in pool:
        lc = _area_centroid(chi_rings[pid])
        for idx, name in enumerate(new_names):
            ov = overlap(pid, name)
            if ov > 1e-8:
                ranks.append((0, -ov, pid, idx, name))
                continue
            if pid == 902487 and name == "Hebei North (Peiping-Tientsin)":
                ranks.append((1, 0.0, pid, idx, name))
                continue
            sc = _slot_centroid(name, painted.get(name) or [])
            dist = (lc[0] - sc[0]) ** 2 + (lc[1] - sc[1]) ** 2
            ranks.append((2, dist, pid, idx, name))
    ranks.sort()
    for _kind, _score, pid, _idx, name in ranks:
        if pid in used_pids or name in used_names:
            continue
        name_to_pid[name] = pid
        used_pids.add(pid)
        used_names.add(name)
        if len(used_pids) == len(pool):
            break
    nxt = NEW_ID_START
    for name in new_names:
        if name in name_to_pid:
            continue
        if nxt > NEW_ID_END:
            continue
        name_to_pid[name] = nxt
        nxt += 1
    return name_to_pid


_LAND_MASK = None


def _snap_land_anchor(ax: float, ay: float) -> Point:
    global _LAND_MASK
    if _LAND_MASK is None:
        lib = str(ROOT / "tools" / "map_generation" / "lib")
        if lib not in sys.path:
            sys.path.insert(0, lib)
        from ne_full_geometry_align import load_ne_land_features, rasterize_land_mask

        _LAND_MASK = rasterize_land_mask(
            load_ne_land_features(NE_LAND), width=2048, height=1024
        )
    from ne_full_geometry_align import nearest_mask_pixel, sample_mask

    if sample_mask(_LAND_MASK, ax, ay):
        return (round(ax, 6), round(ay, 6))
    nx, ny = nearest_mask_pixel(_LAND_MASK, ax, ay, want_land=True, max_radius=2)
    if (nx - ax) ** 2 + (ny - ay) ** 2 > 16.0:
        return (round(ax, 6), round(ay, 6))
    return (round(nx, 6), round(ny, 6))


def build_geometry(painted: Mapping[str, Sequence[Ring]], ids: Mapping[str, int]) -> Dict[int, dict]:
    out: Dict[int, dict] = {}
    for name, _rect, _kept, _city in SLOTS:
        pid = ids.get(name)
        if pid is None:
            continue
        parts = list(painted.get(name) or [])
        if not parts:
            raise SystemExit("GAP-CHINA empty geometry for %s" % name)
        parts.sort(key=lambda r: -abs(_ring_area(r)))
        parts = parts[:12]
        canvas_parts = [_canvas_from_ll(p) for p in parts]
        bridged = bridge_rings(canvas_parts)
        sized = max(parts, key=lambda r: abs(_ring_area(r)))
        ax, ay = _area_centroid(_canvas_from_ll(sized))
        sx, sy = _snap_land_anchor(ax, ay)
        terrain = "mountains" if "tibet" in name.lower() else "plains"
        out[pid] = {
            "id": pid,
            "name": name,
            "points": _round_ring(bridged),
            "label_anchor": [sx, sy],
            "meta": {
                "source": "ne_10m_land",
                "gap_china": name,
                "adm0_a3": "CHN",
                "terrain_hint": terrain,
            },
        }
    return out


def _bbox_ll(parts: Sequence[Ring]) -> Tuple[float, float, float, float]:
    xs = [p[0] for ring in parts for p in ring]
    ys = [p[1] for ring in parts for p in ring]
    return (min(xs), max(xs), min(ys), max(ys))


def _bbox_gap(a: Tuple[float, float, float, float], b: Tuple[float, float, float, float]) -> float:
    aw, ae, as_, an = a
    bw, be, bs, bn = b
    dx = 0.0 if ae >= bw and be >= aw else min(abs(ae - bw), abs(be - aw))
    dy = 0.0 if an >= bs and bn >= as_ else min(abs(an - bs), abs(bn - as_))
    return dx * dx + dy * dy


def _mirror_pairs(adj: Dict[str, List[int]]) -> None:
    pending: List[Tuple[str, int]] = []
    for src, nbs in adj.items():
        for dst in nbs:
            key = str(int(dst))
            if key not in adj:
                continue
            if int(src) not in adj[key]:
                pending.append((key, int(src)))
    for key, dst in pending:
        adj[key].append(dst)
    for key in adj:
        adj[key] = sorted(set(int(x) for x in adj[key]))


def _link(adj: Dict[str, List[int]], a: int, b: int) -> None:
    if a == b:
        return
    nbs = adj.setdefault(str(int(a)), [])
    dst = int(b)
    if dst not in [int(x) for x in nbs]:
        nbs.append(dst)


def _unlink(adj: Dict[str, List[int]], a: int, b: int) -> None:
    for src, dst in ((a, b), (b, a)):
        key = str(src)
        if key in adj:
            adj[key] = [x for x in adj[key] if int(x) != dst]


def build_adjacency(
    adj: Dict[str, List[int]],
    ids: Mapping[str, int],
    painted: Mapping[str, Sequence[Ring]],
    geo_by: Mapping[int, dict],
) -> None:
    china_pids = [ids[n] for n, _r, _k, _c in SLOTS if n in ids]
    for pid in china_pids:
        adj.setdefault(str(pid), [])
    ext: Dict[int, List[int]] = {}
    for a in CHI_BLOBS:
        for b in list(adj.get(str(a), [])):
            bi = int(b)
            if bi not in CHI_BLOBS and bi not in china_pids:
                ext.setdefault(bi, []).append(a)
    for a in CHI_BLOBS:
        for b in list(adj.get(str(a), [])):
            _unlink(adj, a, int(b))
    # Slot rects, not painted remainder bboxes. Chahar's leftover Manchuria
    # land would otherwise neighbour half the board.
    boxes = {ids[n]: rect for n, rect, _k, _c in SLOTS if n in ids}
    for i, a in enumerate(china_pids):
        ba = boxes.get(a)
        if not ba:
            continue
        for b in china_pids[i + 1 :]:
            bb = boxes.get(b)
            if not bb:
                continue
            if _bbox_gap(ba, bb) <= 0.04:
                _link(adj, a, b)
    for ext_pid in ext:
        g = geo_by.get(ext_pid) or {}
        pts = g.get("points") or []
        if len(pts) < 3:
            continue
        ll = [_canvas_to_lonlat(float(p[0]), float(p[1])) for p in pts]
        eb = (
            min(p[0] for p in ll),
            max(p[0] for p in ll),
            min(p[1] for p in ll),
            max(p[1] for p in ll),
        )
        best: Optional[Tuple[float, int]] = None
        for pid in china_pids:
            bb = boxes.get(pid)
            if not bb:
                continue
            gap = _bbox_gap(eb, bb)
            if best is None or gap < best[0]:
                best = (gap, pid)
        if best is not None:
            _link(adj, ext_pid, best[1])
    chahar = ids.get("Chahar")
    leftover_ext = set()
    for ext_pid, olds in ext.items():
        if any(o in LEFTOVER_IDS for o in olds):
            leftover_ext.add(ext_pid)
    if chahar:
        for ext_pid in leftover_ext:
            _link(adj, chahar, ext_pid)
    fujian = ids.get("Fujian South (Amoy)")
    canton = ids.get("Guangdong Central (Canton)")
    if fujian:
        _link(adj, KINMEN, fujian)
    if canton:
        _link(adj, YUEN_LONG, canton)
        _link(adj, HONG_KONG, canton)
    if any(emit_existing_id(int(k)) != int(k) for k in list(adj)):
        remapped: Dict[str, List[int]] = {}
        for key, nbs in adj.items():
            nk = str(emit_existing_id(int(key)))
            remapped.setdefault(nk, [])
            remapped[nk].extend(emit_existing_id(int(b)) for b in nbs)
        adj.clear()
        adj.update({k: sorted(set(remapped[k])) for k in remapped})
    _mirror_pairs(adj)  # GAP_CHINA_MIRROR_CALL


def _pretty_base(obj: Mapping[str, Any]) -> str:
    text = json.dumps(obj, indent=2, ensure_ascii=False)
    return "\n".join("    " + line for line in text.splitlines())


def _span(text: str, needle: str) -> Tuple[int, int]:
    idx = text.find(needle)
    if idx < 0:
        raise SystemExit("missing %s" % needle)
    brace = text.rfind("{", 0, idx)
    _obj, end = json.JSONDecoder().raw_decode(text, brace)
    line = text.rfind("\n", 0, brace) + 1
    if text[line:brace].strip() == "":
        return line, end
    return brace, end


def _replace_span(text: str, needle: str, new_text: str) -> str:
    start, end = _span(text, needle)
    return text[:start] + new_text + text[end:]


def _base_row(pid: int, name: str, terrain: str, old: Optional[dict] = None) -> dict:
    row = dict(old or {})
    row.update(
        {
            "id": pid,
            "name": name,
            "terrain": terrain,
            "domain": "land",
            "core_for_tags": row.get("core_for_tags") or [],
            "natural_resources": row.get("natural_resources") or {},
            "population_base": int(row.get("population_base") or 0),
        }
    )
    meta = dict(row.get("meta") or {})
    meta["gap_china"] = name
    meta["adm0_a3"] = meta.get("adm0_a3") or "CHN"
    meta["source"] = meta.get("source") or "ne_10m_land"
    row["meta"] = meta
    return row


def _upsert_base(text: str, rows: Sequence[Mapping[str, Any]]) -> str:
    for row in rows:
        pid = int(row["id"])
        needle = '"id": %d' % pid
        pretty = _pretty_base(row)
        if needle in text:
            text = _replace_span(text, needle, pretty)
            continue
        close = text.rfind("\n  ]\n}")
        if close < 0:
            raise SystemExit("provinces_base.json has no array close")
        text = text[:close] + ",\n" + pretty + text[close:]
    return text


def _compact_geo(row: Mapping[str, Any]) -> str:
    return json.dumps(row, separators=(",", ":"), ensure_ascii=False)


def _upsert_geometry(text: str, rows: Sequence[Mapping[str, Any]]) -> str:
    decoder = json.JSONDecoder()
    array_at = text.find("[")
    _array, array_end = decoder.raw_decode(text, array_at)
    for row in rows:
        pid = int(row["id"])
        needle = '"id":%d' % pid
        blob = _compact_geo(row)
        if needle in text:
            text = _replace_span(text, needle, blob)
            array_at = text.find("[")
            _array, array_end = decoder.raw_decode(text, array_at)
            continue
        text = text[: array_end - 1] + "," + blob + text[array_end - 1 :]
        array_at = text.find("[")
        _array, array_end = decoder.raw_decode(text, array_at)
    return text


def _city_block(pid: int, name: str) -> str:
    return '    "%d": {\n      "city_name": "%s",\n      "tier": 2\n    }' % (pid, name)


def _upsert_cities(text: str, rows: Sequence[Tuple[int, str]]) -> str:
    decoder = json.JSONDecoder()
    for pid, name in rows:
        key = '"%d":' % pid
        block = _city_block(pid, name)
        idx = text.find(key)
        if idx >= 0:
            brace = text.find("{", idx)
            _obj, end = decoder.raw_decode(text, brace)
            line = text.rfind("\n", 0, idx) + 1
            text = text[:line] + block + text[end:]
            continue
        marker = '\n  },\n  "meta"'
        at = text.rfind(marker)
        if at < 0 or text[at - 1] != "}":
            raise SystemExit("province_city_layer.json tail is not the expected close")
        text = text[:at] + ",\n" + block + text[at:]
    return text


def _terrain_of(name: str) -> str:
    return "mountains" if "tibet" in name.lower() else "plains"


def apply_layers(
    chi_rings: Mapping[int, Ring],
    painted: Mapping[str, Sequence[Ring]],
    ids: Mapping[str, int],
) -> None:
    pid_name = {pid: name for name, pid in ids.items()}
    china_pids = sorted(ids.values())
    areas = {ids[n]: sum(abs(_ring_area(r)) for r in painted.get(n) or []) for n in ids}
    total_area = sum(areas.values()) or 1.0

    eco_old = _load(D / "province_economy_layer.json")
    res_old = _load(D / "province_resources_layer.json")
    parent_pop = PARENT_POP
    parent_fac = PARENT_FAC
    parent_coal = PARENT_COAL
    parent_tung = PARENT_TUNG

    def shares(total: int) -> Dict[int, int]:
        raw = {pid: total * areas.get(pid, 0.0) / total_area for pid in china_pids}
        out = {pid: int(v) for pid, v in raw.items()}
        rem = total - sum(out.values())
        order = sorted(china_pids, key=lambda p: -(raw[p] - out[p]))
        for pid in order:
            if rem <= 0:
                break
            out[pid] += 1
            rem -= 1
        return out

    pop_s = shares(parent_pop)
    fac_s = shares(parent_fac)
    coal_s = shares(parent_coal)
    tung_s = shares(parent_tung)

    for year in ERA_YEARS:
        own_path = D / ("province_ownership_%d.json" % year)
        own = _load(own_path)
        owners = own.setdefault("owners", {})
        for pid in china_pids:
            owners[str(pid)] = "CHI"
        own_path.write_text(_dumps(own), encoding="utf-8")

        mem_path = D / ("hierarchy_membership_%d.json" % year)
        mem = _load(mem_path)
        reg = mem.setdefault("province_to_region", {})
        st = mem.setdefault("province_to_state", {})
        sup = mem.setdefault("province_to_super_region", {})
        for pid in china_pids:
            reg[str(pid)] = REGION_EAST_ASIA
            st[str(pid)] = STATE_CHN
            sup[str(pid)] = SUPER_EAST_ASIA
        mem_path.write_text(_dumps(mem), encoding="utf-8")

    terr = _load(D / "province_terrain_layer.json")
    trows = terr.setdefault("provinces", {})
    for pid in china_pids:
        trows[str(pid)] = {"terrain": _terrain_of(pid_name[pid]), "domain": "land"}
    (D / "province_terrain_layer.json").write_text(_dumps(terr), encoding="utf-8")

    eco = _load(D / "province_economy_layer.json")
    erows = eco.setdefault("provinces", {})
    for pid in china_pids:
        erows[str(pid)] = {
            "population": int(pop_s.get(pid, 0)),
            "factories": int(fac_s.get(pid, 0)),
            "infrastructure": 3,
            "development_level": 2,
        }
    (D / "province_economy_layer.json").write_text(_dumps(eco), encoding="utf-8")

    res = _load(D / "province_resources_layer.json")
    rrows = res.setdefault("provinces", {})
    for pid in china_pids:
        row = {}
        if coal_s.get(pid, 0):
            row["coal"] = int(coal_s[pid])
        if tung_s.get(pid, 0):
            row["tungsten"] = int(tung_s[pid])
        rrows[str(pid)] = row
    (D / "province_resources_layer.json").write_text(_dumps(res), encoding="utf-8")

    regions = _load(D / "strategic_regions.json")
    for region in regions.get("regions") or []:
        if region.get("id") == REGION_EAST_ASIA:
            rids = region.setdefault("province_ids", [])
            for pid in china_pids:
                if pid not in rids:
                    rids.append(pid)
    (D / "strategic_regions.json").write_text(_dumps(regions), encoding="utf-8")

    scaffold = _load(D / "hierarchy_scaffold.json")
    for pid in china_pids:
        scaffold.setdefault("province_to_region", {})[str(pid)] = REGION_EAST_ASIA
        scaffold.setdefault("province_to_state", {})[str(pid)] = STATE_CHN
        scaffold.setdefault("province_to_super_region", {})[str(pid)] = SUPER_EAST_ASIA
    scaffold["province_n"] = len(scaffold["province_to_region"])
    scaffold["land_n"] = sum(1 for v in scaffold["province_to_state"].values() if int(v or 0) > 0)
    (D / "hierarchy_scaffold.json").write_text(_dumps(scaffold), encoding="utf-8")

    base_text = (D / "provinces_base.json").read_text(encoding="utf-8")
    base_doc = json.loads(base_text)
    by_base = {int(p["id"]): p for p in base_doc["provinces"]}
    rows = []
    for name, pid in ids.items():
        rows.append(_base_row(pid, name, _terrain_of(name), by_base.get(pid)))
    for pid, orig in ORIG_LEFTOVER_NAMES.items():
        if pid not in china_pids and pid in by_base:
            rows.append(_base_row(pid, orig, "plains", by_base.get(pid)))
    (D / "provinces_base.json").write_text(_upsert_base(base_text, rows), encoding="utf-8")

    geo_text = (D / "provinces_geometry.json").read_text(encoding="utf-8")
    geo_doc = json.loads(geo_text)
    by_geo = {int(g["id"]): g for g in geo_doc["provinces"]}
    built = build_geometry(painted, ids)
    geo_rows = []
    for pid, row in built.items():
        old = by_geo.get(pid) or {}
        meta = dict(old.get("meta") or {})
        meta.update(row["meta"])
        geo_rows.append(
            {
                "id": pid,
                "name": row["name"],
                "points": row["points"],
                "label_anchor": row["label_anchor"],
                "meta": meta,
            }
        )
    (D / "provinces_geometry.json").write_text(_upsert_geometry(geo_text, geo_rows), encoding="utf-8")

    city_rows = []
    for name, _rect, _kept, city in SLOTS:
        pid = ids.get(name)
        if pid is None or not city:
            continue
        city_rows.append((pid, city))
    city_path = D / "province_city_layer.json"
    city_path.write_text(_upsert_cities(city_path.read_text(encoding="utf-8"), city_rows), encoding="utf-8")

    states_path = D / "province_states.json"
    states_text = states_path.read_text(encoding="utf-8")
    needle = '"id": %d,' % STATE_CHN
    start, end = _span(states_text, needle)
    state = json.loads(states_text[start:end])
    sids = list(state.get("province_ids") or [])
    for pid in china_pids:
        if pid not in sids:
            sids.append(pid)
    state["province_ids"] = sids
    states_path.write_text(states_text[:start] + _pretty_base(state) + states_text[end:], encoding="utf-8")

    adj_path = D / "province_adjacency.json"
    adj_doc = _load(adj_path)
    adj = {k: [int(x) for x in v] for k, v in (adj_doc.get("adjacency") or {}).items()}
    geo_now = {int(g["id"]): g for g in json.loads((D / "provinces_geometry.json").read_text())["provinces"]}
    build_adjacency(adj, ids, painted, geo_now)
    for key in list(adj):
        adj[key] = sorted(set(int(x) for x in adj[key]))
    adj_doc["adjacency"] = {k: adj[k] for k in adj}
    base_now = json.loads((D / "provinces_base.json").read_text(encoding="utf-8"))
    stats = adj_doc.setdefault("stats", {})
    land_n = sum(1 for p in base_now["provinces"] if str(p.get("domain") or "") == "land")
    stats["province_n"] = len(adj)
    stats["land_n"] = land_n
    stats["water_n"] = len(adj) - land_n
    adj_path.write_text(_dumps(adj_doc), encoding="utf-8")


def refresh_adj_v3() -> None:
    script = ROOT / "tools" / "map_generation" / "scripts" / "generate_adj_v3_rhineland.py"
    import importlib.util

    spec = importlib.util.spec_from_file_location("adjv3_from_china", script)
    if spec is None or spec.loader is None:
        raise SystemExit("cannot load ADJ-V3 generator")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    if mod.main([]) != 0:
        raise SystemExit("ADJ-V3 refresh failed")


def main() -> int:
    if not FIXTURE.is_file():
        raise SystemExit("missing CHI parent fixture: %s" % FIXTURE)
    chi_rings = load_chi_rings()
    painted = paint_boxes(chi_rings)
    ids = assign_ids(chi_rings, painted)
    missing = [n for n, _r, _k, _c in SLOTS if n not in ids]
    if missing:
        raise SystemExit("GAP-CHINA missing ids for %s" % missing)
    apply_layers(chi_rings, painted, ids)
    refresh_adj_v3()
    print(
        "GAP-CHINA n_named=%d ids=%s leftover=%s"
        % (
            len(ids),
            sorted(ids.values())[:8],
            {pid: name for name, pid in ids.items() if pid in LEFTOVER_IDS},
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
