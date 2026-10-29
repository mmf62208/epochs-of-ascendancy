"""GAP-JAP-1: JAP 1936 land rings must not stay 36/72-vertex placeholders.

The board at af2c5b06 has 114 JAP-owned land placeholders (id < 950000,
domain land). They are Japan prefectures (JPN ADM1), Korea (KOR and PRK
ADM2), Formosa (TWN ADM2), and Pohnpei (FSM). Karafuto and Kwantung are not
JAP-owned land provinces on this board. Two Korea rings (Ganghwa-gun area
903942 and Ulleung-gun 903946) are already real outlines and stay as they are.

113 placeholders match a gbOpen admin name. 金湖鎮 903981 stays a circle:
its 2 px lie inside CHI 902633. The ring is that polygon,
clipped the way GAP-ENG-1 clips: neighbours yield, frozen rings are
subtracted, and a ring this pass writes is strictly simple. Overlap is the
polygon intersection area, and also the pixel count. FRA ids 905203, 904598,
903903, 905610, and 905620 are not edited. CHI, ENG, and FRA rings are not
rewritten.
"""
from __future__ import annotations

import re
import unicodedata
from typing import Dict, List, Sequence, Tuple

from gap_china2_outline import _clean, _nz_pair_area, _self_kinds  # noqa: E402
from gap_ussr_west2_product import (  # noqa: E402
    _bboxes_overlap,
    _cluster_windows,
    _is_water,
    integer_bounds,
    is_placeholder_ring,
    open_ring,
    overlap_px,
    rasterize_centers,
    self_crosses,
)

META_RING = "gap_jap1"
META_YIELD = "gap_jap1_yield"
OVERLAP_PX_MAX = 1
POLY_OVERLAP_MAX = 1.0
HOLE_PX_MAX = 250
OWNER = "JAP"

# 金湖鎮 (Kinmen) is a real gbOpen township, but both of its pixel centers lie
# inside CHI 902633. A single exterior ring cannot open a hole in that
# province, and notching CHI is out of scope. The circle stays.
UNKNOWN_PLACEHOLDER_IDS = (903981,)
UNKNOWN_REASONS = {
    903981: "gbOpen 金湖鎮 is 2 px and those centers lie inside CHI 902633 CHN South; a single ring cannot open a hole there",
}

# Every JAP 1936 land placeholder on af2c5b06. 903942 and 903946 are already real.
SCOPE_PLACEHOLDER_IDS = (
    902474, 903918, 903919, 903920,
    903921, 903922, 903923, 903924,
    903925, 903926, 903927, 903928,
    903929, 903930, 903931, 903932,
    903933, 903934, 903935, 903936,
    903937, 903938, 903939, 903940,
    903941, 903943, 903944, 903945,
    903947, 903948, 903949, 903950,
    903951, 903952, 903953, 903954,
    903955, 903956, 903957, 903958,
    903959, 903960, 903961, 903962,
    903963, 903964, 903965, 903966,
    903967, 903968, 903969, 903970,
    903971, 903972, 903973, 903974,
    903975, 903976, 903977, 903978,
    903979, 903980, 903981, 903982,
    903983, 903984, 903985, 903986,
    903987, 903988, 903989, 903990,
    903991, 903992, 903993, 903994,
    903995, 903996, 903997, 903998,
    903999, 904000, 904001, 904002,
    904003, 904004, 904005, 904006,
    904007, 904008, 904009, 904010,
    904011, 904012, 904013, 904014,
    904015, 904016, 904017, 904018,
    904019, 904020, 904021, 904022,
    904023, 904024, 904025, 904026,
    904027, 904028, 904029, 904030,
    904031, 904032,
)

# Rings this branch must not rewrite. The two JAP placeholders that are
# already raw-invalid (903952, 904012) are omitted so this pass can replace
# them. FRA ids stay even when the current ring is simple.
DO_NOT_EDIT_IDS = (
    711040, 902487, 902491, 902493, 902496, 902504,
    902505, 902514, 902521, 902534, 902544, 902564, 902566, 902569,
    902590, 902601, 902633, 902790, 902798, 902820, 902822, 902826,
    902831, 902839, 902846, 902849, 902865, 902873, 902875, 903045,
    903047, 903048, 903049, 903052, 903318, 903330, 903353, 903838,
    903903, 904598, 904638, 904657, 904668,
    904710, 905066, 905203, 905610, 905620, 905644, 905792, 905795,
    905796, 905814, 905815, 905838, 905843, 906001, 906004, 906006,
    906014, 906016, 906018, 906102, 950006, 950075, 950077, 950078,
    950096, 950179,
)

