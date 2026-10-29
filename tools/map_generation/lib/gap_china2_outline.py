#!/usr/bin/env python3
"""Even-odd outline check for the GAP-CHINA-2 provinces 906111–906138.

Snap is 1e-4 px. A new outline fails when it crosses itself or overlaps
another land province by more than 1 px². Sea zones are coarse and are
not part of this gate.

audit_play_gaps also fails the theatre holes and thin labelled points from
the 908fee18 play pass, and the 1bf83066 residuals: any CHI×CHI nonzero
overlap over 1 px², any enclosed China hole over 500 px², and hairline
slivers between neighbouring CHI provinces. It is not a world-wide strip
check: many real micro-provinces are narrower than 8 px on purpose.
Sea overlaps are not counted.
"""
from __future__ import annotations

import math
from collections import defaultdict

SNAP = 1e-4
ANG_EPS = 1e-12


def snap(p):
    return (round(float(p[0]) / SNAP) * SNAP, round(float(p[1]) / SNAP) * SNAP)


def _orient(a, b, c):
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def _area(ring):
    a = 0.0
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        a += x1 * y2 - x2 * y1
    return a * 0.5


def _clean(ring):
    pts = [snap(p) for p in ring]
    if len(pts) >= 2 and pts[0] == pts[-1]:
        pts = pts[:-1]
    out = []
    for p in pts:
        if not out or p != out[-1]:
            out.append(p)
    if len(out) >= 2 and out[0] == out[-1]:
        out.pop()
    # drop a closing spike back to the previous point
    if len(out) >= 2 and out[0] == out[-1]:
        out.pop()
    return out


def _on_seg(a, b, p, tol=1e-8):
    if abs(_orient(a, b, p)) > max(1e-6, 1e-8 * (abs(b[0] - a[0]) + abs(b[1] - a[1]) + 1.0)):
        # relative: use cross vs edge length
        cross = abs(_orient(a, b, p))
        elen = math.hypot(b[0] - a[0], b[1] - a[1])
        if elen < 1e-12 or cross > 1e-7 * max(elen, 1.0):
            return False
    return (
        min(a[0], b[0]) - 1e-8 <= p[0] <= max(a[0], b[0]) + 1e-8
        and min(a[1], b[1]) - 1e-8 <= p[1] <= max(a[1], b[1]) + 1e-8
    )


def _seg_param_dist(a, b, p):
    """Parameter of the projection of p onto ab, and distance to the infinite line."""
    dx = b[0] - a[0]
    dy = b[1] - a[1]
    elen = math.hypot(dx, dy)
    if elen < 1e-15:
        return 0.0, math.hypot(p[0] - a[0], p[1] - a[1])
    t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (elen * elen)
    dist = abs(_orient(a, b, p)) / elen
    return t, dist


def _accept_split(a, b, p):
    """Snapped intersection points sit up to ~SNAP off the source line."""
    t, dist = _seg_param_dist(a, b, p)
    return -1e-7 <= t <= 1.0 + 1e-7 and dist <= SNAP * 3.0


def _seg_points(a, b, c, d):
    """Points where segment ab meets cd, including collinear overlap endpoints.

    A proper crossing is returned from the parametric hit. Snapping that point
    onto the 1e-4 grid moves it off both lines, so it must not be re-tested
    with a collinearity epsilon.
    """
    a, b, c, d = snap(a), snap(b), snap(c), snap(d)
    if a == b or c == d:
        return []
    o1 = _orient(a, b, c)
    o2 = _orient(a, b, d)
    o3 = _orient(c, d, a)
    o4 = _orient(c, d, b)
    elen = math.hypot(b[0] - a[0], b[1] - a[1]) + math.hypot(d[0] - c[0], d[1] - c[1])
    col_tol = 1e-7 * max(elen, 1.0)
    if abs(o1) <= col_tol and abs(o2) <= col_tol and abs(o3) <= col_tol and abs(o4) <= col_tol:
        pts = []
        for p in (a, b):
            if _on_seg(c, d, p) or _accept_split(c, d, p):
                pts.append(p)
        for p in (c, d):
            if _on_seg(a, b, p) or _accept_split(a, b, p):
                pts.append(p)
        return pts
    if (o1 < 0.0) != (o2 < 0.0) and (o3 < 0.0) != (o4 < 0.0) and o1 != 0.0 and o2 != 0.0 and o3 != 0.0 and o4 != 0.0:
        den = (a[0] - b[0]) * (c[1] - d[1]) - (a[1] - b[1]) * (c[0] - d[0])
        if abs(den) < 1e-18:
            return []
        t = ((a[0] - c[0]) * (c[1] - d[1]) - (a[1] - c[1]) * (c[0] - d[0])) / den
        u = ((a[0] - c[0]) * (a[1] - b[1]) - (a[1] - c[1]) * (a[0] - b[0])) / den
        if -1e-9 <= t <= 1.0 + 1e-9 and -1e-9 <= u <= 1.0 + 1e-9:
            pt = snap((a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])))
            return [pt]
        return []
    pts = []
    if abs(o1) <= col_tol and (_on_seg(a, b, c) or _accept_split(a, b, c)):
        pts.append(c)
    if abs(o2) <= col_tol and (_on_seg(a, b, d) or _accept_split(a, b, d)):
        pts.append(d)
    if abs(o3) <= col_tol and (_on_seg(c, d, a) or _accept_split(c, d, a)):
        pts.append(a)
    if abs(o4) <= col_tol and (_on_seg(c, d, b) or _accept_split(c, d, b)):
        pts.append(b)
    return pts


