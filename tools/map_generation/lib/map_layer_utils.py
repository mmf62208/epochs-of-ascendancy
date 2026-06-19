"""Utilities for real-world map layer generation (stdlib + Pillow)."""

from __future__ import annotations

import json
import math
import os
import struct
import urllib.error
import urllib.request
import zipfile
from io import BytesIO
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, List, Optional, Sequence, Tuple

try:
    from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageOps
except ImportError as exc:  # pragma: no cover
    raise SystemExit("Pillow required: pip install pillow") from exc


LonLat = Tuple[float, float]
BBox = Tuple[float, float, float, float]  # lon_min, lat_min, lon_max, lat_max


def load_yaml_simple(path: Path) -> Dict[str, Any]:
    """Minimal YAML reader for our flat config (no PyYAML dependency)."""
    text = path.read_text(encoding="utf-8")
    root: Dict[str, Any] = {}
    stack: List[Tuple[int, Any]] = [(0, root)]
    current_key: Optional[str] = None

    for raw in text.splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(" "))
        content = line.strip()
        while stack and indent < stack[-1][0]:
            stack.pop()
        parent = stack[-1][1]

        if content.endswith(":"):
            key = content[:-1].strip()
            node: Dict[str, Any] = {}
            if isinstance(parent, dict):
                parent[key] = node
            stack.append((indent + 2, node))
            current_key = key
            continue

        if ":" not in content:
            continue
        key, val = content.split(":", 1)
        key = key.strip()
        val = val.strip()
        if val.startswith("{") and val.endswith("}"):
            inner = val[1:-1]
            obj: Dict[str, Any] = {}
            for part in inner.split(","):
                if ":" not in part:
                    continue
                k, v = part.split(":", 1)
                obj[k.strip()] = _parse_scalar(v.strip())
            parent[key] = obj
        else:
            parent[key] = _parse_scalar(val)

    return root


def _parse_scalar(val: str) -> Any:
    if val in ("true", "false"):
        return val == "true"
    if val.startswith("[") and val.endswith("]"):
        inner = val[1:-1].strip()
        if not inner:
            return []
        return [_parse_scalar(x.strip()) for x in inner.split(",")]
    try:
        if "." in val:
            return float(val)
        return int(val)
    except ValueError:
        return val.strip('"').strip("'")


def lonlat_to_pixel(lon: float, lat: float, bbox: BBox, size: Tuple[int, int], use_mercator_y: bool = False) -> Tuple[int, int]:
    lon_min, lat_min, lon_max, lat_max = bbox
    w, h = size
    x = int((lon - lon_min) / (lon_max - lon_min) * (w - 1))
    if use_mercator_y:
        # mercator y for canvas (0 top high lat, h bottom low lat)
        def merc_y(l):
            l = max(min(l, 85.05112878), -85.05112878)
            return (1.0 - math.asinh(math.tan(math.radians(l))) / math.pi) / 2.0
        my_max = merc_y(lat_max)
        my_min = merc_y(lat_min)
        my = merc_y(lat)
        y = int( (my - my_max) / (my_min - my_max + 1e-12) * (h - 1) )
    else:
        y = int((lat_max - lat) / (lat_max - lat_min) * (h - 1))
    return max(0, min(w - 1, x)), max(0, min(h - 1, y))


def pixel_to_lonlat(x: int, y: int, bbox: BBox, size: Tuple[int, int], use_mercator_y: bool = False) -> LonLat:
    lon_min, lat_min, lon_max, lat_max = bbox
    w, h = size
    lon = lon_min + (x / max(1, w - 1)) * (lon_max - lon_min)
    if use_mercator_y:
        def merc_y(l):
            l = max(min(l, 85.05112878), -85.05112878)
            return (1.0 - math.asinh(math.tan(math.radians(l))) / math.pi) / 2.0
        my_max = merc_y(lat_max)
        my_min = merc_y(lat_min)
        my = my_max + (y / max(1, h - 1)) * (my_min - my_max)
        # inverse mercator
        lat = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * my))))
    else:
        lat = lat_max - (y / max(1, h - 1)) * (lat_max - lat_min)
    return lon, lat


