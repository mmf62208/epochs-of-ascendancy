#!/usr/bin/env python3
"""
Split a large world raster (e.g. 8192x4096 clean underlay) into roughly equal
"canonical" chunks close to the Europe grand theater size (5000x2000 or 4096x2048)
for manageable textures, fast loading of "portions", and future multi-theater support.

Usage (after world build):
  python3 scripts/split_world_canonical_chunks.py

Outputs go to assets/maps/world_chunks/ with manifest.
Each chunk gets its own base/elev/rivers/etc if full layers are provided.

This lets us "load on a portion of the map and continue working" while having the
full consistent source.
"""

from __future__ import annotations
import json
from pathlib import Path
from PIL import Image

SCRIPT_DIR = Path(__file__).resolve().parent
BASE_DIR = SCRIPT_DIR.parent
PROJECT_ROOT = BASE_DIR.parent.parent

TARGET_CHUNK_W = 4096
TARGET_CHUNK_H = 2048
OVERLAP = 96  # pixels overlap for potential seam blending later

WORLD_LAYERS_DIR = PROJECT_ROOT / "assets" / "maps" / "layers"
CHUNKS_DIR = PROJECT_ROOT / "assets" / "maps" / "world_chunks"
CHUNKS_DIR.mkdir(parents=True, exist_ok=True)

# The world files produced by build (z3)
WORLD_FILES = {
    "clean_underlay": "world_grand_theater_clean.png",   # preferred for base
    "base": "world_base_stylized.png",
    "rivers": "world_layer_rivers.png",
    "elevation": "world_layer_elevation.png",
    "vegetation": "world_layer_vegetation.png",
}
# Snow mask (winter high elev bits) - support world_ or europe_ or plain for consistent chunking across regions
for cand in ["world_snow_mask.png", "europe_snow_mask.png", "snow_mask.png"]:
    if (WORLD_LAYERS_DIR / cand).exists():
        WORLD_FILES["snow_mask"] = cand
        break

