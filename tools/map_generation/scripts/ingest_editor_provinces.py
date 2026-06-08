#!/usr/bin/env python3
"""
Ingests provinces exported from the in-game ProvinceEditor (user://editor_provinces/)
and merges them into a full province layer set for use with the map pipeline or ScenarioLoader.

Usage:
  python3 ingest_editor_provinces.py --editor-dir /path/to/editor_provinces --output-dir data/provinces_my_editor_map --merge-with-existing data/provinces

This is a starter helper as per design doc. Extend with smart attribute assignment, historical variants, etc.
"""

import argparse
import json
import os
import shutil
from pathlib import Path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--editor-dir", default="user://editor_provinces/", help="Directory with editor export (provinces_geometry.json etc.)")
    parser.add_argument("--output-dir", required=True, help="Where to write the merged province dataset")
    parser.add_argument("--merge-with-existing", default=None, help="Optional existing provinces dir to copy base layers from")
    parser.add_argument("--base-name", default="EditorProvince", help="Prefix for new province names")
    args = parser.parse_args()

    editor_dir = Path(args.editor_dir).expanduser()
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    geo_path = editor_dir / "provinces_geometry.json"
    base_path = editor_dir / "provinces_base.json"

    if not geo_path.exists():
        print(f"ERROR: No {geo_path} found. Export from in-game editor first.")
        return

    with open(geo_path) as f:
        geo_data = json.load(f)

    base_data = {}
    if base_path.exists():
        with open(base_path) as f:
            base_data = json.load(f)

    # Simple merge: copy existing if provided
    if args.merge_with_existing:
        existing = Path(args.merge_with_existing)
        for layer in ["provinces_base.json", "province_adjacency.json", "province_terrain_layer.json", "province_economy_layer.json", "province_resources_layer.json", "province_states.json", "strategic_regions.json"]:
            src = existing / layer
            if src.exists():
                shutil.copy(src, out_dir / layer)
                print(f"Copied {layer}")

    # Write/overwrite geometry and base with editor content + merge note
    new_geo = {
        "meta": {
            "version": 1,
            "source": "in_game_editor_ingest",
            "original_meta": geo_data.get("meta", {})
        },
        "provinces": geo_data.get("provinces", [])
    }
    with open(out_dir / "provinces_geometry.json", "w") as f:
        json.dump(new_geo, f, indent=2)

    # Merge or create base
    existing_base_provs = []
    if (out_dir / "provinces_base.json").exists():
        with open(out_dir / "provinces_base.json") as f:
            existing_base = json.load(f)
            existing_base_provs = existing_base.get("provinces", [])

    editor_base_provs = base_data.get("provinces", [])
    # Simple: append editor ones, assume no id conflict or let user resolve
    # Preserve historical_variants if present in editor base or geometry attrs
    for ep in editor_base_provs:
        if "historical_variants" not in ep and "attrs" in ep:  # from editor export sometimes
            ep["historical_variants"] = ep.get("attrs", {}).get("historical_variants", [])
    merged_base = {"provinces": existing_base_provs + editor_base_provs}
    with open(out_dir / "provinces_base.json", "w") as f:
        json.dump(merged_base, f, indent=2)

    # Create stub other layers if missing (in real use, run full assign_attributes.py etc.)
    # For terrain, try basic assignment based on name hints (human override in editor or post-process)
    terrain_stubs = {}
    for p in merged_base["provinces"]:
        pid = str(p["id"])
        name = p.get("name", "").lower()
        terrain = "plains"
        if "mountain" in name or "hill" in name: terrain = "mountains"
        elif "swamp" in name or "marsh" in name: terrain = "swamp"
        elif "desert" in name: terrain = "desert"
        elif "forest" in name: terrain = "forest"
        elif "coast" in name or "port" in name: terrain = "coastal"
        terrain_stubs[pid] = {"terrain": terrain, "movement_cost": 1.0}
    stubs = ["province_city_layer.json", "province_resources_layer.json", "province_economy_layer.json", "province_terrain_layer.json"]
    for stub in stubs:
        if not (out_dir / stub).exists():
            data = {"provinces": {str(p["id"]): {} for p in merged_base["provinces"]}}
            if stub == "province_terrain_layer.json":
                data = {"version": 1, "provinces": terrain_stubs}
            with open(out_dir / stub, "w") as f:
                json.dump(data, f, indent=2)
            print(f"Created stub {stub} (terrain has basic name-based hints - override in editor or pipeline)")

    print(f"\nIngest complete. New dataset in {out_dir}")
    print("Next: Update ScenarioLoader or TestRunner to point to this dir, or run your full map generation pipeline on it.")
    print("Tip: Use the in-game 'Apply Temporary' + test, then export for permanent use.")
    # For river vector: if editor export includes or gen has river polylines (from phase1 gen), load here for snap data in editor.
    # e.g. if (editor_dir / "rivers.json").exists(): load and merge into a river_layer or note for in-game snap.
    # Full sampling: use assign_attributes.py on the output for terrain/pop from base data.

if __name__ == "__main__":
    main()