def tile_range_for_bbox(bbox: BBox, zoom: int) -> Tuple[range, range]:
    lon_min, lat_min, lon_max, lat_max = bbox
    x0, y0 = lonlat_to_tile(lon_min, lat_max, zoom)
    x1, y1 = lonlat_to_tile(lon_max, lat_min, zoom)
    return range(min(x0, x1), max(x0, x1) + 1), range(min(y0, y1), max(y0, y1) + 1)


def lonlat_to_tile(lon: float, lat: float, zoom: int) -> Tuple[int, int]:
    lat = max(min(lat, 85.05112878), -85.05112878)
    n = 2**zoom
    x = int((lon + 180.0) / 360.0 * n)
    lat_rad = math.radians(lat)
    y = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return max(0, min(n - 1, x)), max(0, min(n - 1, y))


def tile_bounds_lonlat(x: int, y: int, zoom: int) -> BBox:
    n = 2**zoom
    lon_min = x / n * 360.0 - 180.0
    lon_max = (x + 1) / n * 360.0 - 180.0
    lat_max = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / n))))
    lat_min = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (y + 1) / n))))
    return lon_min, lat_min, lon_max, lat_max


def download_bytes(url: str, cache_dir: Path, timeout: int = 60) -> bytes:
    cache_dir.mkdir(parents=True, exist_ok=True)
    safe = url.replace("://", "_").replace("/", "_")
    cache_path = cache_dir / safe
    if cache_path.exists() and cache_path.stat().st_size > 0:
        return cache_path.read_bytes()
    req = urllib.request.Request(url, headers={"User-Agent": "EpochsOfAscendancy-MapGen/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = resp.read()
    except urllib.error.URLError as err:
        raise RuntimeError(f"Download failed: {url} ({err})") from err
    cache_path.write_bytes(data)
    return data


def fetch_tile_mosaic(
    url_pattern: str,
    bbox: BBox,
    zoom: int,
    cache_dir: Path,
    decode: Optional[Callable[[Image.Image], Any]] = None,
    use_mercator_y: bool = False,
) -> Tuple[Image.Image, Optional[List[List[float]]]]:
    xs, ys = tile_range_for_bbox(bbox, zoom)
    tile_size = 256
    cols = len(xs)
    rows = len(ys)
    mosaic = Image.new("RGB", (cols * tile_size, rows * tile_size), (0, 0, 0))
    # Auto-enable grid for known elevation sources (Terrarium) even if decode flag not passed.
    # This makes elevation layer generation robust across call sites.
    is_terrarium = "terrarium" in url_pattern.lower()
    elev_grid: Optional[List[List[float]]] = None
    if decode is not None or is_terrarium:
        elev_grid = [[0.0] * (cols * tile_size) for _ in range(rows * tile_size)]

    for j, y in enumerate(ys):
        for i, x in enumerate(xs):
            url = url_pattern.format(z=zoom, x=x, y=y)
            try:
                raw = download_bytes(url, cache_dir)
                tile = Image.open(BytesIO(raw)).convert("RGB")
            except Exception:
                tile = Image.new("RGB", (tile_size, tile_size), (128, 128, 128))
            ox, oy = i * tile_size, j * tile_size
            mosaic.paste(tile, (ox, oy))
            if elev_grid is not None:
                for ty in range(tile_size):
                    for tx in range(tile_size):
                        r, g, b = tile.getpixel((tx, ty))
                        elev_grid[oy + ty][ox + tx] = terrarium_to_meters(r, g, b)

    # Crop mosaic to exact bbox
    lon_min, lat_min, lon_max, lat_max = bbox
    n = 2**zoom
    # Top-left tile origin
    x0 = xs.start
    y0 = ys.start
    tl_lon, _, _, tl_lat = tile_bounds_lonlat(x0, y0, zoom)
    br_lon, br_lat, _, _ = tile_bounds_lonlat(xs.stop - 1, ys.stop - 1, zoom)

    def lon_to_px(lon: float) -> int:
        return int((lon - tl_lon) / (br_lon - tl_lon + 1e-9) * mosaic.width)

    def lat_to_px(lat: float) -> int:
        if use_mercator_y:
            def merc_y(l):
                l = max(min(l, 85.05112878), -85.05112878)
                return (1.0 - math.asinh(math.tan(math.radians(l))) / math.pi) / 2.0
            my_tl = merc_y(tl_lat)
            my_br = merc_y(br_lat)
            my = merc_y(lat)
            return int( (my - my_tl) / (my_br - my_tl + 1e-9) * mosaic.height )
        return int((tl_lat - lat) / (tl_lat - br_lat + 1e-9) * mosaic.height)

    left = max(0, lon_to_px(lon_min))
    right = min(mosaic.width, lon_to_px(lon_max))
    top = max(0, lat_to_px(lat_max))
    bottom = min(mosaic.height, lat_to_px(lat_min))
    if right <= left or bottom <= top:
        cropped = mosaic
        cropped_elev = elev_grid
    else:
        cropped = mosaic.crop((left, top, right, bottom))
        if elev_grid is not None:
            cropped_elev = [row[left:right] for row in elev_grid[top:bottom]]
        else:
            cropped_elev = None

    # For accurate geo-aligned layers (hillshade, veg) we prefer the full grid + geo params
    # so we can sample directly in the final canvas pixel space using the same lonlat_to_pixel mapping as rivers/coast.
    if elev_grid is not None:
        elev_info = {
            "full_grid": elev_grid,  # full mosaic resolution, not cropped
            "tl_lon": tl_lon,
            "tl_lat": tl_lat,
            "br_lon": br_lon,
            "br_lat": br_lat,
            "mosaic_width": mosaic.width,
            "mosaic_height": mosaic.height,
            "xs_start": xs.start,
            "xs_stop": xs.stop,
            "ys_start": ys.start,
            "ys_stop": ys.stop,
            "zoom": zoom,
        }
        # return the info instead of cropped grid for callers that want geo-accurate
        return cropped, elev_info

    return cropped, cropped_elev


def terrarium_to_meters(r: int, g: int, b: int) -> float:
    return (r * 256 + g + b / 256.0) - 32768.0


def _sample_elev_from_info(lon: float, lat: float, elev_info: Dict[str, Any]) -> float:
    """Sample elevation at exact lon,lat using the full mosaic grid and its geo params.
    Uses exact mercator tile fractional positioning (same as tile placement) for accurate
    lookup in the grid, avoiding linear lat approximation errors over the bbox.
    This guarantees correct high elevations in Scotland, Iceland, Spain etc.
    """
    if not elev_info or "full_grid" not in elev_info:
        return 0.0
    grid = elev_info["full_grid"]
    xs_start = elev_info["xs_start"]
    ys_start = elev_info["ys_start"]
    zoom = elev_info["zoom"]
    mh = len(grid)
    mw = len(grid[0]) if mh > 0 else 0
    if mw < 2 or mh < 2:
        return 0.0
    n = 2 ** zoom
    # fractional tile x (lon linear)
    tile_x = (lon + 180.0) / 360.0 * n
    # fractional tile y (exact mercator)
    lat = max(min(lat, 85.05112878), -85.05112878)
    lat_rad = math.radians(lat)
    tile_y = (1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n
    # local pixel in tile [0, 256)
    local_x = (tile_x - math.floor(tile_x)) * 256
    local_y = (tile_y - math.floor(tile_y)) * 256
    # grid position
    gx = (math.floor(tile_x) - xs_start) * 256 + local_x
    gy = (math.floor(tile_y) - ys_start) * 256 + local_y
    # clamp and bilinear
    x0 = max(0, min(mw - 2, int(gx)))
    y0 = max(0, min(mh - 2, int(gy)))
    fx = max(0.0, min(1.0, gx - x0))
    fy = max(0.0, min(1.0, gy - y0))
    v00 = grid[y0][x0]
    v10 = grid[y0][x0 + 1] if x0 + 1 < mw else grid[y0][x0]
    v01 = grid[y0 + 1][x0] if y0 + 1 < mh else grid[y0][x0]
    v11 = grid[y0 + 1][x0 + 1] if (y0 + 1 < mh and x0 + 1 < mw) else grid[y0][x0]
    return (v00 * (1 - fx) + v10 * fx) * (1 - fy) + (v01 * (1 - fx) + v11 * fx) * fy


def resize_to(img: Image.Image, size: Tuple[int, int]) -> Image.Image:
    return img.resize(size, Image.Resampling.LANCZOS)


def build_hillshade_layer(
    elev: Any,
    size: Tuple[int, int],
    style: Dict[str, Any],
    bbox: Optional[BBox] = None,
    use_mercator_y: bool = False,
) -> Image.Image:
    """Directional shaded relief (classic carto NW sun) + elevation band tints.
    Produces world-class readable terrain relief over the parchment base.

    Supports two modes for registration:
    - Legacy: elev is List[List[float]], size matches grid size (uses internal bilinear).
    - Geo-accurate (recommended for final canvas): elev is elev_info dict from fetch_tile_mosaic,
      bbox must be provided. Samples using exact lon/lat per target pixel so that mountain
      shading aligns perfectly with rivers, coast, and province geometry (which all use the
      same final-size lonlat_to_pixel mapping). This fixes the "mountains in wrong locations" issue.
    """
    w, h = size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    hill_t = float(style.get("hill_threshold_m", 180))
    mount_t = float(style.get("mountain_threshold_m", 750))
    hill_c = tuple(style.get("hill_tint", [155, 148, 135, 155]))
    mount_c = tuple(style.get("mountain_tint", [115, 108, 98, 195]))
    strength = float(style.get("hillshade_strength", 0.9))
    azimuth = math.radians(float(style.get("hillshade_azimuth_deg", 315)))
    altitude = math.radians(float(style.get("hillshade_altitude_deg", 48)))
    zf = float(style.get("z_factor", 2.8))

    is_geo_mode = isinstance(elev, dict) and "full_grid" in elev and bbox is not None

    if is_geo_mode:
        # We don't need eh/ew for sampling; geo sampling is used
        pass
    else:
        eh = len(elev) if isinstance(elev, list) else 0
        ew = len(elev[0]) if isinstance(elev, list) and elev else 0
        if eh < 2 or ew < 2:
            return out

    def sample_elev(px: float, py: float) -> float:
        if is_geo_mode:
            # Will be overridden in the main loop with per-pixel geo sampling for gradients too
            return 0.0
        # legacy path
        eh2 = len(elev)
        ew2 = len(elev[0]) if elev else 0
        sx = px / max(1, w - 1) * (ew2 - 1)
        sy = py / max(1, h - 1) * (eh2 - 1)
        x0 = max(0, min(ew2 - 2, int(sx)))
        y0 = max(0, min(eh2 - 2, int(sy)))
        fx = max(0.0, min(1.0, sx - x0))
        fy = max(0.0, min(1.0, sy - y0))
        v00 = elev[y0][x0]
        v10 = elev[y0][x0 + 1]
        v01 = elev[y0 + 1][x0]
        v11 = elev[y0 + 1][x0 + 1]
        return (v00 * (1 - fx) + v10 * fx) * (1 - fy) + (v01 * (1 - fx) + v11 * fx) * fy

    pixels = out.load()
    for y in range(h):
        for x in range(w):
            if is_geo_mode:
                # exact per-pixel geo sampling for z and gradients -- this is the key fix
                lon = bbox[0] + (x / max(1, w - 1)) * (bbox[2] - bbox[0])
                if use_mercator_y:
                    # canvas y corresponds to mercator; compute the geo lat for this canvas y
                    def merc_y(l):
                        l = max(min(l, 85.05112878), -85.05112878)
                        return (1.0 - math.asinh(math.tan(math.radians(l))) / math.pi) / 2.0
                    my_max = merc_y(bbox[3])
                    my_min = merc_y(bbox[1])
                    my = my_max + (y / max(1, h - 1)) * (my_min - my_max)
                    lat = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * my))))
                else:
                    lat = bbox[3] - (y / max(1, h - 1)) * (bbox[3] - bbox[1])
                z = _sample_elev_from_info(lon, lat, elev)

                # gradients from neighboring final pixels' geo locations
                lon_c, lat_c = lon, lat
                lon_r = bbox[0] + (min(x + 1, w - 1) / max(1, w - 1)) * (bbox[2] - bbox[0])
                lon_l = bbox[0] + (max(x - 1, 0) / max(1, w - 1)) * (bbox[2] - bbox[0])
                if use_mercator_y:
                    my_u = my_max + (min(y + 1, h - 1) / max(1, h - 1)) * (my_min - my_max)
                    my_d = my_max + (max(y - 1, 0) / max(1, h - 1)) * (my_min - my_max)
                    lat_u = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * my_u))))
                    lat_d = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * my_d))))
                else:
                    lat_u = bbox[3] - (min(y + 1, h - 1) / max(1, h - 1)) * (bbox[3] - bbox[1])
                    lat_d = bbox[3] - (max(y - 1, 0) / max(1, h - 1)) * (bbox[3] - bbox[1])
                zx = (_sample_elev_from_info(lon_r, lat_c, elev) - _sample_elev_from_info(lon_l, lat_c, elev)) * zf
                zy = (_sample_elev_from_info(lon_c, lat_u, elev) - _sample_elev_from_info(lon_c, lat_d, elev)) * zf
                zy = -zy  # geographic y correction
            else:
                z = sample_elev(x, y)
                zx = (sample_elev(min(x + 1, w - 1), y) - sample_elev(max(x - 1, 0), y)) * zf
                zy = (sample_elev(x, min(y + 1, h - 1)) - sample_elev(x, max(y - 1, 0))) * zf
                zy = -zy

            slope = math.atan(math.sqrt(zx * zx + zy * zy) * strength)
            aspect = math.atan2(zy, zx)
            cos_i = (math.sin(altitude) * math.cos(slope) +
                     math.cos(altitude) * math.sin(slope) * math.cos(azimuth - aspect - math.pi))
            shade = max(0.35, min(1.15, cos_i))

            if z < 0:
                # Suppress all tint over sea (negative DEM) for clean ocean
                pixels[x, y] = (0, 0, 0, 0)
                continue
            if z >= mount_t:
                base_col = mount_c
                a = int(90 + (shade - 0.6) * 140)
                r = int(base_col[0] * (0.75 + shade * 0.35))
                g = int(base_col[1] * (0.75 + shade * 0.35))
                b = int(base_col[2] * (0.75 + shade * 0.35))
                pixels[x, y] = (r, g, b, min(255, max(40, min(base_col[3], a))))
            elif z >= hill_t:
                base_col = hill_c
                a = int(55 + (shade - 0.55) * 130)
                r = int(base_col[0] * (0.8 + shade * 0.28))
                g = int(base_col[1] * (0.8 + shade * 0.28))
                b = int(base_col[2] * (0.8 + shade * 0.28))
                pixels[x, y] = (r, g, b, min(255, max(25, min(base_col[3], a))))
            else:
                if abs(zx) + abs(zy) > 1.5:
                    a = int(18 * (shade - 0.6))
                    if a > 8:
                        r = int(148 * (0.9 + shade * 0.12))
                        g = int(145 * (0.9 + shade * 0.12))
                        b = int(138 * (0.9 + shade * 0.12))
                        pixels[x, y] = (r, g, b, min(70, max(0, a)))
    return out.filter(ImageFilter.GaussianBlur(radius=0.55))


