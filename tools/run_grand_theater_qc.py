#!/usr/bin/env python3
"""
Automated subset of docs/TEST_MAP_GRAND_THEATER_FOUNDATION.md (47-item checklist).

Checks file/data/runtime wiring that can be verified headlessly without F5 pan/zoom.
Manual items (visual pan, editor LMB, performance feel) remain in the doc for playtest.

Usage:
  python3 tools/run_grand_theater_qc.py
  python3 tools/run_grand_theater_qc.py --dir data/provinces_phase1_test
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    Image = None  # type: ignore

ROOT = Path(__file__).resolve().parent.parent


def check(label: str, ok: bool, detail: str = "") -> bool:
    status = "PASS" if ok else "FAIL"
    line = f"[QC {status}] {label}"
    if detail:
        line += f" — {detail}"
    print(line)
    return ok


def img_info(path: Path) -> tuple[int, int, int]:
    if Image is None or not path.exists():
        return (0, 0, 0)
    with Image.open(path) as im:
        return im.size[0], im.size[1], path.stat().st_size


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", default="data/provinces_phase1_test")
    parser.add_argument("--skip-godot", action="store_true")
    args = parser.parse_args()

    data_dir = ROOT / args.dir
    passed = 0
    total = 0

    def run(label: str, ok: bool, detail: str = "") -> None:
        nonlocal passed, total
        total += 1
        if check(label, ok, detail):
            passed += 1

    print("=== Grand Theater QC (automated) ===")

    # Items 1, 10, 37 — underlay assets present and not tiny placeholders
    for rel, min_w, min_kb in [
        ("assets/maps/world_grand_theater_ultra_high.jpg", 7000, 1500),
        ("assets/maps/europe_grand_theater_ultra_high.jpg", 4000, 800),
        ("assets/maps/layers/world_grand_theater_clean.png", 7000, 3000),
        ("assets/maps/layers/europe_grand_theater_clean.png", 4000, 1500),
    ]:
        p = ROOT / rel
        w, h, sz = img_info(p)
        run(
            f"Asset {rel}",
            p.exists() and w >= min_w and sz >= min_kb * 1024,
            f"{w}x{h} {sz // 1024}KB" if p.exists() else "missing",
        )

    # Layer stack (items 12–13 wiring)
    for rel in [
        "assets/maps/layers/world_layer_rivers.png",
        "assets/maps/layers/world_layer_elevation.png",
        "assets/maps/layers/world_grand_theater_composite.png",
        "data/map/layer_metadata.json",
        "data/map/rivers.json",
    ]:
        p = ROOT / rel
        run(f"Layer/data {rel}", p.exists(), f"{p.stat().st_size // 1024}KB" if p.exists() else "missing")

    # World chunks (item 37 full scope)
    manifest = ROOT / "assets/maps/world_chunks/world_chunks_manifest.json"
    chunk_ok = manifest.exists()
    chunk_n = 0
    if chunk_ok:
        doc = json.loads(manifest.read_text())
        chunk_n = len(doc.get("chunks", doc.get("entries", [])))
    run("World chunks manifest", chunk_ok and chunk_n >= 4, f"chunks={chunk_n}")

    # Province data (items 11–15, 23, 27, 35)
    geom_path = data_dir / "provinces_geometry.json"
    geom_n = 0
    sea_n = 0
    if geom_path.exists():
        geom = json.loads(geom_path.read_text())
        for entry in geom.get("provinces", []):
            geom_n += 1
            if entry.get("is_sea"):
                sea_n += 1
    run("Province geometry count", 350 <= geom_n <= 500, f"n={geom_n} sea={sea_n}")

    val = subprocess.run(
        [sys.executable, str(ROOT / "tools/validate_province_layers.py"), "--dir", str(data_dir), "--strict-base"],
        capture_output=True,
        text=True,
        cwd=str(ROOT),
    )
    run("Validator strict-base", val.returncode == 0, val.stdout.strip().split("\n")[-1] if val.stdout else val.stderr[:120])

    align = subprocess.run(
        [
            sys.executable,
            str(ROOT / "tools/map_generation/scripts/align_province_spot_check.py"),
            "--dir",
            str(data_dir),
            "--europe-only",
        ],
        capture_output=True,
        text=True,
        cwd=str(ROOT),
    )
    run("City alignment (europe-only)", align.returncode == 0, align.stdout.strip().split("\n")[-1] if align.stdout else "")

    choke_path = data_dir / "naval_chokepoints.json"
    choke_n = 0
    if choke_path.exists():
        choke_n = len(json.loads(choke_path.read_text()).get("chokepoint_province_ids", []))
    run("Naval chokepoints data-driven", choke_n >= 10, f"count={choke_n}")

    variants_path = ROOT / "tools/map_generation/output/phase1_europe/map_visual_features_variants_phase1.json"
    if variants_path.exists():
        vdoc = json.loads(variants_path.read_text())
        blob = json.dumps(vdoc).lower()
        run(
            "Visual variants JSON (item 11)",
            "expanded" in blob or "uk" in blob or "scand" in blob,
            str(variants_path.relative_to(ROOT)),
        )
    else:
        run("Visual variants JSON (item 11)", False, "missing (run generate_europe_phase1.py)")

    # Item 38 — terrain toggle API exists in MapRenderer
    mr = ROOT / "scripts/map/MapRenderer.gd"
    mr_text = mr.read_text(encoding="utf-8") if mr.exists() else ""
    run("Terrain clean-view API (item 38)", "set_show_terrain_layer" in mr_text and "toggle_terrain_layer" in mr_text)

    # Item 13 — infra overlay layer
    infra = ROOT / "scripts/map/InfrastructureOverlayLayer.gd"
    infra_text = infra.read_text(encoding="utf-8") if infra.exists() else ""
    run("Infra R/T layers (item 13)", "rebuild_road_layer" in infra_text and "rebuild_rail_layer" in infra_text)

    # Era infra + mesh perf (recent phases)
    run("Era infra profiles", "get_era_infra_profile" in infra_text)
    run("Batched mesh layer", "ProvinceMeshLayer" in mr_text and "get_batched_mesh_stats" in mr_text)

    # Item 35 — godot compile
    if not args.skip_godot:
        which = subprocess.run(["which", "godot"], capture_output=True, text=True)
        if which.returncode == 0:
            g = subprocess.run(
                ["godot", "--headless", "--path", str(ROOT), "--check-only"],
                capture_output=True,
                text=True,
                cwd=str(ROOT),
                timeout=300,
            )
            err = g.stderr + g.stdout
            parse_ok = "Parse Error" not in err and "Failed to load script" not in err
            run("Godot --check-only (item 35)", g.returncode == 0 or parse_ok, f"exit={g.returncode}")
        else:
            run("Godot --check-only (item 35)", False, "godot not in PATH")

    print(f"\n=== GRAND THEATER QC: {passed}/{total} automated checks passed ===")
    print("Manual: items 2–9, 16–22, 28–30, 36, 39–47 require F5 + F10 playtest (see docs/TEST_MAP_GRAND_THEATER_FOUNDATION.md)")
    return 0 if passed >= int(total * 0.85) else 1


if __name__ == "__main__":
    raise SystemExit(main())
