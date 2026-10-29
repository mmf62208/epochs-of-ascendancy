"""GAP-FRA-1: FRA 1936 land rings must not stay 36/72-vertex placeholders.

Ship's count on this base is 142 FRA-owned land placeholders (id < 950000).
geoBoundaries gbOpen has no ADM1/ADM2 for NCL, SPM, PYF, or ATF, so those
five rings stay placeholders and are the UNKNOWN list. Every other ring is
replaced with the admin polygon it was simplified from and clipped to the
board the way GAP-USSR-WEST-2 clips: sea keeps its pixels, neighbours yield,
and no new land overlap or enclosed hole is allowed.

The Levant window already had a 301 px² enclosed gap on 455adc75, between
Abu Kamal and Iraqi Al-Rutba. Real Abu Kamal does not cover it. That hole
may remain. It must not grow, and no other enclosed hole may exceed 250 px².
"""
from __future__ import annotations

import re
import unicodedata
from typing import Dict, List, Sequence, Tuple

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

META_RING = "gap_fra1"
META_YIELD = "gap_fra1_yield"
OVERLAP_PX_MAX = 1
HOLE_PX_MAX = 250
OWNER = "FRA"

# gbOpen API 404 for both ADM1 and ADM2. Shapes are not invented.
UNKNOWN_PLACEHOLDER_IDS = (
    902154,  # NCL Nord
    902388,  # SPM Miquelon-Langlade
    902395,  # PYF Windward Islands
    902396,  # PYF Marquesas Islands
    902424,  # ATF Archipel des Kerguelen
)
UNKNOWN_REASONS = {
    902154: "gbOpen has no NCL ADM1 or ADM2 (API 404)",
    902388: "gbOpen has no SPM ADM1 or ADM2 (API 404)",
    902395: "gbOpen has no PYF ADM1 or ADM2 (API 404)",
    902396: "gbOpen has no PYF ADM1 or ADM2 (API 404)",
    902424: "gbOpen has no ATF ADM1 or ADM2 (API 404)",
}
# Pixel center inside the pre-existing Levant gap. Size is the enclosed
# component on 455adc75. A later ring may not enlarge it.
PRIOR_ENCLOSED_HOLES = (
    {"probe": (5028.5, 1441.5), "max_px": 301, "note": "Abu Kamal / Al-Rutba gap"},
)

# Every FRA 1936 land placeholder on 455adc75. A later batch may notch one
# before it is re-ringed, so the vertex count is no longer 36. Those ids are
# still in scope until meta gap_fra1 is set.
SCOPE_PLACEHOLDER_IDS = (
    902112, 902154, 902388, 902395, 902396, 902424, 903899, 903900,
    903901, 903902, 903903, 903904, 903905, 903906, 903907, 903908,
    903909, 903910, 903911, 903912, 903913, 903914, 903915, 903916,
    903917, 904127, 904580, 904581, 904582, 904583, 904584, 904585,
    904586, 904587, 904588, 904589, 904590, 904591, 904592, 904593,
    904594, 904595, 904596, 904597, 904598, 904599, 904600, 904601,
    904602, 904603, 904604, 904605, 904606, 904607, 904608, 904609,
    904610, 904611, 904612, 904613, 904614, 904615, 904616, 904617,
    904618, 904619, 904620, 904621, 904622, 904623, 904624, 904625,
    904626, 904627, 904628, 904629, 904630, 904631, 904632, 904633,
    904946, 904947, 904948, 904949, 904950, 904951, 904952, 904953,
    904954, 904955, 904956, 904957, 904958, 904959, 904960, 904961,
    904962, 904963, 904964, 904965, 904966, 904967, 904968, 904969,
    904970, 904971, 904972, 904973, 905202, 905203, 905204, 905205,
    905206, 905207, 905208, 905209, 905210, 905211, 905212, 905213,
    905214, 905215, 905216, 905217, 905218, 905219, 905220, 905221,
    905222, 905581, 905644, 905710, 905711, 905712, 905713, 905714,
    905715, 905716, 905717, 905718, 905719, 905720,
)

EXPECTED_RERINGS = len(SCOPE_PLACEHOLDER_IDS) - len(UNKNOWN_PLACEHOLDER_IDS)


def norm_name(name: str) -> str:
    """Fold an admin name the way the RoW densify wrote province names."""
    text = unicodedata.normalize("NFKD", str(name or ""))
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = text.lower().replace("’", "'").replace("`", "'").replace("'", "")
    text = re.sub(r"(\s+area)+$", "", text)
    text = re.sub(r"^province\s+de\s+", "", text)
    text = re.sub(r"^province\s+", "", text)
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return " ".join(text.split())


def fra_land_ids(owners: Dict[str, str], domains: Dict[int, str]) -> List[int]:
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
    """FRA 1936 land rings that are still 36/72-vertex placeholders."""
    by_id = {int(g["id"]): g for g in geometry}
    bad = []
    for pid in fra_land_ids(owners, domains):
        g = by_id.get(pid)
        if g is None or is_placeholder_ring(g.get("points") or []):
            bad.append(pid)
    return sorted(bad)


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
    """True when this component is a known pre-existing hole that did not grow."""
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


def audit_changed(
    geometry: Sequence[dict],
    domains: Dict[int, str],
    adjacency: Dict[str, List[int]],
    pids: Sequence[int],
) -> List[str]:
    """Overlap, self-crossing, neighbours, and enclosed holes for these rings."""
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
        if self_crosses(pts):
            problems.append("self-cross %s" % pid)
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
    windows = _cluster_windows([(pid, boxes[pid]) for pid in want if pid in boxes])
    draw = [(pts, boxes[pid]) for pid, pts in land_pts.items()]
    draw.extend((pts, integer_bounds(pts, 0)) for pts in water_pts.values())
    for win in windows:
        w = win[2] - win[0]
        h = win[3] - win[1]
        if w <= 0 or h <= 0 or w * h > 6_000_000:
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
    """Problems on gap_fra1 rings. Empty list is a pass."""
    problems: List[str] = []
    by_id = {int(g["id"]): g for g in geometry}
    if len(by_id) != 3596:
        problems.append("province-count %d" % len(by_id))
    flagged = []
    for pid, g in by_id.items():
        meta = g.get("meta") if isinstance(g.get("meta"), dict) else {}
        if meta.get(META_RING):
            flagged.append(pid)
    if len(flagged) < EXPECTED_RERINGS:
        problems.append("rerings=%d want>=%d" % (len(flagged), EXPECTED_RERINGS))
        return problems
    for pid in flagged:
        g = by_id[pid]
        if is_placeholder_ring(g.get("points") or []):
            problems.append("still-placeholder %s" % pid)
    problems.extend(audit_changed(geometry, domains, adjacency, flagged))
    return problems
