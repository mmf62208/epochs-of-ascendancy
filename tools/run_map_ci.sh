#!/usr/bin/env bash
# Map data + asset CI pipeline (Phase A–F validators). Run from project root.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DIR="${1:-data/provinces_phase1_test}"

echo "=== Map CI: $DIR ==="
python3 tools/map_generation/scripts/sync_river_aware_terrain.py --dir "$DIR"
python3 tools/map_generation/scripts/repair_city_positions.py --dir "$DIR"
python3 tools/map_generation/scripts/promote_map_master.py
python3 tools/map_generation/scripts/sync_phase1_base_catalog.py --dir "$DIR"
python3 tools/map_generation/scripts/repair_phase1_references.py --dir "$DIR"
python3 tools/validate_province_layers.py --dir "$DIR" --strict-base
python3 tools/map_generation/scripts/align_province_spot_check.py --dir "$DIR" --europe-only
python3 tools/map_generation/scripts/export_naval_chokepoints.py

python3 tools/run_grand_theater_qc.py --skip-godot

echo "=== Map CI PASSED ==="