def build_coast_layer(
    land_mask: Image.Image,
    size: Tuple[int, int],
    style: Dict[str, Any],
) -> Image.Image:
    """Subtle coastline enhancement for map readability.
    Adds a thin, soft definition line along land/ocean boundaries (fjords, islands, intricate coasts pop).
    Blends nicely with parchment style without cluttering the clean default look.
    """
    w, h = size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    coast_c = tuple(style.get("coast_color", [50, 78, 105, 95]))

    # Resize mask and detect soft edges
    mask = land_mask.convert("L").resize(size, Image.Resampling.LANCZOS)
    # FIND_EDGES gives us boundary strength
    edge = mask.filter(ImageFilter.FIND_EDGES)
    # Threshold + feather
    edge = edge.point(lambda p: min(255, int(p * 1.6)) if p > 18 else 0)

    # Color only the edge
    coast_fill = Image.new("RGBA", size, coast_c)
    out = Image.composite(coast_fill, out, edge)

    # Very light outer glow / soft for parchment
    out = out.filter(ImageFilter.GaussianBlur(radius=1.1))
    return out


def mask_layer_to_land(layer: Image.Image, land_mask: Image.Image) -> Image.Image:
    """Mask a RGBA layer (elev or veg tint) to only land areas using the vector-accurate land_mask.
    This prevents green/mountain tint from appearing over ocean and ensures it respects the exact coastline.
    Uses threshold for stricter binary land (avoids partial alpha bleed near coasts).
    """
    if layer.mode != "RGBA":
        layer = layer.convert("RGBA")
    land = land_mask.convert("L")
    if land.size != layer.size:
        land = land.resize(layer.size, Image.Resampling.NEAREST)
    # Stricter binary land mask (>200) to eliminate any coastal/sea bleed in tints
    land = land.point(lambda p: 255 if p > 200 else 0)
    a = layer.getchannel("A")
    new_a = ImageChops.multiply(a, land)
    layer = layer.copy()
    layer.putalpha(new_a)
    return layer