# No enclosed hole over 250 px² sits in the JAP placeholder windows on af2c5b06.
PRIOR_ENCLOSED_HOLES = ()

EXPECTED_RERINGS = len(SCOPE_PLACEHOLDER_IDS) - len(UNKNOWN_PLACEHOLDER_IDS)


_ADMIN_WORDS = {
    "prefecture", "metropolis", "subprefecture", "province", "district",
    "township", "county", "city", "area", "gun", "si", "do", "fu", "ken",
    "special", "ward", "municipality", "autonomous", "town", "village",
}


def norm_name(name: str) -> str:
    """Fold an admin name the way the RoW densify wrote province names."""
    text = unicodedata.normalize("NFKD", str(name or ""))
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = text.lower().replace("’", "'").replace("`", "'").replace("'", "")
    text = re.sub(r"(\s+area)+$", "", text)
    text = text.replace("*", "")
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return " ".join(text.split())


def core_name(name: str) -> str:
    """Drop a trailing admin word so 'Osaka Prefecture' matches 'Osaka'."""
    parts = norm_name(name).split()
    while len(parts) > 1 and parts[-1] in _ADMIN_WORDS:
        parts.pop()
    while len(parts) > 1 and parts[0] in _ADMIN_WORDS:
        parts.pop(0)
    return " ".join(parts)


def _cjk_core(name: str) -> str:
    text = unicodedata.normalize("NFKC", str(name or ""))
    text = re.sub(r"\s*area\s*$", "", text, flags=re.I).strip()
    return re.sub(r"[鎮乡镇鄉區区市縣县]$", "", text).strip()


def _has_cjk(text: str) -> bool:
    return any("\u4e00" <= ch <= "\u9fff" for ch in text)


def names_match(prov: str, admin: str) -> bool:
    """True when the board name and the admin name are the same unit."""
    p = norm_name(prov)
    a = norm_name(admin)
    if p and a:
        if p == a:
            return True
        if len(p) >= 12 and a.startswith(p):
            return True
        if len(a) >= 12 and p.startswith(a):
            return True
    pc = core_name(prov)
    ac = core_name(admin)
    if pc and ac and pc == ac:
        return True
    cp = _cjk_core(prov)
    ca = _cjk_core(admin)
    if _has_cjk(cp) and _has_cjk(ca) and (cp == ca or cp in ca or ca in cp):
        return True
    return False


def _vertices_on_grid(points) -> bool:
    for x, y in open_ring(points):
        if abs(x - round(x)) > 1e-4 or abs(y - round(y)) > 1e-4:
            return False
    return True


def _orthogonal_invalid(pts) -> bool:
    """Self-touch or self-cross of an integer axis-aligned ring.

    Splitting each edge into unit segments makes a pinch a vertex of degree
    other than 2, and a retrace a repeated unit edge. That is the same set
    of defects as _self_kinds for this class of ring, in linear time.
    """
    degree: Dict[Tuple[int, int], int] = {}
    used = set()

    def bump(v):
        degree[v] = degree.get(v, 0) + 1

    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        ix1, iy1, ix2, iy2 = int(x1), int(y1), int(x2), int(y2)
        if ix1 == ix2 and iy1 == iy2:
            return True
        if ix1 != ix2 and iy1 != iy2:
            raise ValueError("diagonal")
        if iy1 == iy2:
            step = 1 if ix2 > ix1 else -1
            for x in range(ix1, ix2, step):
                a = (x, iy1)
                b = (x + step, iy1)
                key = a if step > 0 else b
                key = (key, (key[0] + 1, key[1]))
                if key in used:
                    return True
                used.add(key)
                bump(a)
                bump(b)
        else:
            step = 1 if iy2 > iy1 else -1
            for y in range(iy1, iy2, step):
                a = (ix1, y)
                b = (ix1, y + step)
                key = a if step > 0 else b
                key = (key, (key[0], key[1] + 1))
                if key in used:
                    return True
                used.add(key)
                bump(a)
                bump(b)
    return any(d != 2 for d in degree.values())


