"""Hidden hex authoring lattice (HEXP3 Rhineland pilot).

Flat-top axial hexes on one global origin, with a spherical Lambert azimuthal
equal-area (LAEA) projection. Hexes never reach runtime; this module is offline
authoring only.

Mutant hooks (tests edit these, then revert):
  SUBSAMPLE_ENABLED — 5-mi (9-per-hex) samples; dropping it must fail T2.
  RANDOM_ORIGIN_PER_RUN — non-zero random origin shift; enabling it must fail T4.
"""
from __future__ import annotations

import math
import random
from typing import Iterable, List, Optional, Sequence, Tuple

# --- mutant hooks (real source edits in test_hex_pilot_rhineland.py) ---
SUBSAMPLE_ENABLED: bool = True
RANDOM_ORIGIN_PER_RUN: bool = False

# Spherical authalic radius (m). Good enough for a ~400 km theater.
EARTH_RADIUS_M: float = 6371007.2
MILES_TO_M: float = 1609.344
KM_TO_M: float = 1000.0

# Flat-top axial neighbours (q, r).
HEX_DIRECTIONS: Tuple[Tuple[int, int], ...] = (
    (1, 0),
    (1, -1),
    (0, -1),
    (-1, 0),
    (-1, 1),
    (0, 1),
)

# 3x3 axial offsets on the 5-mi lattice covering one 15-mi parent (9 samples).
SUBSAMPLE_AXIAL_OFFSETS: Tuple[Tuple[int, int], ...] = tuple(
    (dq, dr) for dq in (-1, 0, 1) for dr in (-1, 0, 1)
)

Point = Tuple[float, float]
Axial = Tuple[int, int]


def size_from_flat_to_flat_m(flat_to_flat_m: float) -> float:
    """Circumradius (center → vertex) for a regular hex of given flat-to-flat."""
    return float(flat_to_flat_m) / math.sqrt(3.0)


def hex_area_m2(size_m: float) -> float:
    return (3.0 * math.sqrt(3.0) / 2.0) * float(size_m) * float(size_m)


def hex_to_pixel(q: int, r: int, size_m: float) -> Point:
    """Flat-top axial → LAEA metres (origin at hex 0,0)."""
    s = float(size_m)
    x = s * (1.5 * float(q))
    y = s * (math.sqrt(3.0) / 2.0 * float(q) + math.sqrt(3.0) * float(r))
    return x, y


def pixel_to_hex(x: float, y: float, size_m: float) -> Axial:
    s = float(size_m)
    q = (2.0 / 3.0 * float(x)) / s
    r = (-1.0 / 3.0 * float(x) + (math.sqrt(3.0) / 3.0) * float(y)) / s
    return axial_round(q, r)


def axial_round(q: float, r: float) -> Axial:
    x = float(q)
    z = float(r)
    y = -x - z
    rx, ry, rz = round(x), round(y), round(z)
    dx, dy, dz = abs(rx - x), abs(ry - y), abs(rz - z)
    if dx > dy and dx > dz:
        rx = -ry - rz
    elif dy > dz:
        ry = -rx - rz
    else:
        rz = -rx - ry
    return int(rx), int(rz)


def hex_corners(q: int, r: int, size_m: float) -> List[Point]:
    """Flat-top corners; first vertex at due east (0°)."""
    cx, cy = hex_to_pixel(q, r, size_m)
    s = float(size_m)
    out: List[Point] = []
    for i in range(6):
        ang = math.radians(60.0 * float(i))
        out.append((cx + s * math.cos(ang), cy + s * math.sin(ang)))
    return out


def hex_neighbours(q: int, r: int) -> List[Axial]:
    return [(q + dq, r + dr) for dq, dr in HEX_DIRECTIONS]


class LAEA:
    """Spherical Lambert azimuthal equal-area, one global origin."""

    def __init__(
        self,
        lon0_deg: float = 6.0,
        lat0_deg: float = 50.0,
        radius_m: float = EARTH_RADIUS_M,
    ) -> None:
        self.lon0_deg = float(lon0_deg)
        self.lat0_deg = float(lat0_deg)
        self.radius_m = float(radius_m)
        self.lam0 = math.radians(self.lon0_deg)
        self.phi0 = math.radians(self.lat0_deg)
        self.sin_phi0 = math.sin(self.phi0)
        self.cos_phi0 = math.cos(self.phi0)

    def forward(self, lon_deg: float, lat_deg: float) -> Point:
        lam = math.radians(float(lon_deg))
        phi = math.radians(float(lat_deg))
        dlam = lam - self.lam0
        sin_phi = math.sin(phi)
        cos_phi = math.cos(phi)
        cos_dlam = math.cos(dlam)
        denom = 1.0 + self.sin_phi0 * sin_phi + self.cos_phi0 * cos_phi * cos_dlam
        if denom < 1e-12:
            denom = 1e-12
        k = math.sqrt(2.0 / denom)
        x = self.radius_m * k * cos_phi * math.sin(dlam)
        y = self.radius_m * k * (
            self.cos_phi0 * sin_phi - self.sin_phi0 * cos_phi * cos_dlam
        )
        return x, y

    def inverse(self, x: float, y: float) -> Point:
        rho = math.hypot(float(x), float(y))
        if rho < 1e-9:
            return self.lon0_deg, self.lat0_deg
        c = 2.0 * math.asin(max(-1.0, min(1.0, rho / (2.0 * self.radius_m))))
        sin_c = math.sin(c)
        cos_c = math.cos(c)
        phi = math.asin(
            max(
                -1.0,
                min(
                    1.0,
                    cos_c * self.sin_phi0
                    + (float(y) * sin_c * self.cos_phi0) / rho,
                ),
            )
        )
        lam = self.lam0 + math.atan2(
            float(x) * sin_c,
            rho * self.cos_phi0 * cos_c - float(y) * self.sin_phi0 * sin_c,
        )
        lon = math.degrees(lam)
        if lon > 180.0:
            lon -= 360.0
        elif lon < -180.0:
            lon += 360.0
        return lon, math.degrees(phi)