def split_image(img: Image.Image, name: str) -> list[dict]:
    w, h = img.size
    chunks_meta = []
    chunk_id = 0
    y = 0
    while y < h:
        x = 0
        while x < w:
            x0 = max(0, x - OVERLAP // 2)
            y0 = max(0, y - OVERLAP // 2)
            x1 = min(w, x + TARGET_CHUNK_W + OVERLAP // 2)
            y1 = min(h, y + TARGET_CHUNK_H + OVERLAP // 2)

            chunk = img.crop((x0, y0, x1, y1))
            # Normalize snow_mask chunk filenames to consistent *_snow_mask.png (drop europe_/world_ prefix in per-chunk files)
            out_name_base = "snow_mask.png" if "snow_mask" in name.lower() else name
            out_name = f"world_chunk_{chunk_id:02d}_{out_name_base}"
            out_path = CHUNKS_DIR / out_name
            if out_name_base.endswith(".jpg"):
                chunk.convert("RGB").save(out_path, quality=90, optimize=True)
            else:
                chunk.save(out_path, optimize=True)

            chunks_meta.append({
                "id": chunk_id,
                "file": str(out_path.relative_to(PROJECT_ROOT)),
                "pixel_rect": [x0, y0, x1 - x0, y1 - y0],
                "world_pixel_origin": [x0, y0],
            })
            chunk_id += 1
            x += TARGET_CHUNK_W
        y += TARGET_CHUNK_H
    return chunks_meta

def main() -> None:
    print("Splitting world rasters into canonical chunks (~4096x2048 + overlap)...")
    manifest: dict = {"version": 1, "chunk_size": [TARGET_CHUNK_W, TARGET_CHUNK_H], "overlap": OVERLAP, "chunks": {} }

    # Load global rivers for per-chunk slicing (for editor snap in sub-theaters)
    world_rivers_path = PROJECT_ROOT / "data" / "map" / "rivers_world.json"
    world_rivers = []
    if world_rivers_path.exists():
        with open(world_rivers_path) as jf:
            wr = json.load(jf)
            world_rivers = wr.get("rivers", [])
        print(f"  Loaded {len(world_rivers)} global rivers for chunk slicing")

    # Compute canonical chunk rects from a full-size ref (world 8192x4096) so ALL layer types get exactly 4 chunk entries even if a layer src is smaller (e.g. europe snow 5000x2000)
    # Later crops will clamp to the actual src size.
    ref_w, ref_h = 8192, 4096
    canonical_chunks = []
    y = 0
    cid = 0
    while y < ref_h:
        x = 0
        while x < ref_w:
            x0 = max(0, x - OVERLAP // 2)
            y0 = max(0, y - OVERLAP // 2)
            x1 = min(ref_w, x + TARGET_CHUNK_W + OVERLAP // 2)
            y1 = min(ref_h, y + TARGET_CHUNK_H + OVERLAP // 2)
            canonical_chunks.append({"id": cid, "rect": (x0, y0, x1 - x0, y1 - y0)})
            cid += 1
            x += TARGET_CHUNK_W
        y += TARGET_CHUNK_H

    for key, fname in WORLD_FILES.items():
        src = WORLD_LAYERS_DIR / fname
        if not src.exists():
            print(f"  skip {key} (no {src})")
            continue
        img = Image.open(src)
        print(f"  splitting {key} {img.size} ...")
        # Use canonical rects for uniform 4 chunks; crop will be safe for smaller src
        meta = []
        for cinfo in canonical_chunks:
            cid2 = cinfo["id"]
            x0, y0, cw, ch = cinfo["rect"]
            x1, y1 = x0 + cw, y0 + ch
            # clamp crop to actual image; if the src layer is smaller than world (e.g. snow from europe build) and rect is south, produce blank of chunk size so all 4 chunks always have entry
            cx0 = max(0, min(x0, img.width))
            cy0 = max(0, min(y0, img.height))
            cx1 = max(cx0, min(x1, img.width))
            cy1 = max(cy0, min(y1, img.height))
            # Build chunk image always at canonical target size (cw,ch) so underlay + per-chunk layers/snow have matching dims for scale/pos in game.
            # Paste valid sub-crop (if any) at top-left; rest blank. Handles edge/smaller-src layers (snow) without size mismatch.
            blank_mode = img.mode if img.mode in ("L", "LA", "RGBA", "RGB") else "RGBA"
            blank_color = 0 if blank_mode in ("L", "LA") else (0, 0, 0, 0)
            chunk = Image.new(blank_mode, (max(1, cw), max(1, ch)), blank_color)
            if cx1 > cx0 and cy1 > cy0:
                sub = img.crop((cx0, cy0, cx1, cy1))
                chunk.paste(sub, (0, 0))
            out_name_base = "snow_mask.png" if "snow_mask" in fname.lower() else fname
            out_name = f"world_chunk_{cid2:02d}_{out_name_base}"
            out_path = CHUNKS_DIR / out_name
            if out_name_base.endswith(".jpg"):
                chunk.convert("RGB").save(out_path, quality=90, optimize=True)
            else:
                chunk.save(out_path, optimize=True)
            meta.append({
                "id": cid2,
                "file": str(out_path.relative_to(PROJECT_ROOT)),
                "pixel_rect": [x0, y0, cw, ch],  # report the canonical rect
                "world_pixel_origin": [x0, y0],
            })
        manifest["chunks"][key] = meta
        print(f"    -> {len(meta)} chunks for {key}")

    # Slice rivers per chunk (points inside rect) for localized snap data
    if world_rivers:
        chunk_rivers_dir = CHUNKS_DIR
        for cmeta in manifest["chunks"].get("clean_underlay", []):  # use underlay chunks as ref
            cid = cmeta["id"]
            rect = cmeta["pixel_rect"]  # [x0,y0,w,h]
            x0,y0,w,h = rect
            x1, y1 = x0 + w, y0 + h
            chunk_rivs = []
            for r in world_rivers:
                pts = r.get("points", [])
                if pts and any(x0 <= p[0] <= x1 and y0 <= p[1] <= y1 for p in pts):
                    chunk_rivs.append(r)
            if chunk_rivs:
                cr_path = chunk_rivers_dir / f"world_chunk_{cid:02d}_rivers.json"
                with open(cr_path, "w") as jf:
                    json.dump({"version":1, "chunk_id":cid, "rivers": chunk_rivs}, jf, indent=2)
                print(f"    -> {len(chunk_rivs)} rivers for chunk {cid}")
        manifest["has_chunk_rivers"] = True

    manifest_path = CHUNKS_DIR / "world_chunks_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"\nWrote manifest: {manifest_path}")
    print("Chunks ready in assets/maps/world_chunks/")
    print("Europe grand theater work continues unchanged on its 5000x2000 set.")

if __name__ == "__main__":
    main()
