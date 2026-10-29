"""GAP-USSR-WEST-2: SOV 1936 rings must not stay 36/72-vertex placeholders.

The 1936 geoBoundaries densify capped every RoW ring at 36 vertices. Those
rings are the placeholders (RoadTierVisual treats n==36 or 37 the same way).
Baikonur lease 902132 has no admin polygon in the geoBoundaries sets this
board was built from, so it stays a placeholder and is the only exception.

Overlap and holes are measured on pixel centers (canvas integer grid).
Two rings that share an edge on that grid do not overlap. An enclosed hole
is an empty pixel component, inside the re-ringed window, that does not
touch the window border and is not a sea/lake province.
"""
from __future__ import annotations

import math
from collections import defaultdict, deque
from typing import Dict, Iterable, List, Sequence, Tuple

try:
    import numpy as np
except ImportError:  # pragma: no cover
    np = None  # type: ignore[assignment]

# No geoBoundaries unit for the lease. Qyzylorda is a different district.
UNKNOWN_PLACEHOLDER_IDS = (902132,)
META_RING = "gap_ussr_west2"
META_YIELD = "gap_ussr_west2_yield"
OVERLAP_PX_MAX = 1
HOLE_PX_MAX = 250
PLACEHOLDER_VERTS = (36, 72)

Point = Tuple[float, float]
Ring = List[Point]


def _require_numpy():
    if np is None:
        raise ImportError("numpy is required for GAP-USSR-WEST-2 ring audit")
    return np


def open_ring(points: Sequence[Sequence[float]]) -> Ring:
    pts: Ring = []
    for p in points:
        if not isinstance(p, (list, tuple)) or len(p) < 2:
            continue
        x, y = float(p[0]), float(p[1])
        if pts and abs(pts[-1][0] - x) < 1e-9 and abs(pts[-1][1] - y) < 1e-9:
            continue
        pts.append((x, y))
    if len(pts) >= 2 and abs(pts[0][0] - pts[-1][0]) < 1e-9 and abs(pts[0][1] - pts[-1][1]) < 1e-9:
        pts = pts[:-1]
    return pts


def vertex_count(points: Sequence[Sequence[float]]) -> int:
    return len(open_ring(points))


def is_placeholder_ring(points: Sequence[Sequence[float]]) -> bool:
    """36- or 72-vertex ring left by the RoW densify cap (or a circle of that size)."""
    return vertex_count(points) in PLACEHOLDER_VERTS


def ring_area(points: Sequence[Sequence[float]]) -> float:
    pts = open_ring(points)
    n = len(pts)
    if n < 3:
        return 0.0
    area = 0.0
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        area += x1 * y2 - x2 * y1
    return abs(area) * 0.5


def ring_bbox(points: Sequence[Sequence[float]]) -> Tuple[float, float, float, float]:
    pts = open_ring(points)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def point_in_ring(x: float, y: float, points: Sequence[Sequence[float]]) -> bool:
    pts = open_ring(points)
    n = len(pts)
    if n < 3:
        return False
    inside = False
    j = n - 1
    for i in range(n):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y):
            den = (yj - yi) if (yj - yi) != 0.0 else 1e-12
            if x < (xj - xi) * (y - yi) / den + xi:
                inside = not inside
        j = i
    return inside


def integer_bounds(points: Sequence[Sequence[float]], pad: int = 1) -> Tuple[int, int, int, int]:
    minx, miny, maxx, maxy = ring_bbox(points)
    return (
        math.floor(minx) - pad,
        math.floor(miny) - pad,
        math.ceil(maxx) + pad,
        math.ceil(maxy) + pad,
    )