def _param(a, b, p):
    dx = b[0] - a[0]
    dy = b[1] - a[1]
    if abs(dx) >= abs(dy):
        if abs(dx) < 1e-15:
            return 0.0
        return (p[0] - a[0]) / dx
    return (p[1] - a[1]) / dy


def _winding(ring, x, y):
    wn = 0
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        if y1 <= y:
            if y2 > y and _orient((x1, y1), (x2, y2), (x, y)) > 0.0:
                wn += 1
        else:
            if y2 <= y and _orient((x1, y1), (x2, y2), (x, y)) < 0.0:
                wn -= 1
    return wn


_RAYS = ((1.0, 0.137), (0.61, 0.97), (-0.41, 0.83), (0.23, -0.95), (0.91, -0.29))


def _even_odd(ring, x, y):
    """Robust even-odd. Retries the ray when it passes through a vertex."""
    n = len(ring)
    last = 0
    for dx, dy in _RAYS:
        crossings = 0
        bad = False
        for i in range(n):
            x1, y1 = ring[i]
            x2, y2 = ring[(i + 1) % n]
            # ray p + t * d, t>0, against segment, u in [0,1]
            rx, ry = x2 - x1, y2 - y1
            den = dx * ry - dy * rx
            if abs(den) < 1e-15:
                # parallel. bad if the point is nearly on the infinite line and the segment is ahead
                if abs(_orient((x1, y1), (x2, y2), (x, y))) <= 1e-8 * (abs(rx) + abs(ry) + 1.0):
                    bad = True
                    break
                continue
            t = ((x1 - x) * ry - (y1 - y) * rx) / den
            u = ((x1 - x) * dy - (y1 - y) * dx) / den
            if t > 1e-9 and -1e-9 <= u <= 1.0 + 1e-9:
                if u < 1e-7 or u > 1.0 - 1e-7:
                    bad = True
                    break
                crossings += 1
        if not bad:
            return (crossings % 2) == 1
        last = crossings
    return (last % 2) == 1


def _inside_any(rings, x, y):
    return any(_even_odd(r, x, y) for r in rings)


def _point_in_face(face, x, y):
    """Even-odd ray cast. Face rings are simple cycles from the walk."""
    n = len(face)
    inside = False
    j = n - 1
    for i in range(n):
        xi, yi = face[i]
        xj, yj = face[j]
        if (yi > y) != (yj > y):
            xint = (xj - xi) * (y - yi) / (yj - yi) + xi
            if x < xint:
                inside = not inside
        j = i
    return inside


def _interior_point(face):
    """A point in the face. Left of the walk.

    Positive-area cycles are bounded: the face is the even-odd interior.
    Negative-area cycles are the unbounded side: the face is outside the ring.
    """
    n = len(face)
    want_inside = _area(face) > 0.0
    fallback = None
    for i in range(n):
        a = face[i]
        b = face[(i + 1) % n]
        dx = b[0] - a[0]
        dy = b[1] - a[1]
        ln = math.hypot(dx, dy)
        if ln < 1e-9:
            continue
        mx = (a[0] + b[0]) * 0.5
        my = (a[1] + b[1]) * 0.5
        nx = -dy / ln
        ny = dx / ln
        for scale in (1e-4, 1e-3, 1e-2, 0.05):
            step = min(scale, ln * 0.25)
            pt = (mx + nx * step, my + ny * step)
            inside = _point_in_face(face, pt[0], pt[1])
            if inside == want_inside:
                return pt
            if fallback is None:
                fallback = pt
    if want_inside:
        cx = sum(p[0] for p in face) / n
        cy = sum(p[1] for p in face) / n
        if _point_in_face(face, cx, cy):
            return (cx, cy)
    return fallback if fallback is not None else face[0]