def classify_vegetation(
    elev: List[List[float]],
    bbox: BBox,
    size: Tuple[int, int],
    style: Dict[str, Any],
    use_mercator_y: bool = False,
) -> Image.Image:
    w, h = size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    eh = len(elev)
    ew = len(elev[0]) if elev else 0
    if eh < 2 or ew < 2:
        return out

    forest = tuple(style.get("forest_color", [48, 92, 52, 140]))
    jungle = tuple(style.get("jungle_color", [28, 72, 38, 160]))
    swamp = tuple(style.get("swamp_color", [72, 88, 62, 150]))
    j_lat = float(style.get("jungle_lat_max", 35))
    f_min = float(style.get("forest_lat_min", 35))
    f_max = float(style.get("forest_lat_max", 65))
    swamp_z = float(style.get("swamp_elevation_max_m", 80))
    f_z_min = float(style.get("forest_z_min", 50))

    def sample_elev(px: int, py: int) -> float:
        sx = int(px / max(1, w - 1) * (ew - 1))
        sy = int(py / max(1, h - 1) * (eh - 1))
        return elev[sy][sx]

    pixels = out.load()
    for y in range(h):
        for x in range(w):
            lon, lat = pixel_to_lonlat(x, y, bbox, size, use_mercator_y=use_mercator_y)
            z = sample_elev(x, y)
            if z < swamp_z and abs(lat) < 55:
                pixels[x, y] = swamp
            elif abs(lat) <= j_lat and z < 1200 and z > 0:
                pixels[x, y] = jungle
            elif f_min <= abs(lat) <= f_max and f_z_min < z < 2200:
                pixels[x, y] = forest
    return out.filter(ImageFilter.GaussianBlur(radius=1.2))