def rasterize_centers(ring: Sequence[Sequence[float]], minx: int, miny: int, width: int, height: int):
    """Pixel (r, c) is set when its center (minx+c+0.5, miny+r+0.5) is inside the ring.

    Edges that lie on the integer grid do not claim a center, so two polygons
    that share such an edge do not overlap and do not leave a gap.
    """
    npy = _require_numpy()
    mask = npy.zeros((height, width), npy.uint8)
    pts = open_ring(ring)
    n = len(pts)
    if n < 3 or width <= 0 or height <= 0:
        return mask
    for r in range(height):
        y = miny + r + 0.5
        xs: List[float] = []
        for i in range(n):
            x1, y1 = pts[i]
            x2, y2 = pts[(i + 1) % n]
            if (y1 > y) != (y2 > y):
                xs.append(x1 + (y - y1) / (y2 - y1) * (x2 - x1))
        xs.sort()
        for i in range(0, len(xs) - 1, 2):
            x_l, x_r = xs[i], xs[i + 1]
            c0 = int(math.floor(x_l - minx - 0.5) + 1)
            c1 = int(math.ceil(x_r - minx - 0.5) - 1)
            # A span that lies fully left of the window has c1 < 0. Python
            # would treat mask[r, 0:c1] as a negative end and fill the row.
            if c1 < 0 or c0 >= width:
                continue
            c0 = max(0, c0)
            c1 = min(width - 1, c1)
            if c1 >= c0:
                mask[r, c0 : c1 + 1] = 1
    return mask


def _drop_collinear(ring: Ring) -> Ring:
    if len(ring) < 4:
        return list(ring)
    out: Ring = []
    n = len(ring)
    for i in range(n):
        ax, ay = ring[(i - 1) % n]
        bx, by = ring[i]
        cx, cy = ring[(i + 1) % n]
        if (bx - ax) * (cy - by) - (by - ay) * (cx - bx) == 0:
            continue
        out.append((bx, by))
    return out if len(out) >= 3 else list(ring)


def trace_mask(mask, minx: int, miny: int) -> Ring:
    """Exterior corner ring of a binary mask. Canvas coords.

    Pixel (r, c) covers [minx+c, minx+c+1] x [miny+r, miny+r+1].
    A corner where two boundary edges meet (a diagonal pinch) keeps the
    turn that leaves the filled pixel on the left in y-down canvas space.
    The largest loop is the exterior. Tiny interior holes stay inside it;
    the caller absorbs them when they are under the hole budget.
    Collinear grid points are dropped so a rectangle stays a rectangle.
    """
    height, width = mask.shape
    nxts: Dict[Tuple[int, int], List[Tuple[int, int]]] = defaultdict(list)

    def add(a, b):
        if b not in nxts[a]:
            nxts[a].append(b)

    for r in range(height):
        row = mask[r]
        for c in range(width):
            if row[c] == 0:
                continue
            up = mask[r - 1, c] if r > 0 else 0
            dn = mask[r + 1, c] if r + 1 < height else 0
            lf = mask[r, c - 1] if c > 0 else 0
            rt = mask[r, c + 1] if c + 1 < width else 0
            if up == 0:
                add((c + 1, r), (c, r))
            if rt == 0:
                add((c + 1, r + 1), (c + 1, r))
            if dn == 0:
                add((c, r + 1), (c + 1, r + 1))
            if lf == 0:
                add((c, r), (c, r + 1))
    if not nxts:
        return []
    unused = {(a, b) for a, bs in nxts.items() for b in bs}

    def leftmost(prev, cur):
        options = [b for b in nxts.get(cur, []) if (cur, b) in unused]
        if not options:
            return None
        if prev is None or len(options) == 1:
            return options[0]
        ix, iy = cur[0] - prev[0], cur[1] - prev[1]

        def score(b):
            ox, oy = b[0] - cur[0], b[1] - cur[1]
            # Negative cross is a left turn when y grows downward.
            cross = ix * oy - iy * ox
            dot = ix * ox + iy * oy
            return (cross, -dot)

        return min(options, key=score)

    best_loop: List[Tuple[int, int]] = []
    best_area = -1.0
    limit = len(unused) + 4
    for a0, b0 in list(unused):
        if (a0, b0) not in unused:
            continue
        unused.discard((a0, b0))
        loop = [a0]
        prev, cur = a0, b0
        closed = False
        for _ in range(limit):
            loop.append(cur)
            if cur == a0:
                closed = True
                break
            nxt = leftmost(prev, cur)
            if nxt is None:
                break
            unused.discard((cur, nxt))
            prev, cur = cur, nxt
        if not closed or len(loop) < 4:
            continue
        if loop[-1] == loop[0]:
            loop = loop[:-1]
        area = 0.0
        m = len(loop)
        for i in range(m):
            x1, y1 = loop[i]
            x2, y2 = loop[(i + 1) % m]
            area += x1 * y2 - x2 * y1
        area = abs(area) * 0.5
        if area > best_area:
            best_area = area
            best_loop = loop
    if not best_loop:
        return []
    return _drop_collinear([(minx + x, miny + y) for x, y in best_loop])