class _Arr:
    def __init__(self, rings):
        self.rings = [_clean(r) for r in rings if len(_clean(r)) >= 3]
        self._build()

    def _build(self):
        segs = []
        for r in self.rings:
            n = len(r)
            for i in range(n):
                a, b = r[i], r[(i + 1) % n]
                if a != b:
                    segs.append((a, b))
        # split points per segment
        splits = [[] for _ in segs]
        for i, (a, b) in enumerate(segs):
            splits[i].append(a)
            splits[i].append(b)
        for i in range(len(segs)):
            a, b = segs[i]
            for j in range(i + 1, len(segs)):
                c, d = segs[j]
                # bbox reject
                if max(a[0], b[0]) < min(c[0], d[0]) - 1e-6:
                    continue
                if max(c[0], d[0]) < min(a[0], b[0]) - 1e-6:
                    continue
                if max(a[1], b[1]) < min(c[1], d[1]) - 1e-6:
                    continue
                if max(c[1], d[1]) < min(a[1], b[1]) - 1e-6:
                    continue
                for p in _seg_points(a, b, c, d):
                    splits[i].append(p)
                    splits[j].append(p)
        # atomic undirected edges
        edges = set()
        for i, (a, b) in enumerate(segs):
            pts = []
            seen = set()
            for p in splits[i]:
                p = snap(p)
                if p not in seen and _accept_split(a, b, p):
                    seen.add(p)
                    pts.append(p)
            pts.sort(key=lambda p: _param(a, b, p))
            for u, v in zip(pts, pts[1:]):
                if u != v:
                    edges.add((u, v) if u < v else (v, u))
        # graph
        adj = defaultdict(list)
        for u, v in edges:
            ang_uv = math.atan2(v[1] - u[1], v[0] - u[0])
            ang_vu = math.atan2(u[1] - v[1], u[0] - v[0])
            adj[u].append((ang_uv, v))
            adj[v].append((ang_vu, u))
        for k in adj:
            adj[k].sort(key=lambda t: t[0])
        self.adj = adj
        self.edges = edges
        # face walk
        used = set()
        faces = []  # list of vertex rings
        half_face = {}
        for u, v in list(edges):
            for a, b in ((u, v), (v, u)):
                if (a, b) in used:
                    continue
                face = []
                s, prev = a, None
                cur = a
                nxt = b
                guard = 0
                while guard < 100000:
                    guard += 1
                    if (cur, nxt) in used:
                        break
                    used.add((cur, nxt))
                    face.append(cur)
                    half_face[(cur, nxt)] = len(faces)
                    outs = adj[nxt]
                    # find outgoing nxt->cur
                    rev = None
                    for i, (_ang, w) in enumerate(outs):
                        if w == cur:
                            rev = i
                            break
                    if rev is None or not outs:
                        break
                    # previous in CCW order = clockwise next = face on left
                    _ang, w = outs[(rev - 1) % len(outs)]
                    cur, nxt = nxt, w
                    if cur == a and nxt == b:
                        break
                else:
                    continue
                if len(face) >= 3:
                    faces.append(face)
        self.faces = faces
        self.half_face = half_face

    def select(self, keep_fn):
        """keep_fn(face_index, interior_point) -> bool. Returns CCW outer loops."""
        interior = set()
        for i, face in enumerate(self.faces):
            pt = _interior_point(face)
            if keep_fn(i, pt):
                interior.add(i)
        boundary = []
        for (u, v), fid in self.half_face.items():
            twin = self.half_face.get((v, u))
            if fid in interior and twin not in interior:
                boundary.append((u, v))
        if not boundary:
            return []
        outs = defaultdict(list)
        for u, v in boundary:
            outs[u].append(v)
        # successor
        succ = {}
        incoming = defaultdict(list)
        for u, v in boundary:
            incoming[v].append(u)
        for u, v in boundary:
            cands = outs[v]
            if len(cands) == 1:
                succ[(u, v)] = cands[0]
                continue
            # arrival angle
            ain = math.atan2(v[1] - u[1], v[0] - u[0])
            # reverse heading
            rev = ain + math.pi
            if rev > math.pi:
                rev -= 2 * math.pi
            # choose outgoing whose heading is the first clockwise from rev
            best = None
            for w in cands:
                aout = math.atan2(w[1] - v[1], w[0] - v[0])
                # clockwise delta from rev to aout
                delta = rev - aout
                while delta < 0:
                    delta += 2 * math.pi
                while delta >= 2 * math.pi:
                    delta -= 2 * math.pi
                # delta==0 means going straight back; allow it but prefer a real turn if present
                if best is None or delta < best[0] - 1e-12:
                    best = (delta, w)
            succ[(u, v)] = best[1]
        used = set()
        loops = []
        for e0 in boundary:
            if e0 in used:
                continue
            u, v = e0
            loop = [u]
            guard = 0
            while guard < 100000:
                guard += 1
                used.add((u, v))
                w = succ.get((u, v))
                if w is None:
                    break
                loop.append(v)
                if v == e0[0] and w == e0[1]:
                    break
                u, v = v, w
                if (u, v) == e0:
                    break
            if len(loop) >= 4 and loop[0] == loop[-1]:
                loop = loop[:-1]
            if len(loop) >= 3 and abs(_area(loop)) > 1e-6:
                loops.append(loop)
        return loops


def _chain(boundary):
    if not boundary:
        return []
    outs = defaultdict(list)
    for u, v in boundary:
        outs[u].append(v)
    succ = {}
    for u, v in boundary:
        cands = outs[v]
        if len(cands) == 1:
            succ[(u, v)] = cands[0]
            continue
        ain = math.atan2(v[1] - u[1], v[0] - u[0])
        rev = ain + math.pi
        if rev > math.pi:
            rev -= 2 * math.pi
        best = None
        for w in cands:
            aout = math.atan2(w[1] - v[1], w[0] - v[0])
            delta = rev - aout
            while delta <= 1e-9:
                delta += 2 * math.pi
            if best is None or delta < best[0]:
                best = (delta, w)
        succ[(u, v)] = best[1]
    used = set()
    loops = []
    for e0 in boundary:
        if e0 in used:
            continue
        u, v = e0
        loop = [u]
        guard = 0
        while guard < 100000:
            guard += 1
            used.add((u, v))
            w = succ.get((u, v))
            if w is None:
                break
            loop.append(v)
            if (v, w) == e0:
                break
            u, v = v, w
        if len(loop) >= 4 and loop[0] == loop[-1]:
            loop = loop[:-1]
        if len(loop) >= 3 and abs(_area(loop)) > 1e-4:
            loops.append(loop)
    return loops