def stylize_base(satellite: Image.Image, style: Dict[str, Any], land_mask: Optional[Image.Image] = None) -> Image.Image:
    base = satellite.convert("RGB")
    desat = float(style.get("desaturate", 0.35))
    base = ImageEnhance.Color(base).enhance(1.0 - desat * 0.7)
    base = ImageEnhance.Brightness(base).enhance(float(style.get("land_brightness", 1.05)))
    parchment = tuple(style.get("parchment_tint", [235, 225, 205]))
    tint = Image.new("RGB", base.size, parchment)
    base = ImageChops.blend(base, tint, desat)
    if land_mask is not None:
        ocean = tuple(style.get("ocean_tint", [72, 108, 142]))
        ocean_img = Image.new("RGB", base.size, ocean)
        mask = land_mask.convert("L").resize(base.size, Image.Resampling.LANCZOS)
        base = Image.composite(base, ocean_img, mask)
    return base


def load_geojson_lines(url: str, cache_dir: Path) -> List[Dict[str, Any]]:
    data = json.loads(download_bytes(url, cache_dir).decode("utf-8"))
    features = data.get("features", [])
    return features


def draw_rivers_layer(
    features: Sequence[Dict[str, Any]],
    bbox: BBox,
    size: Tuple[int, int],
    style: Dict[str, Any],
    use_mercator_y: bool = False,
) -> Tuple[Image.Image, List[Dict[str, Any]]]:
    w, h = size
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    color = tuple(style.get("color", [42, 98, 148, 220]))
    width = int(style.get("width_px", 2))
    major_w = int(style.get("major_width_px", 4))
    rank_max = int(style.get("scale_rank_max", 6))
    rivers_json: List[Dict[str, Any]] = []
    rid = 0

    for feat in features:
        geom = feat.get("geometry") or {}
        props = feat.get("properties") or {}
        gtype = geom.get("type")
        coords = geom.get("coordinates")
        if not coords:
            continue
        rank = int(props.get("scalerank", props.get("scalerank_alt", 9)) or 9)
        lw = major_w if rank <= 2 else width if rank <= rank_max else 1
        lines: List[List[LonLat]] = []
        if gtype == "LineString":
            lines = [coords]
        elif gtype == "MultiLineString":
            lines = coords
        for line in lines:
            pts: List[Tuple[int, int]] = []
            world_pts: List[List[float]] = []
            for lon, lat in line:
                if lon < bbox[0] - 2 or lon > bbox[2] + 2 or lat < bbox[1] - 2 or lat > bbox[3] + 2:
                    continue
                px, py = lonlat_to_pixel(lon, lat, bbox, size, use_mercator_y=use_mercator_y)
                pts.append((px, py))
                # Game coords: same pixel space as GRAND_THEATER canvas
                world_pts.append([float(px), float(py)])
            if len(pts) >= 2:
                draw.line(pts, fill=color, width=lw, joint="curve")
                rivers_json.append({
                    "id": rid,
                    "name": props.get("name", ""),
                    "scalerank": rank,
                    "points": world_pts,
                })
                rid += 1
    return img, rivers_json


