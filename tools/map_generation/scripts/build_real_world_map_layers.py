#!/usr/bin/env python3
"""
Build real-world map layers for Epochs of Ascendancy.

Sources (free / NASA / public domain):
  - NASA SRTM-derived Terrarium elevation tiles
  - NASA VIIRS Blue Marble shaded relief (satellite base)
  - Natural Earth rivers + land (GeoJSON)

Outputs (stylized for grand-strategy readability):
  assets/maps/layers/europe_base_stylized.png
  assets/maps/layers/europe_layer_rivers.png
  assets/maps/layers/europe_layer_elevation.png
  assets/maps/layers/europe_layer_vegetation.png
  assets/maps/layers/europe_grand_theater_composite.png
  data/map/rivers.json
  data/map/layer_metadata.json

Usage:
  cd tools/map_generation
  python3 scripts/build_real_world_map_layers.py
  python3 scripts/build_real_world_map_layers.py --region world_full --zoom 3
  python3 scripts/split_world_canonical_chunks.py   # produces manageable ~4096x2048 (overlapped) chunks + manifest for portion loading
  python3 scripts/build_real_world_map_layers.py --skip-download  # use cache only
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image, ImageFilter  # for snow mask generation directly here

SCRIPT_DIR = Path(__file__).resolve().parent
BASE_DIR = SCRIPT_DIR.parent
PROJECT_ROOT = BASE_DIR.parent.parent
sys.path.insert(0, str(BASE_DIR))

from lib import map_layer_utils as mlu  # noqa: E402

DEFAULT_REGIONS = {
    "europe_grand_theater": {
        "lon_min": -25.0,
        "lon_max": 45.0,
        "lat_min": 28.0,
        "lat_max": 72.0,
        "width": 5000,
        "height": 2000,
    },
    "world_full": {
        "lon_min": -180.0,
        "lon_max": 180.0,
        "lat_min": -56.0,
        "lat_max": 83.0,
        "width": 8192,
        "height": 4096,
    },
}


def load_config() -> dict:
    cfg_path = BASE_DIR / "config" / "world_map_layers.yaml"
    if cfg_path.exists():
        try:
            return mlu.load_yaml_simple(cfg_path)
        except Exception as err:
            print(f"Warning: could not parse YAML config ({err}); using defaults.")
    return {
        "default_region": "europe_grand_theater",
        "regions": DEFAULT_REGIONS,
        "data_sources": {
            "elevation": {
                "url_pattern": "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png",
            },
            "satellite": {
                "url_pattern": "https://map1.vis.earthdata.nasa.gov/wmts-webmerc/VIIRS_Blue_Marble_Shaded_Relief_Bathymetry/default/GoogleMapsCompatible_Level9/{z}/{y}/{x}.jpg",
            },
            "rivers": {
                "geojson_url": "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_rivers_lake_centerlines.geojson",
            },
            "land_mask": {
                "geojson_url": "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_land.geojson",
            },
        },
        "styling": {
            "base": {"desaturate": 0.55, "parchment_tint": [235, 225, 205], "ocean_tint": [72, 108, 142]},
            "rivers": {"color": [42, 98, 148, 220], "width_px": 2, "major_width_px": 4},
            "elevation": {"hill_threshold_m": 50, "mountain_threshold_m": 400, "hillshade_strength": 1.1, "hill_tint": [155, 148, 135, 210], "mountain_tint": [115, 108, 98, 240], "hillshade_azimuth_deg": 315, "hillshade_altitude_deg": 48, "z_factor": 2.8},
            "vegetation": {"forest_color": [105, 138, 100, 55], "jungle_color": [70, 105, 65, 55], "swamp_color": [95, 115, 85, 45], "forest_z_min": 20},
            "coast": {"coast_color": [50, 78, 105, 95]},
        },
        "output": {
            "assets_dir": "assets/maps/layers",
            "data_dir": "data/map",
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Build NASA/Natural Earth map layers")
    parser.add_argument("--region", default=None, help="europe_grand_theater | world_full")
    parser.add_argument("--zoom", type=int, default=None, help="WebMercator tile zoom (auto if omitted)")
    parser.add_argument("--skip-download", action="store_true", help="Use cached tiles only")
    parser.add_argument("--dry-run", action="store_true", help="Print plan only")
    parser.add_argument("--only-snow", action="store_true", help="Fast path: only generate *snow_mask* (uses elev tiles + lat bias for high-elev white bits; skips base/rivers/hillshade/veg/coast. Perfect for quick world snow on cached tiles, then re-split chunks.")
    parser.add_argument("--variants", action="store_true", help="Stub: generate extra variant layers (bomb damage, era/culture footprints) - future work, prints plan for now.")
    args = parser.parse_args()

    cfg = load_config()
    region_name = args.region or cfg.get("default_region", "europe_grand_theater")
    regions = cfg.get("regions", DEFAULT_REGIONS)
    if region_name not in regions:
        print(f"Unknown region: {region_name}")
        return 1
    region = regions[region_name]
    bbox = (region["lon_min"], region["lat_min"], region["lon_max"], region["lat_max"])
    size = (int(region["width"]), int(region["height"]))

    zoom = args.zoom
    if zoom is None:
        zoom = 6 if region_name == "europe_grand_theater" else 3  # z=6 for Europe gives ~2x better DEM detail to capture peaks in Scotland, Iceland, Spain etc.

    out_cfg = cfg.get("output", {})
    assets_dir = PROJECT_ROOT / out_cfg.get("assets_dir", "assets/maps/layers")
    data_dir = PROJECT_ROOT / out_cfg.get("data_dir", "data/map")
    cache_dir = BASE_DIR / "data" / "cache" / "map_tiles"

    is_world = region_name == "world_full"
    prefix = "europe" if "europe" in region_name else "world"
    # For data/ we keep europe_grand_theater as the active "rivers.json" + metadata for current scenarios.
    # World (and future regions) get suffixed files so we don't clobber the working Europe set.
    if prefix == "europe":
        rivers_json_path = data_dir / "rivers.json"
        meta_path = data_dir / "layer_metadata.json"
    else:
        rivers_json_path = data_dir / f"rivers_{prefix}.json"
        meta_path = data_dir / f"layer_metadata_{prefix}.json"

    paths = {
        "base": assets_dir / f"{prefix}_base_stylized.png",
        "rivers": assets_dir / f"{prefix}_layer_rivers.png",
        "elevation": assets_dir / f"{prefix}_layer_elevation.png",
        "vegetation": assets_dir / f"{prefix}_layer_vegetation.png",
        "composite": assets_dir / f"{prefix}_grand_theater_composite.png",
        "rivers_json": rivers_json_path,
        "metadata": meta_path,
    }

    print(f"=== Real-World Map Layer Build: {region_name} ===")
    print(f"BBox: lon {bbox[0]}..{bbox[2]}, lat {bbox[1]}..{bbox[3]}")
    print(f"Output: {size[0]}×{size[1]} px @ zoom {zoom}")
    print(f"Assets → {assets_dir}")

    if args.dry_run:
        for k, p in paths.items():
            print(f"  {k}: {p}")
        return 0

    sources = cfg.get("data_sources", {})
    styling = cfg.get("styling", {})

    elev_url = sources.get("elevation", {}).get("url_pattern", "")
    sat_url = sources.get("satellite", {}).get("url_pattern", "")
    rivers_url = sources.get("rivers", {}).get("geojson_url", "")
    land_url = sources.get("land_mask", {}).get("geojson_url", "")
    lakes_url = sources.get("lakes", {}).get("geojson_url", "")

    is_world = region_name == "world_full"
    print("\n[1/4] Fetching NASA elevation (Terrarium / SRTM-derived)...")
    # Pass a truthy decode flag so fetch_tile_mosaic populates the elev_grid using terrarium decode.
    # (The decode param currently acts as a "build grid" switch; terrarium logic is inlined.)
    _, elev_grid = mlu.fetch_tile_mosaic(elev_url, bbox, zoom, cache_dir, decode=True, use_mercator_y=is_world)
    if isinstance(elev_grid, dict):
        # Debug: sample real DEM z at known high points in problem areas (Scotland, Iceland, Spain etc had low/zero tint)
        test_points = [
            ("Scotland BenNevis approx", -5.0, 56.8),
            ("Iceland highland", -18.0, 65.0),
            ("Pyrenees high", 0.0, 42.7),
            ("Alps high", 10.0, 46.5),
            ("Norway high", 7.0, 62.0),
        ]
        print("  DEM sample z at key points (to diagnose missing mountains):")
        for name, lon, lat in test_points:
            z = mlu._sample_elev_from_info(lon, lat, elev_grid)
            print(f"    {name} ({lon},{lat}): {z:.0f} m")

    if args.variants:
        print("[VARIANTS STUB] Would generate bomb/era/culture footprint masks on raster using elev/rivers/land as guides (e.g. damage on high infra, culture tints near cities). See docs for plan. Skipping for now.")
        # Future: composite extra RGBA layers, save as europe_layer_variants_*.png etc.
    if args.only_snow:
        print("[ONLY-SNOW] Skipping base/satellite/rivers/hillshade/veg/coast for fast snow_mask gen on cached elev.")
        # Build minimal land_mask for masking snow
        land_features = mlu.load_geojson_lines(land_url, cache_dir)
        land_mask = mlu.build_land_mask_from_geojson(land_features, bbox, size, use_mercator_y=is_world)
        # Snow mask block (copied/adapted from main path for --only-snow)
        snow_mask = Image.new("L", size, 0)
        egrid = []
        if isinstance(elev_grid, dict):
            egrid = elev_grid.get("full_grid", [])
        elif elev_grid:
            egrid = elev_grid
        if isinstance(elev_grid, dict) or egrid:
            snow_pixels = snow_mask.load()
            for y in range(size[1]):
                for x in range(size[0]):
                    lon, lat = mlu.pixel_to_lonlat(x, y, bbox, size, use_mercator_y=is_world)
                    z = mlu._sample_elev_from_info(lon, lat, elev_grid if isinstance(elev_grid, dict) else {"full_grid": egrid, "xs_start":0,"ys_start":0,"zoom":zoom,"mosaic_width":len(egrid[0]) if egrid else 1,"mosaic_height":len(egrid) if egrid else 1})
                    base_thresh = 2900
                    lat_factor = max(0, (lat - 45) / 20.0)
                    snow_thresh = base_thresh - lat_factor * 300
                    if lat >= 72.0:
                        snow_thresh = 180.0
                    elif lat >= 62.0:
                        snow_thresh = min(snow_thresh, 900.0 - (lat - 62.0) * 55.0)
                    if z > snow_thresh:
                        intensity = min(255, int( (z - snow_thresh) * 1.1 ))
                        if z > 3200:
                            intensity = min(255, intensity + 70)
                        if lat >= 66 and z > 1400:
                            intensity = min(255, intensity + 90)
                        snow_pixels[x, y] = intensity
            snow_mask = snow_mask.filter(ImageFilter.GaussianBlur(radius=0.5))
        snow_mask = mlu.mask_layer_to_land(snow_mask.convert("RGBA"), land_mask).convert("L")
        snow_mask_path = assets_dir / f"{prefix}_snow_mask.png"
        snow_mask.save(snow_mask_path, optimize=True)
        print(f"   [ONLY-SNOW] Snow mask (white on high elevations for winter layer): {snow_mask_path}")
        # Minimal metadata update
        meta_path = data_dir / "layer_metadata.json"
        try:
            meta = json.loads(meta_path.read_text()) if meta_path.exists() else {}
        except:
            meta = {}
        meta.update({
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "region": region_name,
            "bbox_lonlat": list(bbox),
            "canvas_pixels": list(size),
            "tile_zoom": zoom,
            "layers": meta.get("layers", {}) | {"snow_mask": str((assets_dir / f"{prefix}_snow_mask.png").relative_to(PROJECT_ROOT))},
            "note": "Generated with --only-snow (fast world high-elev snow bits from cached elev)"
        })
        meta_path.write_text(json.dumps(meta, indent=2), encoding="utf-8")
        print("ONLY-SNOW complete (ready for re-split_world_canonical_chunks.py to update world chunks with global snow).")
        return 0

    print("[2/4] Fetching NASA Blue Marble satellite base...")
    satellite, _ = mlu.fetch_tile_mosaic(sat_url, bbox, zoom, cache_dir, use_mercator_y=is_world)

    print("[3/4] Loading Natural Earth rivers + land...")
    river_features = mlu.load_geojson_lines(rivers_url, cache_dir)
    land_features = mlu.load_geojson_lines(land_url, cache_dir)

    print("[4/4] Resizing + building layers...")
    satellite_rs = mlu.resize_to(satellite, size)
    land_mask = mlu.build_land_mask_from_geojson(land_features, bbox, size, use_mercator_y=is_world)
    base = mlu.stylize_base(satellite_rs, styling.get("base", {}), land_mask)

    rivers_layer, rivers_json = mlu.draw_rivers_layer(
        river_features, bbox, size, styling.get("rivers", {}), use_mercator_y=is_world,
    )
    # Add lakes (Great Lakes, etc) to the river layer visual (filled blue areas + centerlines from rivers geo)
    if lakes_url:
        print("  Loading lakes for river layer (Great Lakes, large inland seas...)")
        lakes_features = mlu.load_geojson_lines(lakes_url, cache_dir)
        lakes_layer = mlu.draw_lakes_layer(lakes_features, bbox, size, styling.get("rivers", {}), use_mercator_y=is_world)
        # Lakes fills under the river lines
        rivers_layer = Image.alpha_composite(lakes_layer, rivers_layer)
    # Geo-accurate generation directly at final target size using the elev_info (full grid + geo params)
    # and the bbox. This samples per final pixel using the exact same lon/lat mapping as rivers,
    # coast, and province geometry. Guarantees mountain/hill shading is in the correct locations
    # relative to the map canvas and vectors (the root cause of previous misalignment).
    elev_layer = mlu.build_hillshade_layer(elev_grid or [], size, styling.get("elevation", {}), bbox=bbox, use_mercator_y=is_world)
    veg_grid = elev_grid.get("full_grid", elev_grid) if isinstance(elev_grid, dict) else (elev_grid or [])
    veg_layer = mlu.classify_vegetation(veg_grid, bbox, size, styling.get("vegetation", {}), use_mercator_y=is_world)

    # Mask elev and veg tints to land only using the vector-accurate land_mask.
    # This ensures green overlay and mountain tint respect the exact coastline (no bleed over ocean or outlines)
    # and rivers (where they cross land). Critical for clean look.
    elev_layer = mlu.mask_layer_to_land(elev_layer, land_mask)
    veg_layer = mlu.mask_layer_to_land(veg_layer, land_mask)

    # Bake subtle "winter mix" white bits into the elevation layer itself using the snow mask (few bits on highest for base map look, even without dynamic snow)
    # The dynamic snow layer will add more when active.
    if region_name == "europe_grand_theater" and (assets_dir / "europe_snow_mask.png").exists():
        sm = Image.open(assets_dir / "europe_snow_mask.png").convert("L")
        white = Image.new("RGBA", size, (255,255,255,0))
        white.putalpha(sm.point(lambda p: int(p * 0.25)))  # subtle few bits of white on highs for base winter mix
        elev_layer = Image.alpha_composite(elev_layer, white)
        elev_layer = mlu.mask_layer_to_land(elev_layer, land_mask)  # re-mask
        print("   Baked subtle snow white bits into elevation layer for winter mix base")

    # Debug: save masked grayscale of final hillshade for clean QA (no sea tint)
    if region_name == "europe_grand_theater":
        debug_elev = elev_layer.convert("L")
        debug_path = assets_dir / "europe_elevation_shade_debug.png"
        debug_elev.save(debug_path, optimize=True)
        print(f"   QA debug (final geo-accurate hillshade, land-masked): {debug_path}")

    # Snow mask for winter mix layer: bits of white on highest elevations (DEM driven, for snow overlay to use)
    # Uses elev_grid z + northern bias (higher lat, lower thresh for snow on highs like Alps, Norway, Scotland, Iceland)
    # This feeds the "winter mix layer snow thing" to add white specks to highest areas dynamically.
    snow_mask = Image.new("L", size, 0)
    egrid = []
    if isinstance(elev_grid, dict):
        egrid = elev_grid.get("full_grid", [])
    elif elev_grid:
        egrid = elev_grid
    if isinstance(elev_grid, dict) or egrid:
        snow_pixels = snow_mask.load()
        for y in range(size[1]):
            for x in range(size[0]):
                lon, lat = mlu.pixel_to_lonlat(x, y, bbox, size)
                z = mlu._sample_elev_from_info(lon, lat, elev_grid if isinstance(elev_grid, dict) else {"full_grid": egrid, "xs_start":0,"ys_start":0,"zoom":zoom,"mosaic_width":len(egrid[0]) if egrid else 1,"mosaic_height":len(egrid) if egrid else 1})  # fallback
                # Persistent peak / permafrost / polar ice cap mask (S key layer — not seasonal weather).
                base_thresh = 2900
                lat_factor = max(0, (lat - 45) / 20.0)  # 0 at 45, higher north
                snow_thresh = base_thresh - lat_factor * 300
                if lat >= 72.0:
                    snow_thresh = 180.0
                elif lat >= 62.0:
                    snow_thresh = min(snow_thresh, 900.0 - (lat - 62.0) * 55.0)
                if z > snow_thresh:
                    intensity = min(255, int( (z - snow_thresh) * 1.1 ))
                    if z > 3200:
                        intensity = min(255, intensity + 70)
                    if lat >= 66 and z > 1400:
                        intensity = min(255, intensity + 90)
                    snow_pixels[x, y] = intensity
        # Soft for natural bits
        snow_mask = snow_mask.filter(ImageFilter.GaussianBlur(radius=0.5))
    # Mask snow to land too (no white in sea)
    snow_mask = mlu.mask_layer_to_land(snow_mask.convert("RGBA"), land_mask).convert("L")
    snow_mask_path = assets_dir / f"{prefix}_snow_mask.png"
    snow_mask.save(snow_mask_path, optimize=True)
    print(f"   Snow mask (white on high elevations for winter layer): {snow_mask_path}")
    # Also save to metadata
    if "layers" not in locals():
        pass
    # Update metadata later if needed
    coast_layer = mlu.build_coast_layer(land_mask, size, styling.get("coast", {}))

    # Clean default underlay (parchment + coast definition + directional hills + rivers).
    # Vegetation deliberately excluded or extremely faint here for the "clean world-class parchment" default.
    # The separate veg layer remains available for the V toggle (very subtle pastel when enabled).
    clean_composite = mlu.composite_layers(base, coast_layer, elev_layer, rivers_layer)
    full_composite = mlu.composite_layers(base, coast_layer, elev_layer, veg_layer, rivers_layer)

    print("Writing outputs...")
    assets_dir.mkdir(parents=True, exist_ok=True)
    data_dir.mkdir(parents=True, exist_ok=True)
    base.save(paths["base"], optimize=True)
    rivers_layer.save(paths["rivers"], optimize=True)
    elev_layer.save(paths["elevation"], optimize=True)
    veg_layer.save(paths["vegetation"], optimize=True)
    # "composite" in layers/ is the full (with subtle veg) for reference / max-detail use
    full_composite.save(paths["composite"], optimize=True)
    # Also write a clean version explicitly (same content as default underlay)
    clean_path = assets_dir / f"{prefix}_grand_theater_clean.png"
    clean_composite.save(clean_path, optimize=True)

    rivers_doc = {
        "version": 1,
        "region": region_name,
        "bbox_lonlat": list(bbox),
        "canvas_size": list(size),
        "game_bounds": region.get("game_bounds", {"x": 0, "y": 0, "w": size[0], "h": size[1]}),
        "rivers": rivers_json,
    }
    paths["rivers_json"].write_text(json.dumps(rivers_doc, indent=2), encoding="utf-8")

    metadata = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "region": region_name,
        "bbox_lonlat": list(bbox),
        "canvas_pixels": list(size),
        "game_bounds": region.get("game_bounds", {"x": 0, "y": 0, "w": size[0], "h": size[1]}),
        "tile_zoom": zoom,
        "layers": {
            "base": str(paths["base"].relative_to(PROJECT_ROOT)),
            "rivers": str(paths["rivers"].relative_to(PROJECT_ROOT)),
            "elevation": str(paths["elevation"].relative_to(PROJECT_ROOT)),
            "vegetation": str(paths["vegetation"].relative_to(PROJECT_ROOT)),
            "composite": str(paths["composite"].relative_to(PROJECT_ROOT)),
            "snow_mask": str((assets_dir / f"{prefix}_snow_mask.png").relative_to(PROJECT_ROOT)),  # for winter mix layer to add white on high elevations (DEM high z + lat)
        },
        "data_sources": {
            "elevation": sources.get("elevation", {}).get("name", "NASA SRTM Terrarium"),
            "satellite": sources.get("satellite", {}).get("name", "NASA Blue Marble"),
            "rivers": sources.get("rivers", {}).get("name", "Natural Earth"),
        },
        "attribution": [
            "NASA SRTM elevation (via Terrarium tiles)",
            "NASA VIIRS Blue Marble",
            "Natural Earth physical vectors",
        ],
        "notes": "Stylized for grand-strategy readability (clean default: parchment + directional hills + rivers + subtle coast). Vegetation is a separate very faint togglable layer (V). See TerrainLayerStack and docs/REAL_WORLD_MAP_LAYERS.md.",
    }
    paths["metadata"].write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    # Update the in-game grand theater underlay from the *clean* composite (rivers + hills + coast on parchment).
    # This keeps the default map beautiful, readable, and "world class" without vegetation clutter.
    # Veg layer (V key) provides the optional faint biome tint on top via TerrainLayerStack.
    if region_name == "europe_grand_theater":
        theater_path = PROJECT_ROOT / "assets" / "maps" / "europe_grand_theater_ultra_high.jpg"
        clean_composite.convert("RGB").save(theater_path, quality=92, optimize=True)
        print(f"Updated grand theater underlay (clean: base+coast+hills+rivers): {theater_path}")
    elif region_name == "world_full":
        world_underlay = PROJECT_ROOT / "assets" / "maps" / "world_grand_theater_ultra_high.jpg"
        clean_composite.convert("RGB").save(world_underlay, quality=90, optimize=True)
        print(f"Updated world underlay (clean): {world_underlay}")

    print("\n✅ Map layers built successfully.")
    print(f"   Full composite (layers/): {paths['composite']}")
    print(f"   Clean underlay (jpg for game): rivers + directional hills + coast on parchment (veg separate + faint)")
    print(f"   Rivers JSON: {paths['rivers_json']} ({len(rivers_json)} polylines)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
