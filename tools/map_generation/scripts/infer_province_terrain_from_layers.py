#!/usr/bin/env python3
"""
Infer province terrain tags, movement costs, etc. from the real-world map layers (elev/veg).
Samples the final geo-accurate layers at province points/centroids.
Outputs/ merges into province_terrain_layer.json for use in ScenarioLoader / gameplay.

Run after Europe (or world chunk) build:
  python3 scripts/infer_province_terrain_from_layers.py --data-dir provinces_full_europe

This integrates the NASA/Natural Earth data into province gameplay (terrain, logistics, combat).
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
from PIL import Image
from typing import Any, Dict, List, Tuple

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent.parent  # scripts -> map_generation -> tools -> project root

DEFAULT_BBOX = (-25.0, 28.0, 45.0, 72.0)
DEFAULT_SIZE = (5000, 2000)

def lonlat_to_pixel(lon: float, lat: float, bbox: Tuple[float,...], size: Tuple[int,int]) -> Tuple[int,int]:
    lon_min, lat_min, lon_max, lat_max = bbox
    w, h = size
    x = int((lon - lon_min) / (lon_max - lon_min) * (w - 1))
    y = int((lat_max - lat) / (lat_max - lat_min) * (h - 1))
    return max(0, min(w-1, x)), max(0, min(h-1, y))

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", default="provinces_full_europe", help="e.g. provinces_full_europe or provinces_phase1_test")
    parser.add_argument("--layers-dir", default="assets/maps/layers", help="where the final layers live (or per-chunk dir)")
    parser.add_argument("--shade-path", default="", help="override path to elevation_shade_debug.png (for chunked or custom)")
    parser.add_argument("--snow-mask-path", default="", help="override path to snow_mask.png (for chunked high-elev inference)")
    parser.add_argument("--debug", action="store_true", help="print samples")
    args = parser.parse_args()

    data_dir = PROJECT_ROOT / "data" / args.data_dir
    layers_dir = PROJECT_ROOT / args.layers_dir

    geo_path = data_dir / "provinces_geometry.json"
    terrain_path = data_dir / "province_terrain_layer.json"

    if not geo_path.exists():
        print(f"No geometry at {geo_path}")
        return

    with open(geo_path) as j: geo = json.load(j)
    provs = geo.get("provinces", {})
    if isinstance(provs, list):
        provs = {str(p.get("id", i)): p for i, p in enumerate(provs)}

    # Load final layers for sampling (use debug shade for height proxy, veg for biome)
    # Support europe_ or world_ or generic names (for chunk/world inference later). Overrides via --shade-path/--snow-mask-path for per-chunk.
    def _find_layer(basename: str) -> Path:
        for prefix in ("europe_", "world_", ""):
            p = layers_dir / f"{prefix}{basename}"
            if p.exists():
                return p
        return layers_dir / basename  # may not exist
    if args.shade_path:
        shade_path = Path(args.shade_path)
    else:
        shade_path = _find_layer("elevation_shade_debug.png")
        if not shade_path.exists():
            shade_path = layers_dir / "europe_elevation_shade_debug.png"
    if args.snow_mask_path:
        snow_mask_path = Path(args.snow_mask_path)
    else:
        snow_mask_path = _find_layer("snow_mask.png")
    veg_path = _find_layer("layer_vegetation.png")
    if not shade_path.exists():
        print("No debug shade; run build first")
        return
    shade = Image.open(shade_path).convert("L")
    veg_im = Image.open(veg_path).convert("RGBA") if veg_path.exists() else None
    snow_im = Image.open(snow_mask_path).convert("L") if snow_mask_path.exists() else None
    print(f"Using layers: shade={shade_path.name} veg={veg_path.name if veg_im else None} snow={snow_mask_path.name if snow_im else None}")

    bbox = DEFAULT_BBOX
    size = DEFAULT_SIZE

    new_terrain: Dict[str, Dict] = {}
    samples = 0
    for pid, pdata in provs.items():
        pts = pdata.get("points", []) if isinstance(pdata, dict) else []
        if not pts:
            continue
        # Sample avg over all points (better for poly coverage) + label if present
        pxs = [int(p[0]) for p in pts]
        pys = [int(p[1]) for p in pts]
        if "label_anchor" in pdata:
            pxs.append(int(pdata["label_anchor"][0]))
            pys.append(int(pdata["label_anchor"][1]))
        pxs = [max(0, min(size[0]-1, p)) for p in pxs]
        pys = [max(0, min(size[1]-1, p)) for p in pys]
        h = sum(shade.getpixel((pxs[i], pys[i])) for i in range(len(pxs))) / (len(pxs) * 255.0)
        v_a = 0.0
        if veg_im:
            v_a = sum(veg_im.getpixel((pxs[i], pys[i]))[3] for i in range(len(pxs))) / (len(pxs) * 255.0)
        s = 0.0
        if snow_im:
            s = sum(snow_im.getpixel((pxs[i], pys[i])) for i in range(len(pxs))) / (len(pxs) * 255.0)

        # Infer (tuned for current layers, with snow on high elev)
        terrain = "plains"
        move_mod = 1.0
        if h > 0.55 or s > 0.3:  # snow mask indicates high elev potential
            terrain = "mountains"
            move_mod = 2.5
            if s > 0.5:
                terrain = "snow_capped"  # or keep mountains, add tag
                move_mod = 3.0
        elif h > 0.25:
            terrain = "hills"
            move_mod = 1.6
        if v_a > 0.12 and terrain != "mountains" and "snow" not in terrain:
            terrain = "forest" if terrain == "plains" else terrain
            move_mod *= 1.25

        new_terrain[str(pid)] = {
            "terrain": terrain,
            "movement_cost": round(move_mod, 2),
            "height_proxy": round(h, 3),
            "veg_strength": round(v_a, 3),
            "snow_potential": round(s, 3),
            "source": "real_layers_inference"
        }
        samples += 1
        if args.debug and samples < 6:
            print(f"  pid {pid}: h={h:.2f} v={v_a:.2f} s={s:.2f} -> {terrain} move={move_mod}")

    # Merge or write - robust: always operate on the provinces sub-dict to avoid wrapper/key pollution (prior runs mixed flat + wrapped + cross-dir pids like 90xx)
    existing_provs: dict = {}
    if terrain_path.exists():
        try:
            ex = json.load(open(terrain_path))
            tl = ex.get("province_terrain_layer", ex) if isinstance(ex, dict) else {}
            if isinstance(tl, dict):
                if "provinces" in tl and isinstance(tl["provinces"], dict):
                    existing_provs = tl["provinces"]
                else:
                    # legacy flat pid->data at this level
                    existing_provs = {str(k): v for k, v in tl.items() if isinstance(v, dict) and "terrain" in v}
        except Exception:
            existing_provs = {}
    # Start fresh from geometry pids for this data-dir (prevents stale cross-dir pollution); carry prior matching pids if any
    merged_provs = dict(existing_provs)
    merged_provs.update(new_terrain)
    # Only keep pids that look like current set (or all if small); for clean europe run this will drop 90xx world-ish ids
    # For safety, keep only pids present in the just-loaded geom for this run
    current_pids = set(new_terrain.keys())
    if len(current_pids) > 10:
        # trim to only pids we have geom/inferred for this dir (drop orphans from prior bad merges)
        merged_provs = {k: v for k, v in merged_provs.items() if k in current_pids}
    else:
        merged_provs = dict(new_terrain)  # full fresh if tiny
    out_layer = {"version": 1, "provinces": merged_provs}
    out = {"version": 1, "province_terrain_layer": out_layer, "source": "real_layers_inference", "count": len(merged_provs)}
    with open(terrain_path, "w") as j:
        json.dump(out, j, indent=2)
    print(f"Inferred terrain for {len(new_terrain)} provinces (merged clean) -> {terrain_path}")
    print("Sample terrains:", list(new_terrain.values())[:3])

if __name__ == "__main__":
    main()
