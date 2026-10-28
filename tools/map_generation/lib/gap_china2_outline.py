#!/usr/bin/env python3
"""Even-odd outline check for the GAP-CHINA-2 provinces 906111–906138.

Snap is 1e-4 px. A new outline fails when it crosses itself or overlaps
another land province by more than 1 px². Sea zones are coarse and are
not part of this gate.
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