def largest_component(mask):
    """Return (component mask, kept area, dropped area)."""
    npy = _require_numpy()
    height, width = mask.shape
    seen = npy.zeros((height, width), npy.uint8)
    best_cells: List[Tuple[int, int]] = []
    total = int(mask.sum())
    ys, xs = npy.nonzero(mask)
    for y0, x0 in zip(ys.tolist(), xs.tolist()):
        if seen[y0, x0]:
            continue
        stack = [(y0, x0)]
        seen[y0, x0] = 1
        cells = [(y0, x0)]
        while stack:
            y, x = stack.pop()
            if y > 0 and mask[y - 1, x] and not seen[y - 1, x]:
                seen[y - 1, x] = 1
                stack.append((y - 1, x))
                cells.append((y - 1, x))
            if y + 1 < height and mask[y + 1, x] and not seen[y + 1, x]:
                seen[y + 1, x] = 1
                stack.append((y + 1, x))
                cells.append((y + 1, x))
            if x > 0 and mask[y, x - 1] and not seen[y, x - 1]:
                seen[y, x - 1] = 1
                stack.append((y, x - 1))
                cells.append((y, x - 1))
            if x + 1 < width and mask[y, x + 1] and not seen[y, x + 1]:
                seen[y, x + 1] = 1
                stack.append((y, x + 1))
                cells.append((y, x + 1))
        if len(cells) > len(best_cells):
            best_cells = cells
    out = npy.zeros((height, width), npy.uint8)
    for y, x in best_cells:
        out[y, x] = 1
    kept = len(best_cells)
    return out, kept, total - kept


def mask_to_ring(mask, minx: int, miny: int) -> Ring:
    comp, _kept, _dropped = largest_component(mask)
    return trace_mask(comp, minx, miny)


def overlap_px(a: Sequence[Sequence[float]], b: Sequence[Sequence[float]]) -> int:
    """Shared pixel centers. 0 when the rings only share a grid edge."""
    npy = _require_numpy()
    aa = open_ring(a)
    bb = open_ring(b)
    if len(aa) < 3 or len(bb) < 3:
        return 0
    ax0, ay0, ax1, ay1 = ring_bbox(aa)
    bx0, by0, bx1, by1 = ring_bbox(bb)
    ix0 = int(math.floor(max(ax0, bx0)))
    iy0 = int(math.floor(max(ay0, by0)))
    ix1 = int(math.ceil(min(ax1, bx1)))
    iy1 = int(math.ceil(min(ay1, by1)))
    if ix0 >= ix1 or iy0 >= iy1:
        return 0
    # Pad by 1 so centers that sit just inside a vertex bbox are included.
    minx, miny = ix0 - 1, iy0 - 1
    width, height = (ix1 - ix0) + 2, (iy1 - iy0) + 2
    ma = rasterize_centers(aa, minx, miny, width, height)
    mb = rasterize_centers(bb, minx, miny, width, height)
    return int(npy.logical_and(ma, mb).sum())


