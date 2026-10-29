"""GAP-ENG-1: ENG 1936 land rings must not stay 36/72-vertex placeholders.

Ship's count is about 268. The board at 925c2877 has 259 ENG-owned land
placeholders (id < 950000, domain land, 36 vertices). geoBoundaries gbOpen
has no ADM file for ATA, CYM, HMD, JEY, IMN, SGS, or FLK. Somaliland and
Kashmir have no admin polygon that matches the blob. Potaro-Siparuni
lies inside the Venezuelan claim zone, and cutting it out splits that
province. Those twelve stay placeholders. Every other ring is the admin
polygon it was simplified from, clipped the way GAP-USSR-WEST-2 clips.

A ring this pass writes is strictly simple: no self-intersection and no
self-touch. Overlap is the polygon intersection area, and also the pixel
count. FRA defects (905203, 904598, 903903 and the known overlap pairs) are
not edited.
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

META_RING = "gap_eng1"
META_YIELD = "gap_eng1_yield"
OVERLAP_PX_MAX = 1
POLY_OVERLAP_MAX = 1.0
HOLE_PX_MAX = 250
OWNER = "ENG"

UNKNOWN_PLACEHOLDER_IDS = (
    900316, 900329, 902131, 902133, 902134, 902422, 902423, 902447,
    902448, 902475, 902476, 905394,
)
UNKNOWN_REASONS = {
    900316: "gbOpen SOM has no unit named Somaliland; Woqooyi Galbeed under the centroid is 0.18 of the blob",
    900329: "Potaro-Siparuni lies inside VEN 903817 Zona en Reclamación (1085 px); removing it splits that province into 3951 and 2512 px pieces",
    902131: "centroid is in PAK Ghanche, which is not a Kashmir polygon; Jammu and Kashmir and Azad Kashmir do not contain it",
    902133: "gbOpen has no ATA ADM1 or ADM2 (API 404)",
    902134: "gbOpen has no ATA ADM1 or ADM2 (API 404)",
    902422: "gbOpen has no CYM ADM1 or ADM2 (API 404)",
    902423: "gbOpen has no HMD ADM1 or ADM2 (API 404)",
    902447: "gbOpen has no JEY ADM1 or ADM2 (API 404)",
    902448: "gbOpen has no IMN ADM1 or ADM2 (API 404)",
    902475: "gbOpen has no SGS ADM1 or ADM2 (API 404)",
    902476: "gbOpen has no FLK ADM1 or ADM2 (API 404)",
    905394: "Ayi is covered by Ma'an 905393 (36 of 38 px); no separate ring remains",
}

# Every ENG 1936 land placeholder on 925c2877.
SCOPE_PLACEHOLDER_IDS = (
    900212, 900229, 900230, 900231, 900232, 900233, 900234, 900235,
    900236, 900237, 900238, 900316, 900329, 901432, 901434, 901435,
    902131, 902133, 902134, 902397, 902406, 902422, 902423, 902447,
    902448, 902453, 902467, 902475, 902476, 902477, 902718, 903012,
    903013, 903014, 903015, 903016, 903017, 903018, 903019, 903020,
    903021, 903022, 903023, 903024, 903025, 903026, 903027, 903028,
    903029, 903030, 903031, 903032, 903033, 903034, 903035, 903036,
    903037, 903038, 903039, 903040, 903041, 903042, 903043, 903044,
    903046, 903053, 903054, 903055, 903056, 903057, 903058, 903059,
    903060, 903061, 903062, 903063, 903064, 903065, 903066, 903067,
    903068, 903069, 903070, 903071, 903072, 903073, 903074, 903075,
    903076, 903077, 903078, 903079, 903080, 903081, 903082, 903083,
    903084, 903085, 903086, 903087, 903137, 903867, 903868, 903870,
    903871, 903872, 903873, 903874, 903875, 903876, 903877, 903878,
    903879, 903880, 903881, 903882, 903883, 903884, 903885, 903886,
    903887, 903889, 903890, 903891, 903892, 903893, 903894, 903895,
    903896, 903897, 904041, 904343, 904344, 904345, 904346, 904347,
    904348, 904349, 904350, 904351, 904352, 904353, 904354, 904355,
    904356, 904357, 904358, 904359, 904360, 904361, 904362, 904363,
    904364, 904365, 904366, 904367, 904368, 904369, 904370, 904371,
    904372, 904373, 904374, 904375, 904376, 904377, 904378, 904379,
    904380, 904381, 904382, 904383, 904384, 904385, 904386, 904387,
    904388, 904389, 904390, 904391, 904392, 904393, 904394, 904395,
    904396, 904397, 904398, 904399, 904400, 904401, 904402, 904403,
    904404, 905377, 905378, 905379, 905380, 905381, 905382, 905383,
    905384, 905385, 905386, 905387, 905388, 905389, 905390, 905391,
    905392, 905393, 905394, 905395, 905527, 905528, 905695, 905696,
    905697, 905698, 905699, 905700, 905701, 905702, 905703, 905704,
    905705, 905706, 905707, 905709, 905721, 905722, 905723, 905724,
    905725, 905726, 905727, 905729, 905730, 905731, 905732, 905733,
    905734, 905735, 905736, 905737, 905738, 905739, 905740, 905741,
    905742, 905744, 905746, 905748, 905749, 905750, 905752, 905753,
    905755, 905758, 905790,
)

# Rings this branch must not rewrite. FRA self-touches and the polygon
# overlaps Ship measured, plus every other raw-invalid ring that is not an
# ENG placeholder we are replacing.
DO_NOT_EDIT_IDS = (
    711040, 902105, 902108, 902487, 902491, 902493, 902496, 902504,
    902505, 902514, 902521, 902534, 902544, 902564, 902566, 902569,
    902590, 902601, 902633, 902790, 902798, 902820, 902822, 902826,
    902831, 902839, 902846, 902849, 902865, 902873, 902875, 903045,
    903047, 903048, 903049, 903052, 903318, 903330, 903353, 903838,
    903903, 903952, 904012, 904318, 904598, 904638, 904657, 904668,
    904710, 905047, 905066, 905203, 905610, 905620, 905792, 905795,
    905796, 905814, 905815, 905838, 905843, 906001, 906004, 906006,
    906014, 906016, 906018, 906102, 950006, 950075, 950077, 950078,
    950096, 950179,
)

# Enclosed holes already on 925c2877 inside the ENG placeholder windows.
# A later ring may not enlarge them. The Levant gap is the FRA-1 prior.
PRIOR_ENCLOSED_HOLES = (
    {"probe": (4732.5, 2180.5), "max_px": 664},
    {"probe": (4745.5, 2228.5), "max_px": 483},
    {"probe": (4877.5, 2262.5), "max_px": 2021},
    {"probe": (4700.5, 2265.5), "max_px": 568},
    {"probe": (1052.5, 716.5), "max_px": 2703},
    {"probe": (1592.5, 835.5), "max_px": 4933},
    {"probe": (1627.5, 835.5), "max_px": 638},
    {"probe": (1258.5, 871.5), "max_px": 325},
    {"probe": (2634.5, 896.5), "max_px": 272},
    {"probe": (2649.5, 899.5), "max_px": 936},
    {"probe": (1784.5, 924.5), "max_px": 737},
    {"probe": (1764.5, 955.5), "max_px": 603},
    {"probe": (1784.5, 971.5), "max_px": 1438},
    {"probe": (2096.5, 1004.5), "max_px": 661},
    {"probe": (2078.5, 1014.5), "max_px": 520},
    {"probe": (2557.5, 1031.5), "max_px": 1351},
    {"probe": (2177.5, 1073.5), "max_px": 493},
    {"probe": (2098.5, 1074.5), "max_px": 433},
    {"probe": (5069.5, 1344.5), "max_px": 1204},
    {"probe": (5352.5, 1777.5), "max_px": 906},
    {"probe": (5028.5, 1441.5), "max_px": 301},
)

EXPECTED_RERINGS = len(SCOPE_PLACEHOLDER_IDS) - len(UNKNOWN_PLACEHOLDER_IDS)


def norm_name(name: str) -> str:
    """Fold an admin name the way the RoW densify wrote province names."""
    text = unicodedata.normalize("NFKD", str(name or ""))
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = text.lower().replace("’", "'").replace("`", "'").replace("'", "")
    text = re.sub(r"(\s+area)+$", "", text)
    text = re.sub(r"^wilayat\s+", "", text)
    text = re.sub(r"^province\s+de\s+", "", text)
    text = re.sub(r"^province\s+", "", text)
    text = text.replace("*", "")
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return " ".join(text.split())


def names_match(prov: str, admin: str) -> bool:
    """True when the board name is the admin name, or a cut prefix of it."""
    p = norm_name(prov)
    a = norm_name(admin)
    if not p or not a:
        return False
    if p == a:
        return True
    if len(p) >= 12 and a.startswith(p):
        return True
    if len(a) >= 12 and p.startswith(a):
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


def eng_land_ids(owners: Dict[str, str], domains: Dict[int, str]) -> List[int]:
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
    """ENG 1936 land rings that are still 36/72-vertex placeholders."""
    by_id = {int(g["id"]): g for g in geometry}
    bad = []
    for pid in eng_land_ids(owners, domains):
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
    """Problems on gap_eng1 rings and the neighbours they notched."""
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