def _boundary_by_predicate(rings, pred):
    """Directed boundary edges with pred True on the left. rings are already clean."""
    arr = _Arr(rings)
    boundary = []
    for u, v in arr.edges:
        dx = v[0] - u[0]
        dy = v[1] - u[1]
        ln = math.hypot(dx, dy)
        if ln < 1e-12:
            continue
        nx, ny = -dy / ln, dx / ln
        mx = (u[0] + v[0]) * 0.5
        my = (u[1] + v[1]) * 0.5
        chosen = None
        for scale in (1e-3, 1e-2, 0.05, 0.25, 1.0):
            step = min(scale, ln * 0.45)
            lp = (mx + nx * step, my + ny * step)
            rp = (mx - nx * step, my - ny * step)
            lt = pred(lp[0], lp[1])
            rt = pred(rp[0], rp[1])
            if lt == rt:
                continue
            chosen = (u, v) if lt else (v, u)
            break
        if chosen:
            boundary.append(chosen)
    return _chain(boundary)


def _odd_boundary_loops(ring_c):
    """Cycles of atomic edges used an odd number of times by the ring.

    Even-odd fill changes only across those edges. Walk them by the sharpest
    left turn so each cycle is consistently oriented.
    """
    arr = _Arr([ring_c])
    # count original-ring traversals of each atomic undirected edge
    counts = defaultdict(int)
    segs = []
    n = len(ring_c)
    for i in range(n):
        a, b = ring_c[i], ring_c[(i + 1) % n]
        if a != b:
            segs.append((a, b))
    # map each original segment onto the atomic edges it was split into
    # by walking the split points we already stored implicitly: re-split
    for i, (a, b) in enumerate(segs):
        pts = [a, b]
        for u, v in arr.edges:
            for p in (u, v):
                if p != a and p != b and _accept_split(a, b, p):
                    pts.append(p)
        uniq = []
        seen = set()
        for p in pts:
            if p not in seen:
                seen.add(p)
                uniq.append(p)
        uniq.sort(key=lambda p: _param(a, b, p))
        for u, v in zip(uniq, uniq[1:]):
            if u == v:
                continue
            key = (u, v) if u < v else (v, u)
            counts[key] += 1
    odd = [e for e, c in counts.items() if c % 2 == 1]
    adj = defaultdict(list)
    for u, v in odd:
        adj[u].append(v)
        adj[v].append(u)
    for k in adj:
        adj[k].sort(key=lambda w: math.atan2(w[1] - k[1], w[0] - k[0]))
    # half-edge walk: next is the previous in CCW order (sharpest left / clockwise next)
    used = set()
    loops = []
    for u0, v0 in odd:
        for a0, b0 in ((u0, v0), (v0, u0)):
            if (a0, b0) in used:
                continue
            u, v = a0, b0
            loop = [u]
            guard = 0
            while guard < 100000:
                guard += 1
                used.add((u, v))
                outs = adj[v]
                rev = outs.index(u)
                w = outs[(rev - 1) % len(outs)]
                loop.append(v)
                u, v = v, w
                if (u, v) == (a0, b0):
                    break
            if len(loop) >= 4 and loop[0] == loop[-1]:
                loop = loop[:-1]
            if len(loop) >= 3 and abs(_area(loop)) > 1e-4:
                loops.append(loop)
    # keep the orientation whose interior test matches the even-odd fill
    kept = []
    for loop in loops:
        pt = _interior_point(loop if _area(loop) > 0 else list(reversed(loop)))
        # _interior_point assumes the ring it is given. Force a positive copy.
        pos = loop if _area(loop) > 0 else list(reversed(loop))
        pt = _interior_point(pos)
        if _even_odd(ring_c, pt[0], pt[1]):
            kept.append(pos)
        else:
            # the other side of this cycle may be the interior (hole vs outer)
            neg = list(reversed(pos))
            pt2 = _interior_point(neg) if _area(neg) > 0 else None
            if pt2 and _even_odd(ring_c, pt2[0], pt2[1]):
                kept.append(neg)
    return kept


def covered_loops(ring):
    """Simple loops of the even-odd region of one ring."""
    ring_c = _clean(ring)
    if len(ring_c) < 3:
        return []
    arr = _Arr([ring_c])

    def keep(_i, pt):
        return _even_odd(ring_c, pt[0], pt[1])

    loops = arr.select(keep)
    out = []
    for loop in loops:
        if _area(loop) < 0.0:
            loop = list(reversed(loop))
        if _area(loop) >= 0.5:
            out.append(loop)
    return out


def region_loops(subject_rings, clip_rings=None, mode="union"):
    """mode union: inside any subject. difference: inside subject, outside every clip."""
    subs = [_clean(r) for r in subject_rings if len(_clean(r)) >= 3]
    clips = [_clean(r) for r in (clip_rings or []) if len(_clean(r)) >= 3]
    if not subs:
        return []
    arr = _Arr(subs + clips)

    def keep(_i, pt):
        inside_s = _inside_any(subs, pt[0], pt[1])
        if mode == "union":
            return inside_s
        return inside_s and not _inside_any(clips, pt[0], pt[1])

    loops = arr.select(keep)
    out = []
    for loop in loops:
        if _area(loop) < 0.0:
            loop = list(reversed(loop))
        if abs(_area(loop)) >= 0.5:
            out.append(loop)
    return out