def self_crosses(points: Sequence[Sequence[float]]) -> bool:
    """Proper segment crossings. Shared endpoints of adjacent edges do not count."""
    pts = open_ring(points)
    n = len(pts)
    if n < 4:
        return False
    cell = 32.0
    buckets: Dict[Tuple[int, int], List[int]] = defaultdict(list)

    def cell_of(x, y):
        return int(math.floor(x / cell)), int(math.floor(y / cell))

    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        cx0, cx1 = sorted((cell_of(x1, y1)[0], cell_of(x2, y2)[0]))
        cy0, cy1 = sorted((cell_of(x1, y1)[1], cell_of(x2, y2)[1]))
        for cx in range(cx0, cx1 + 1):
            for cy in range(cy0, cy1 + 1):
                buckets[(cx, cy)].append(i)

    def orient(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])

    def proper(i, j):
        if i == j or (i + 1) % n == j or (j + 1) % n == i:
            return False
        if abs(i - j) == n - 1:
            return False
        a, b = pts[i], pts[(i + 1) % n]
        c, d = pts[j], pts[(j + 1) % n]
        o1, o2 = orient(a, b, c), orient(a, b, d)
        o3, o4 = orient(c, d, a), orient(c, d, b)
        if o1 == 0 or o2 == 0 or o3 == 0 or o4 == 0:
            return False
        return (o1 > 0) != (o2 > 0) and (o3 > 0) != (o4 > 0)

    checked = set()
    for idxs in buckets.values():
        m = len(idxs)
        if m > 80:
            # Dense coast cell: still check, but cap pairs by unique edges.
            idxs = list(dict.fromkeys(idxs))
            m = len(idxs)
        for a_i in range(m):
            for b_i in range(a_i + 1, m):
                i, j = idxs[a_i], idxs[b_i]
                key = (i, j) if i < j else (j, i)
                if key in checked:
                    continue
                checked.add(key)
                if proper(i, j):
                    return True
    return False


def _is_water(pid: int, domain: str) -> bool:
    if pid >= 950000:
        return True
    return domain in ("sea", "strait", "lake")


def sov_placeholder_ids(owners: Dict[str, str], geometry: Sequence[dict], domains: Dict[int, str]) -> List[int]:
    """SOV-1936 provinces that are still placeholder rings, ignoring UNKNOWN."""
    by_id = {int(g["id"]): g for g in geometry}
    bad = []
    for key, tag in owners.items():
        if tag != "SOV":
            continue
        pid = int(key)
        if pid in UNKNOWN_PLACEHOLDER_IDS:
            continue
        if _is_water(pid, str(domains.get(pid) or "")):
            continue
        g = by_id.get(pid)
        if g is None:
            bad.append(pid)
            continue
        if is_placeholder_ring(g.get("points") or []):
            bad.append(pid)
    return sorted(bad)


def _bboxes_overlap(a, b) -> bool:
    return not (a[2] < b[0] or b[2] < a[0] or a[3] < b[1] or b[3] < a[1])


def _cluster_windows(boxes: List[Tuple[int, Tuple[int, int, int, int]]], pad: int = 6):
    """Union overlapping boxes. Each box is (id, (minx, miny, maxx, maxy))."""
    items = []
    for pid, (x0, y0, x1, y1) in boxes:
        items.append([pid, x0 - pad, y0 - pad, x1 + pad, y1 + pad])
    changed = True
    while changed:
        changed = False
        out = []
        for box in items:
            merged = False
            for acc in out:
                if _bboxes_overlap(box[1:], acc[1:]):
                    acc[0] = box[0]
                    acc[1] = min(acc[1], box[1])
                    acc[2] = min(acc[2], box[2])
                    acc[3] = max(acc[3], box[3])
                    acc[4] = max(acc[4], box[4])
                    merged = True
                    changed = True
                    break
            if not merged:
                out.append(box)
        items = out
    return [(b[1], b[2], b[3], b[4]) for b in items]