def _is_integer_orthogonal(pts) -> bool:
    for x, y in pts:
        if abs(x - round(x)) > 1e-6 or abs(y - round(y)) > 1e-6:
            return False
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        if abs(x1 - x2) > 1e-6 and abs(y1 - y2) > 1e-6:
            return False
    return True


def ring_is_raw_invalid(points) -> bool:
    """Self-intersection or self-touch. Adjacent endpoints do not count."""
    pts = open_ring(points)
    if len(pts) < 4:
        return False
    if _is_integer_orthogonal(pts):
        return _orthogonal_invalid([(int(round(x)), int(round(y))) for x, y in pts])
    if _self_kinds(_clean(pts)):
        return True
    return self_crosses(pts)


def _hole_components(occupied, origin_x: int, origin_y: int):
    """Enclosed empty components as (px, probe_x, probe_y, local_cells)."""
    import numpy as np
    from collections import deque

    height, width = occupied.shape
    if height < 3 or width < 3:
        return []
    empty = occupied == 0
    if not bool(empty.any()):
        return []
    seen = np.zeros((height, width), np.bool_)
    stack = deque()

    def seed(y, x):
        if empty[y, x] and not seen[y, x]:
            seen[y, x] = True
            stack.append((y, x))

    for c in range(width):
        seed(0, c)
        seed(height - 1, c)
    for r in range(height):
        seed(r, 0)
        seed(r, width - 1)
    while stack:
        y, x = stack.pop()
        if y > 0 and empty[y - 1, x] and not seen[y - 1, x]:
            seen[y - 1, x] = True
            stack.append((y - 1, x))
        if y + 1 < height and empty[y + 1, x] and not seen[y + 1, x]:
            seen[y + 1, x] = True
            stack.append((y + 1, x))
        if x > 0 and empty[y, x - 1] and not seen[y, x - 1]:
            seen[y, x - 1] = True
            stack.append((y, x - 1))
        if x + 1 < width and empty[y, x + 1] and not seen[y, x + 1]:
            seen[y, x + 1] = True
            stack.append((y, x + 1))
    holes = empty & ~seen
    if not bool(holes.any()):
        return []
    comp_seen = np.zeros((height, width), np.bool_)
    out = []
    ys, xs = np.nonzero(holes)
    for y0, x0 in zip(ys.tolist(), xs.tolist()):
        if comp_seen[y0, x0]:
            continue
        q = [(y0, x0)]
        comp_seen[y0, x0] = True
        cells = [(y0, x0)]
        while q:
            y, x = q.pop()
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if ny < 0 or nx < 0 or ny >= height or nx >= width:
                    continue
                if holes[ny, nx] and not comp_seen[ny, nx]:
                    comp_seen[ny, nx] = True
                    q.append((ny, nx))
                    cells.append((ny, nx))
        py, px = cells[0]
        out.append((len(cells), origin_x + px + 0.5, origin_y + py + 0.5, cells))
    return out


def _prior_allows(size: int, cells, origin) -> bool:
    ox, oy = origin
    have = set(cells)
    for prior in PRIOR_ENCLOSED_HOLES:
        if size > int(prior["max_px"]):
            continue
        qx, qy = prior["probe"]
        c = int(round(qx - 0.5)) - ox
        r = int(round(qy - 0.5)) - oy
        if (r, c) in have:
            return True
    return False


def jap_land_ids(owners: Dict[str, str], domains: Dict[int, str]) -> List[int]:
    out = []
    for key, tag in owners.items():
        if tag != OWNER:
            continue
        pid = int(key)
        if _is_water(pid, str(domains.get(pid) or "")):
            continue
        out.append(pid)
    return sorted(out)


def scope_placeholder_ids(owners: Dict[str, str], geometry: Sequence[dict], domains: Dict[int, str]) -> List[int]:
    """JAP 1936 land rings that are still 36/72-vertex placeholders."""
    by_id = {int(g["id"]): g for g in geometry}
    bad = []
    for pid in jap_land_ids(owners, domains):
        g = by_id.get(pid)
        if g is None or is_placeholder_ring(g.get("points") or []):
            bad.append(pid)
    return sorted(bad)