def largest_loop(loops, min_area=0.5):
    best = None
    best_a = 0.0
    for loop in loops:
        a = _area(loop)
        if a > best_a and a >= min_area:
            best = loop
            best_a = a
    return best, best_a


def as_points(loop, nd=6):
    if not loop:
        return []
    # ensure CCW
    if _area(loop) < 0:
        loop = list(reversed(loop))
    return [[round(p[0], nd), round(p[1], nd)] for p in loop]


NEW_LO = 906111
NEW_HI = 906138
OVERLAP_LIMIT = 1.0
_WATER = frozenset({"sea", "strait", "lake", "ocean"})


def _open_ring(points):
    pts = [(float(p[0]), float(p[1])) for p in points or []]
    if len(pts) >= 2 and pts[0] == pts[-1]:
        pts = pts[:-1]
    return pts


def _bbox(ring):
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    return min(xs), min(ys), max(xs), max(ys)


def _bbox_hit(a, b):
    return not (a[2] < b[0] or b[2] < a[0] or a[3] < b[1] or b[3] < a[1])


def _self_kinds(ring):
    """Non-adjacent edge meetings: proper cross, collinear overlap, or touch."""
    n = len(ring)
    kinds = []
    if n < 3:
        return ["short"]
    for i in range(n):
        if ring[i] == ring[(i + 1) % n]:
            kinds.append("dup_consec")
            break
    for i in range(n):
        a, b = ring[i], ring[(i + 1) % n]
        for j in range(i + 1, n):
            if (j + 1) % n == i or (i + 1) % n == j:
                continue
            c, d = ring[j], ring[(j + 1) % n]
            hits = _seg_points(a, b, c, d)
            if not hits:
                continue
            # A shared endpoint of two edges that only meet at that vertex
            # still makes the ring non-simple when the edges are not adjacent.
            kinds.append("cross")
            return kinds
    return kinds


def _fill_parts(ring, cache, pid):
    """Even-odd pieces. Bridges in a self-crossing ring are not fill."""
    got = cache.get(pid)
    if got is None:
        got = [l for l in covered_loops(ring) if _area(l) >= 0.5]
        cache[pid] = got
    return got


def _overlap_area(a_parts, b_parts):
    """Area of the even-odd fill of A that also lies in the even-odd fill of B."""
    if not a_parts or not b_parts:
        return 0.0
    before = sum(_area(l) for l in a_parts)
    diff = region_loops(a_parts, b_parts, "difference")
    after = sum(_area(l) for l in diff if _area(l) > 0.0)
    lost = before - after
    return lost if lost > 0.0 else 0.0


def audit_outlines(geometries, domains):
    """Return problem rows for provinces 906111–906138.

    geometries: iterable of {"id", "points"}. domains: id -> domain string.
    """
    rings = {}
    boxes = {}
    for g in geometries:
        pid = int(g["id"])
        ring = _open_ring(g.get("points"))
        if len(ring) < 3:
            continue
        rings[pid] = ring
        boxes[pid] = _bbox(ring)
    land = []
    for pid, ring in rings.items():
        if domains.get(pid) in _WATER or pid >= 950000:
            continue
        land.append(pid)
    problems = []
    fill_cache = {}
    for pid in range(NEW_LO, NEW_HI + 1):
        ring = rings.get(pid)
        if ring is None:
            problems.append({"id": pid, "kind": "missing"})
            continue
        kinds = _self_kinds(ring)
        if kinds:
            problems.append({"id": pid, "kind": "self", "detail": kinds})
        bb = boxes[pid]
        for oid in land:
            if oid == pid:
                continue
            if not _bbox_hit(bb, boxes[oid]):
                continue
            # Cheap reject: no vertex of either ring inside the other and no hit.
            other = rings[oid]
            hit = False
            for p in ring:
                if bb[0] <= p[0] <= bb[2] and _even_odd(other, p[0], p[1]):
                    hit = True
                    break
            if not hit:
                for p in other:
                    if _even_odd(ring, p[0], p[1]):
                        hit = True
                        break
            if not hit:
                # boundary cross
                n = len(ring)
                m = len(other)
                for i in range(n):
                    a, b = ring[i], ring[(i + 1) % n]
                    for j in range(m):
                        if _seg_points(a, b, other[j], other[(j + 1) % m]):
                            hit = True
                            break
                    if hit:
                        break
            if not hit:
                continue
            lost = _overlap_area(
                _fill_parts(ring, fill_cache, pid),
                _fill_parts(other, fill_cache, oid),
            )
            if lost > OVERLAP_LIMIT:
                problems.append({"id": pid, "kind": "overlap", "other": oid, "area": round(lost, 3)})
    return problems


# Labelled points that rendered as strips on 908fee18, plus the neighbours
# that take the enclosed holes. A self-crossing ring is width 0: the fill
# path triangulates the raw ring, not the even-odd area.
STRIP_MIN = 8.0
THEATER_STRIP_IDS = (
    902598,  # Hunan North, self-crossing on 908fee18
    902634,  # Yunnan East, self-crossing, takes part of the southwest hole
    906013,  # Chongqing
    906015,  # Chengdu
    906019,  # Guiyang
    906112,  # Lhasa, takes the Tibet specks it touches
    906113,  # Changtang, takes the Tibet hole
    906114,
    906122,
    906130,
    906131,
    906132,
    906133,
    906134,
    906135,
)