def enclosed_hole_px(occupied_mask) -> int:
    """Largest empty component that does not touch the mask border."""
    npy = _require_numpy()
    height, width = occupied_mask.shape
    if height < 3 or width < 3:
        return 0
    empty = occupied_mask == 0
    if not bool(empty.any()):
        return 0
    seen = npy.zeros((height, width), npy.bool_)
    stack: deque = deque()

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
        return 0
    _comp, kept, _dropped = largest_component(holes.astype(npy.uint8))
    return int(kept)


def audit_board(geometry: Sequence[dict], domains: Dict[int, str], adjacency: Dict[str, List[int]]) -> List[str]:
    """Problems on the re-ringed provinces. Empty list is a pass.

    Requires meta gap_ussr_west2 on each real ring (absent on the base, so the
    caller also checks that those rings exist). Overlap is land-vs-land only.
    """
    _require_numpy()
    problems: List[str] = []
    by_id = {int(g["id"]): g for g in geometry}
    flagged = []
    for pid, g in by_id.items():
        meta = g.get("meta") if isinstance(g.get("meta"), dict) else {}
        if meta.get(META_RING):
            flagged.append(pid)
    if len(flagged) < 53:
        problems.append("rerings=%d want>=53" % len(flagged))
        return problems
    land_pts: Dict[int, Ring] = {}
    water_pts: Dict[int, Ring] = {}
    for pid, g in by_id.items():
        pts = open_ring(g.get("points") or [])
        if len(pts) < 3:
            continue
        if _is_water(pid, str(domains.get(pid) or "")):
            water_pts[pid] = pts
        else:
            land_pts[pid] = pts
    boxes = {pid: integer_bounds(pts, 0) for pid, pts in land_pts.items()}
    for pid in flagged:
        pts = land_pts.get(pid)
        if pts is None:
            problems.append("missing-land-ring %s" % pid)
            continue
        if is_placeholder_ring(pts):
            problems.append("still-placeholder %s n=%d" % (pid, len(pts)))
        if self_crosses(pts):
            problems.append("self-cross %s" % pid)
        nbrs = adjacency.get(str(pid)) or []
        if len(nbrs) < 1:
            problems.append("zero-neighbour %s" % pid)
        bb = boxes[pid]
        for oid, opts in land_pts.items():
            if oid == pid:
                continue
            if not _bboxes_overlap(bb, boxes[oid]):
                continue
            ov = overlap_px(pts, opts)
            if ov > OVERLAP_PX_MAX:
                problems.append("overlap %s x %s = %d px" % (pid, oid, ov))
                if len(problems) > 24:
                    return problems
    # Enclosed holes in the windows of the real rings. Sea/lake pixels are
    # occupied so a Caspian inlet is not a land hole.
    windows = _cluster_windows([(pid, boxes[pid]) for pid in flagged if pid in boxes])
    all_draw = []
    for pid, pts in land_pts.items():
        all_draw.append((pid, pts, boxes[pid], False))
    for pid, pts in water_pts.items():
        all_draw.append((pid, pts, integer_bounds(pts, 0), True))
    for win in windows:
        w = win[2] - win[0]
        h = win[3] - win[1]
        if w <= 0 or h <= 0 or w * h > 6_000_000:
            problems.append("window too big %s" % (win,))
            continue
        npy = _require_numpy()
        occ = npy.zeros((h, w), npy.uint8)
        for _pid, pts, bb, _water in all_draw:
            if not _bboxes_overlap(win, bb):
                continue
            part = rasterize_centers(pts, win[0], win[1], w, h)
            occ |= part
        hole = enclosed_hole_px(occ)
        if hole > HOLE_PX_MAX:
            problems.append("enclosed-hole %d px in %s" % (hole, win))
    return problems