def draw_lakes_layer(
    features: Sequence[Dict[str, Any]],
    bbox: BBox,
    size: Tuple[int, int],
    style: Dict[str, Any],
    use_mercator_y: bool = False,
) -> Image.Image:
    """Draw filled lakes (polygons from ne_10m_lakes) into RGBA layer using river-like blue.
    Used to add Great Lakes, Caspian, Victoria etc to the 'river layer' visual.
    """
    w, h = size
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    color = tuple(style.get("color", [42, 98, 148, 180]))  # slightly more transparent for large lakes?
    for feat in features:
        geom = feat.get("geometry") or {}
        props = feat.get("properties") or {}
        gtype = geom.get("type")
        coords = geom.get("coordinates")
        if not coords:
            continue
        # Only large lakes? optional filter by scalerank or name, but for now all that intersect bbox
        polys: List = []
        if gtype == "Polygon":
            polys = [coords]
        elif gtype == "MultiPolygon":
            polys = coords
        for poly in polys:
            if not poly:
                continue
            ring = poly[0]  # exterior
            pts = []
            for lon, lat in ring:
                if lon < bbox[0] - 2 or lon > bbox[2] + 2 or lat < bbox[1] - 2 or lat > bbox[3] + 2:
                    continue
                px, py = lonlat_to_pixel(lon, lat, bbox, size, use_mercator_y=use_mercator_y)
                pts.append((px, py))
            if len(pts) >= 3:
                draw.polygon(pts, fill=color)
    return img


def build_land_mask_from_geojson(features: Sequence[Dict[str, Any]], bbox: BBox, size: Tuple[int, int], use_mercator_y: bool = False) -> Image.Image:
    w, h = size
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    for feat in features:
        geom = feat.get("geometry") or {}
        gtype = geom.get("type")
        coords = geom.get("coordinates")
        if not coords:
            continue
        polys: List = []
        if gtype == "Polygon":
            polys = [coords]
        elif gtype == "MultiPolygon":
            polys = coords
        for poly in polys:
            if not poly:
                continue
            ring = poly[0]
            pts = [lonlat_to_pixel(lon, lat, bbox, size, use_mercator_y=use_mercator_y) for lon, lat in ring]
            if len(pts) >= 3:
                draw.polygon(pts, fill=255)
    return mask


def composite_layers(base: Image.Image, *layers: Image.Image) -> Image.Image:
    """Alpha composite any number of layers on top of base (order: first arg under, later on top)."""
    out = base.convert("RGBA")
    for layer in layers:
        if layer is not None:
            out = Image.alpha_composite(out, layer.convert("RGBA") if layer.mode != "RGBA" else layer)
    return out