# Integer canvas points. Each square is entirely unowned on 908fee18 and sits
# inside the play hole with a margin, so a 1 px boundary shave still leaves it
# inside the filled province. rad is an inclusive half-width. min_empty is the
# failure threshold (px).
_SOLID_HOLES = (
    ("sw_core", 6444, 1616, 10, 30),       # ~41.2k enclosed southwest hole
    ("yunnan_band", 6334, 1726, 3, 30),    # Yunnan side of the ~48k gap
    ("hunan_hole", 6616, 1504, 4, 30),     # ~2.6k hole beside Hunan
    ("tibet_hole", 6079, 1384, 3, 30),     # 906113 hole
)
# The three Tibet specks (21 + 3 + 1 px). Inclusive pixel-center box.
_SPECK_BOX = ("tibet_specks", 6156, 1495, 6172, 1528, 8)
_SPECK_PROBES = (
    ("tibet_speck_21", 6161, 1501),
    ("tibet_speck_3", 6164, 1509),
    ("tibet_speck_1", 6170, 1527),
)


def label_strip_width(points, anchor):
    """Minimum chord in px through the labelled point.

    Self-crossing and missing rings return 0. The chord is the shortest of
    16 axes. A point outside the ring returns 0.
    """
    ring = _open_ring(points)
    if len(ring) < 3 or not anchor or len(anchor) < 2:
        return 0.0
    if _self_kinds(ring):
        return 0.0
    if _area(ring) < 0.0:
        ring = list(reversed(ring))
    x = float(anchor[0])
    y = float(anchor[1])
    if not _point_in_face(ring, x, y):
        return 0.0
    best = 1e9
    for k in range(16):
        ang = math.pi * k / 16.0
        dx = math.cos(ang)
        dy = math.sin(ang)

        def _reach(sgn, dx=dx, dy=dy):
            span = 0.25
            while span < 800.0 and _point_in_face(ring, x + sgn * dx * span, y + sgn * dy * span):
                span *= 1.7
            if span >= 800.0:
                return 800.0
            lo = 0.0 if span <= 0.25 else span / 1.7
            hi = span
            if lo > 0.0 and not _point_in_face(ring, x + sgn * dx * lo, y + sgn * dy * lo):
                lo = 0.0
            for _ in range(22):
                mid = (lo + hi) * 0.5
                if _point_in_face(ring, x + sgn * dx * mid, y + sgn * dy * mid):
                    lo = mid
                else:
                    hi = mid
            return lo

        width = _reach(1.0) + _reach(-1.0)
        if width < best:
            best = width
    return best


def _loops_of(ring):
    """Simple even-odd pieces. A simple ring is used as-is."""
    if len(ring) < 3:
        return []
    if _self_kinds(ring):
        return [l for l in covered_loops(ring) if _area(l) > 0.0]
    if _area(ring) < 0.0:
        ring = list(reversed(ring))
    return [ring]


def _hole_candidates(rings, boxes):
    """Land fill loops whose bbox meets any test box."""
    out = []
    for pid, ring in rings.items():
        bb = _bbox(ring)
        hit = False
        for x0, y0, x1, y1 in boxes:
            if not (bb[2] < x0 or x1 < bb[0] or bb[3] < y0 or y1 < bb[1]):
                hit = True
                break
        if not hit:
            continue
        loops = _loops_of(ring)
        if loops:
            out.append((bb, loops))
    return out


# 1936 CHI land. Sea zones are not in this set. Coarse sea overlaps
# (906112×950302 8059.4, 906112×950308 1962.6, 906136×950011 426.4)
# are pre-existing and are not a CHI×CHI check.
CHI_LAND_IDS = frozenset((
    902487, 902491, 902493, 902496, 902504, 902505, 902514, 902521, 902523,
    902526, 902534, 902544, 902564, 902566, 902568, 902569, 902590, 902598,
    902601, 902633, 902634, 902646,
    906009, 906010, 906011, 906012, 906013, 906014, 906015, 906016, 906017,
    906018, 906019, 906020,
    906111, 906112, 906113, 906114, 906115, 906116, 906117, 906118, 906119,
    906120, 906121, 906122, 906123, 906124, 906125, 906126, 906127, 906128,
    906129, 906130, 906131, 906132, 906133, 906134, 906135, 906136, 906137,
    906138,
))
# Bounded unowned face of the CHI arrangement. The 1bf83066 holes are
# 2415 / 1397 / 1037 / 784 in Xinjiang and 761 near (6532, 1355), plus the
# wider central gaps the same test catches.
HOLE_AREA_LIMIT = 500.0
# Samples 0.75 and 1.5 px off a CHI edge that sit in no land and within
# 2 px of a second CHI province. One sample is about 1 px of border.
SLIVER_REACH = 2.0
SLIVER_LENGTH_LIMIT = 80.0


def _chi_rings(rings):
    return sorted(pid for pid in CHI_LAND_IDS if pid in rings and len(rings[pid]) >= 3)