def audit_changed(
    geometry: Sequence[dict],
    domains: Dict[int, str],
    adjacency: Dict[str, List[int]],
    pids: Sequence[int],
) -> List[str]:
    """Strict simplicity, pixel overlap, polygon-area overlap, holes, neighbours."""
    import numpy as np

    problems: List[str] = []
    by_id = {int(g["id"]): g for g in geometry}
    want = [int(pid) for pid in pids]
    land_pts = {}
    water_pts = {}
    boxes = {}
    for pid, g in by_id.items():
        pts = open_ring(g.get("points") or [])
        if len(pts) < 3:
            continue
        if _is_water(pid, str(domains.get(pid) or "")):
            water_pts[pid] = pts
            continue
        land_pts[pid] = pts
        boxes[pid] = integer_bounds(pts, 0)
    for pid in want:
        pts = land_pts.get(pid)
        if pts is None:
            problems.append("missing-land %s" % pid)
            continue
        if ring_is_raw_invalid(pts):
            problems.append("raw-invalid %s" % pid)
        if len(adjacency.get(str(pid)) or []) < 1:
            problems.append("zero-neighbour %s" % pid)
        bb = boxes.get(pid)
        if bb is None:
            continue
        for oid, opts in land_pts.items():
            if oid == pid or not _bboxes_overlap(bb, boxes[oid]):
                continue
            ov = overlap_px(pts, opts)
            if ov > OVERLAP_PX_MAX:
                problems.append("overlap %s x %s = %d px" % (pid, oid, ov))
                if len(problems) > 24:
                    return problems
            # Two strictly simple rings on the integer grid meet on pixel
            # edges. Shared centers are the whole intersection, so a pixel
            # overlap of at most 1 is a polygon area of at most 1.
            grid = _vertices_on_grid(pts) and _vertices_on_grid(opts)
            if not grid or ov > OVERLAP_PX_MAX:
                area = _nz_pair_area(_clean(pts), _clean(opts))
                if area > POLY_OVERLAP_MAX:
                    problems.append("poly-overlap %s x %s = %.2f px2" % (pid, oid, area))
                    if len(problems) > 24:
                        return problems
    windows = _cluster_windows([(pid, boxes[pid]) for pid in want if pid in boxes])
    draw = [(pts, boxes[pid]) for pid, pts in land_pts.items()]
    draw.extend((pts, integer_bounds(pts, 0)) for pts in water_pts.values())
    for win in windows:
        w = win[2] - win[0]
        h = win[3] - win[1]
        if w <= 0 or h <= 0 or w * h > 8_000_000:
            problems.append("window too big %s" % (win,))
            continue
        occ = np.zeros((h, w), np.uint8)
        for pts, bb in draw:
            if not _bboxes_overlap(win, bb):
                continue
            occ |= rasterize_centers(pts, win[0], win[1], w, h)
        for size, px, py, cells in _hole_components(occ, win[0], win[1]):
            if size <= HOLE_PX_MAX:
                continue
            if _prior_allows(size, cells, (win[0], win[1])):
                continue
            problems.append("enclosed-hole %d px at (%.1f, %.1f)" % (size, px, py))
            if len(problems) > 24:
                return problems
    return problems


def audit_rerings(geometry: Sequence[dict], domains: Dict[int, str], adjacency: Dict[str, List[int]]) -> List[str]:
    """Problems on gap_jap1 rings and the neighbours they notched."""
    problems: List[str] = []
    by_id = {int(g["id"]): g for g in geometry}
    if len(by_id) != 3596:
        problems.append("province-count %d" % len(by_id))
    flagged = []
    yielded = []
    for pid, g in by_id.items():
        meta = g.get("meta") if isinstance(g.get("meta"), dict) else {}
        if meta.get(META_RING):
            flagged.append(pid)
        elif meta.get(META_YIELD):
            yielded.append(pid)
    if len(flagged) < EXPECTED_RERINGS:
        problems.append("rerings=%d want>=%d" % (len(flagged), EXPECTED_RERINGS))
        return problems
    for pid in flagged:
        g = by_id[pid]
        if is_placeholder_ring(g.get("points") or []):
            problems.append("still-placeholder %s" % pid)
    for pid in yielded:
        g = by_id[pid]
        pts = open_ring(g.get("points") or [])
        if ring_is_raw_invalid(pts):
            problems.append("raw-invalid %s" % pid)
        if len(adjacency.get(str(pid)) or []) < 1:
            problems.append("zero-neighbour %s" % pid)
    # Overlap is checked on the new admin rings. A notched neighbour may keep
    # an overlap it already had with a province this pass did not redraw.
    problems.extend(audit_changed(geometry, domains, adjacency, flagged))
    return problems