def lattice_origin_shift_m() -> Point:
    """Global lattice origin offset in metres. Default (0,0) = deterministic."""
    if RANDOM_ORIGIN_PER_RUN:
        return (
            random.random() * 50000.0 - 25000.0,
            random.random() * 50000.0 - 25000.0,
        )
    return (0.0, 0.0)


def point_in_ring(x: float, y: float, ring: Sequence[Sequence[float]]) -> bool:
    """Even-odd point-in-polygon. `ring` may repeat the first vertex."""
    n = len(ring)
    if n < 3:
        return False
    inside = False
    j = n - 1
    for i in range(n):
        xi = float(ring[i][0])
        yi = float(ring[i][1])
        xj = float(ring[j][0])
        yj = float(ring[j][1])
        if (yi > y) != (yj > y):
            denom = yj - yi
            if abs(denom) < 1e-18:
                denom = 1e-18
            xinters = (xj - xi) * (y - yi) / denom + xi
            if x < xinters:
                inside = not inside
        j = i
    return inside


def point_in_polygon_with_holes(
    x: float,
    y: float,
    exterior: Sequence[Sequence[float]],
    holes: Sequence[Sequence[Sequence[float]]],
) -> bool:
    if not point_in_ring(x, y, exterior):
        return False
    for hole in holes:
        if point_in_ring(x, y, hole):
            return False
    return True


def ring_bbox(ring: Sequence[Sequence[float]]) -> Tuple[float, float, float, float]:
    xs = [float(p[0]) for p in ring]
    ys = [float(p[1]) for p in ring]
    return min(xs), min(ys), max(xs), max(ys)


def shoelace_area_m2(ring: Sequence[Sequence[float]]) -> float:
    n = len(ring)
    if n < 3:
        return 0.0
    pts = [(float(p[0]), float(p[1])) for p in ring]
    if pts[0][0] == pts[-1][0] and pts[0][1] == pts[-1][1]:
        pts = pts[:-1]
        n = len(pts)
        if n < 3:
            return 0.0
    acc = 0.0
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        acc += x1 * y2 - x2 * y1
    return abs(acc) * 0.5


def directed_hausdorff_m(
    a: Sequence[Point],
    b: Sequence[Point],
) -> float:
    if not a:
        return 0.0
    if not b:
        return float("inf")
    worst = 0.0
    for ax, ay in a:
        best = None  # type: Optional[float]
        for bx, by in b:
            d = math.hypot(ax - bx, ay - by)
            if best is None or d < best:
                best = d
        if best is not None and best > worst:
            worst = best
    return worst


def hausdorff_m(a: Sequence[Point], b: Sequence[Point]) -> float:
    return max(directed_hausdorff_m(a, b), directed_hausdorff_m(b, a))


def hexes_covering_bbox(
    minx: float,
    miny: float,
    maxx: float,
    maxy: float,
    size_m: float,
    pad_hex: int = 2,
) -> List[Axial]:
    """All axial hexes whose centres sit in (or just outside) the bbox."""
    corners = (
        (minx, miny),
        (minx, maxy),
        (maxx, miny),
        (maxx, maxy),
    )
    qs: List[int] = []
    rs: List[int] = []
    for x, y in corners:
        q, r = pixel_to_hex(x, y, size_m)
        qs.append(q)
        rs.append(r)
    pad = int(pad_hex)
    qmin, qmax = min(qs) - pad, max(qs) + pad
    rmin, rmax = min(rs) - pad, max(rs) + pad
    pad_m = float(pad) * size_m * math.sqrt(3.0)
    out: List[Axial] = []
    for q in range(qmin, qmax + 1):
        for r in range(rmin, rmax + 1):
            x, y = hex_to_pixel(q, r, size_m)
            if (minx - pad_m) <= x <= (maxx + pad_m) and (miny - pad_m) <= y <= (
                maxy + pad_m
            ):
                out.append((q, r))
    return out


def subsample_axials(parent_q: int, parent_r: int) -> List[Axial]:
    """5-mi axial cells covering a 15-mi parent (k=3, 9 samples) or centre only."""
    if not SUBSAMPLE_ENABLED:
        return [(parent_q * 3, parent_r * 3)]
    return [
        (parent_q * 3 + dq, parent_r * 3 + dr) for dq, dr in SUBSAMPLE_AXIAL_OFFSETS
    ]


def apply_origin_shift(x: float, y: float, shift: Point) -> Point:
    return (float(x) + float(shift[0]), float(y) + float(shift[1]))


def unique_sorted_pairs(edges: Iterable[Tuple[int, int]]) -> List[List[int]]:
    s = {tuple(sorted((int(a), int(b)))) for a, b in edges if int(a) != int(b)}
    return [[a, b] for a, b in sorted(s)]