def _nz_pair_area(ring_a, ring_b):
    """Area where both rings have a nonzero winding."""
    arr = _Arr([ring_a, ring_b])

    def keep(_i, pt, ring_a=ring_a, ring_b=ring_b):
        return _winding(ring_a, pt[0], pt[1]) != 0 and _winding(ring_b, pt[0], pt[1]) != 0

    return sum(abs(_area(loop)) for loop in arr.select(keep))


def _chi_overlap_problems(rings):
    ids = _chi_rings(rings)
    boxes = {pid: _bbox(rings[pid]) for pid in ids}
    problems = []
    for i, aid in enumerate(ids):
        ra, ba = rings[aid], boxes[aid]
        for bid in ids[i + 1:]:
            bb = boxes[bid]
            if ba[2] < bb[0] or bb[2] < ba[0] or ba[3] < bb[1] or bb[3] < ba[1]:
                continue
            area = _nz_pair_area(ra, rings[bid])
            if area > OVERLAP_LIMIT:
                problems.append({
                    "kind": "chi_overlap",
                    "id": aid,
                    "other": bid,
                    "area": round(area, 3),
                })
    return problems


def _chi_hole_loops(rings):
    """Positive-area CHI faces outside every CHI nonzero fill."""
    ids = _chi_rings(rings)
    chi = [rings[pid] for pid in ids]
    if not chi:
        return []
    boxes = [_bbox(ring) for ring in chi]
    arr = _Arr(chi)

    def outside(pt, chi=chi, boxes=boxes):
        x, y = pt
        for ring, bb in zip(chi, boxes):
            if x < bb[0] - 0.2 or x > bb[2] + 0.2 or y < bb[1] - 0.2 or y > bb[3] + 0.2:
                continue
            if _winding(ring, x, y) != 0:
                return False
        return True

    loops = []
    for loop in arr.select(lambda _i, pt: outside(pt)):
        if _area(loop) > HOLE_AREA_LIMIT:
            loops.append(loop)
    return loops


def _chi_hole_problems(rings):
    problems = []
    for loop in _chi_hole_loops(rings):
        area = _area(loop)
        cx = sum(p[0] for p in loop) / len(loop)
        cy = sum(p[1] for p in loop) / len(loop)
        problems.append({
            "kind": "chi_hole",
            "area": round(area, 1),
            "x": round(cx, 1),
            "y": round(cy, 1),
        })
    problems.sort(key=lambda row: -row["area"])
    return problems


def _sliver_length(rings):
    """Length of CHI edge, in px, that has unowned land within 2 px of two CHI provinces.

    A sample is taken every 1 px along each CHI edge, 0.75 px and 1.5 px to
    either side. It counts when that point is outside every land ring, the
    nearest other CHI edge is at most SLIVER_REACH px away, and the sample
    sits between this edge and that neighbour. Each count adds the sample
    spacing. A retraced edge can contribute twice.
    """
    ids = _chi_rings(rings)
    edges = []
    for pid in ids:
        ring = rings[pid]
        n = len(ring)
        for i in range(n):
            a, b = ring[i], ring[(i + 1) % n]
            if a != b:
                edges.append((pid, a[0], a[1], b[0], b[1]))
    cell = 8.0
    grid = defaultdict(list)
    for i, (_pid, ax, ay, bx, by) in enumerate(edges):
        x0, x1 = (ax, bx) if ax <= bx else (bx, ax)
        y0, y1 = (ay, by) if ay <= by else (by, ay)
        gx0 = int(math.floor(x0 / cell)) - 1
        gx1 = int(math.floor(x1 / cell)) + 1
        gy0 = int(math.floor(y0 / cell)) - 1
        gy1 = int(math.floor(y1 / cell)) + 1
        for gx in range(gx0, gx1 + 1):
            for gy in range(gy0, gy1 + 1):
                grid[(gx, gy)].append(i)
    chi_boxes = {pid: _bbox(rings[pid]) for pid in ids}
    foreign = []
    for pid, ring in rings.items():
        if pid in CHI_LAND_IDS or len(ring) < 3:
            continue
        foreign.append((ring, _bbox(ring)))

    def owns_chi(x, y):
        for pid in ids:
            bb = chi_boxes[pid]
            if x < bb[0] - 0.4 or x > bb[2] + 0.4 or y < bb[1] - 0.4 or y > bb[3] + 0.4:
                continue
            if _winding(rings[pid], x, y) != 0:
                return True
        return False

    def owns_foreign(x, y):
        for ring, bb in foreign:
            if x < bb[0] or x > bb[2] or y < bb[1] or y > bb[3]:
                continue
            if _winding(ring, x, y) != 0:
                return True
        return False

    def nearest_other(x, y, skip, reach=SLIVER_REACH):
        best = 1e18
        best_pid = None
        best_q = (x, y)
        gx0 = int(math.floor((x - reach) / cell))
        gx1 = int(math.floor((x + reach) / cell))
        gy0 = int(math.floor((y - reach) / cell))
        gy1 = int(math.floor((y + reach) / cell))
        seen = set()
        for gx in range(gx0, gx1 + 1):
            for gy in range(gy0, gy1 + 1):
                for j in grid.get((gx, gy), ()):
                    if j in seen:
                        continue
                    seen.add(j)
                    pid, ax, ay, bx, by = edges[j]
                    if pid == skip:
                        continue
                    vx, vy = bx - ax, by - ay
                    el2 = vx * vx + vy * vy
                    if el2 < 1e-18:
                        d = math.hypot(x - ax, y - ay)
                        q = (ax, ay)
                    else:
                        t = max(0.0, min(1.0, ((x - ax) * vx + (y - ay) * vy) / el2))
                        q = (ax + t * vx, ay + t * vy)
                        d = math.hypot(x - q[0], y - q[1])
                    if d < best:
                        best = d
                        best_pid = pid
                        best_q = q
        return best, best_pid, best_q

    total = 0.0
    for pid, ax, ay, bx, by in edges:
        dx, dy = bx - ax, by - ay
        el = math.hypot(dx, dy)
        if el < 1.0:
            continue
        nx, ny = -dy / el, dx / el
        nstep = max(1, int(el))
        spacing = el / nstep
        for s in range(nstep):
            t = (s + 0.5) / nstep
            mx = ax + dx * t
            my = ay + dy * t
            hit = False
            for dist in (0.75, 1.5):
                if hit:
                    break
                for sgn in (1.0, -1.0):
                    px = mx + sgn * nx * dist
                    py = my + sgn * ny * dist
                    if owns_chi(px, py):
                        continue
                    d, _qid, _q = nearest_other(px, py, pid)
                    if d > SLIVER_REACH:
                        continue
                    # A coincident shared border leaves the seaward sample
                    # 0.75 px from both edges. Count the sample only when the
                    # edges themselves are 0.35–3.6 px apart and the sample
                    # lies in that gap, not beyond a corner or a thin coast.
                    d_edge, _eid, qe = nearest_other(mx, my, pid, reach=4.0)
                    if d_edge < 0.35 or d_edge > 3.6:
                        continue
                    vx, vy = qe[0] - mx, qe[1] - my
                    el2 = vx * vx + vy * vy
                    if el2 < 1e-8:
                        continue
                    proj = ((px - mx) * vx + (py - my) * vy) / el2
                    if proj < 0.15 or proj > 0.92:
                        continue
                    if owns_foreign(px, py):
                        continue
                    total += spacing
                    hit = True
                    break
    return total


def _owned(cands, x, y):
    for bb, loops in cands:
        if x < bb[0] - 0.1 or x > bb[2] + 0.1 or y < bb[1] - 0.1 or y > bb[3] + 0.1:
            continue
        for loop in loops:
            if _point_in_face(loop, x, y):
                return True
    return False


def audit_play_gaps(geometries, domains):
    """Theatre gaps from 908fee18, plus the 1bf83066 China residuals.

    Fails when a theatre label sits in a strip narrower than 8 px, when an
    interior square of a named hole is still unowned, when two CHI land
    provinces overlap by more than 1 px² (nonzero winding), when an enclosed
    CHI face is larger than 500 px², or when hairline samples between two CHI
    provinces exceed SLIVER_LENGTH_LIMIT. Sea overlaps are not counted.
    """
    rings = {}
    for g in geometries:
        pid = int(g["id"])
        ring = _open_ring(g.get("points"))
        if len(ring) < 3:
            continue
        if domains.get(pid) in _WATER or pid >= 950000:
            continue
        rings[pid] = ring
    by_anchor = {}
    for g in geometries:
        by_anchor[int(g["id"])] = g.get("label_anchor")
    problems = []
    for pid in THEATER_STRIP_IDS:
        ring = rings.get(pid)
        if ring is None:
            problems.append({"kind": "strip", "id": pid, "detail": "missing"})
            continue
        width = label_strip_width(ring, by_anchor.get(pid))
        if width < STRIP_MIN:
            problems.append({"kind": "strip", "id": pid, "width": round(width, 2)})
    boxes = []
    for name, cx, cy, rad, _vmin in _SOLID_HOLES:
        boxes.append((cx - rad, cy - rad, cx + rad, cy + rad))
    sx0, sy0, sx1, sy1 = _SPECK_BOX[1], _SPECK_BOX[2], _SPECK_BOX[3], _SPECK_BOX[4]
    boxes.append((sx0, sy0, sx1, sy1))
    cands = _hole_candidates(rings, boxes)
    for name, cx, cy, rad, vmin in _SOLID_HOLES:
        empty = 0
        for dy in range(-rad, rad + 1):
            for dx in range(-rad, rad + 1):
                if not _owned(cands, cx + dx, cy + dy):
                    empty += 1
        if empty >= vmin:
            problems.append({"kind": "hole", "name": name, "empty": empty, "min": vmin})
    speck_empty = 0
    for y in range(sy0, sy1 + 1):
        for x in range(sx0, sx1 + 1):
            if not _owned(cands, x, y):
                speck_empty += 1
    if speck_empty >= _SPECK_BOX[5]:
        problems.append({
            "kind": "hole",
            "name": _SPECK_BOX[0],
            "empty": speck_empty,
            "min": _SPECK_BOX[5],
        })
    for name, x, y in _SPECK_PROBES:
        if not _owned(cands, x, y):
            problems.append({"kind": "unowned", "name": name, "x": x, "y": y})
    problems.extend(_chi_overlap_problems(rings))
    problems.extend(_chi_hole_problems(rings))
    sliver = _sliver_length(rings)
    if sliver > SLIVER_LENGTH_LIMIT:
        problems.append({
            "kind": "sliver",
            "length": round(sliver, 1),
            "limit": SLIVER_LENGTH_LIMIT,
        })
    return problems
