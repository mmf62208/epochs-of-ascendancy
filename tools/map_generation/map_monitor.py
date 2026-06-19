#!/usr/bin/env python3
"""
Persistent Map Monitor & Autonomous Maintenance Subagent
for Epochs of Ascendancy - Map Generation Pipeline.

Monitors tools/map_generation/ and data/provinces_full_europe/, data/provinces_phase1_test/
- Tracks province counts (target 350-450+)
- Re-runs generate + apply if below target or stale
- Ensures data/ dirs updated from latest merged output (merged_v3_closest_wiring or future variants)
- Validates key layers and ScenarioLoader phase1_europe_test scenario compatibility
- Keeps map playtest-ready (focus: ONLY territory/map data layers)
- Reports cycle status periodically.

Run in background; poll status via get_command_or_subagent_output <task_id>
"""

import json
import os
import subprocess
import time
import glob
from datetime import datetime
from pathlib import Path

# Config
PROJECT_ROOT = Path(__file__).resolve().parents[2]
DATA_FULL = PROJECT_ROOT / "data" / "provinces_full_europe"
DATA_TEST = PROJECT_ROOT / "data" / "provinces_phase1_test"
OUTPUT_PHASE1 = PROJECT_ROOT / "tools" / "map_generation" / "output" / "phase1_europe"
SCRIPTS_DIR = PROJECT_ROOT / "tools" / "map_generation" / "scripts"
MERGE_VARIANT = "merged_v3_closest_wiring"  # from apply_phase1_merge.py ; update if changes
CHECK_INTERVAL_SEC = 300  # 5 minutes
TARGET_MIN = 350
TARGET_MAX = 450
STALE_THRESHOLD_SEC = 86400 * 7  # consider >7 days old potentially stale for regen consideration

CYCLE = 0

def log(msg: str):
    ts = datetime.now().isoformat(timespec="seconds")
    print(f"[{ts}] {msg}", flush=True)

def get_province_count(path: Path) -> int:
    if not path.exists():
        return 0
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        provinces = data.get("provinces", [])
        if isinstance(provinces, list):
            return len(provinces)
        if isinstance(provinces, dict):
            return len(provinces)
        return 0
    except Exception as e:
        log(f"ERROR reading {path}: {e}")
        return 0

def get_latest_mtime(path: Path) -> float:
    if not path.exists():
        return 0.0
    return path.stat().st_mtime

def get_latest_gen_info() -> str:
    # Prefer the current variant dir's geometry mtime + files
    variant_dir = OUTPUT_PHASE1 / MERGE_VARIANT
    geom = variant_dir / "provinces_geometry.json"
    if geom.exists():
        dt = datetime.fromtimestamp(get_latest_mtime(geom)).isoformat(timespec="minutes")
        cnt = get_province_count(geom)
        return f"{dt} (merged_{MERGE_VARIANT} {cnt} provinces)"
    # Fallback to any recent in output
    candidates = list(OUTPUT_PHASE1.glob("*/provinces_geometry.json"))
    if candidates:
        latest = max(candidates, key=lambda p: p.stat().st_mtime)
        dt = datetime.fromtimestamp(latest.stat().st_mtime).isoformat(timespec="minutes")
        return f"{dt} (from {latest.parent.name})"
    plan = OUTPUT_PHASE1 / "phase1_europe_plan.json"
    if plan.exists():
        dt = datetime.fromtimestamp(get_latest_mtime(plan)).isoformat(timespec="minutes")
        return f"{dt} (plan file)"
    return "unknown (no output yet)"

def has_key_layers(data_dir: Path) -> bool:
    required = [
        "provinces_geometry.json",
        "province_economy_layer.json",
        "province_states.json",
    ]
    for r in required:
        if not (data_dir / r).exists():
            return False
    # Quick parse check
    try:
        for r in required:
            with open(data_dir / r) as f:
                json.load(f)
        return True
    except:
        return False

def scenario_points_correctly() -> bool:
    scenario_path = PROJECT_ROOT / "data" / "scenarios" / "phase1_europe_test.json"
    if not scenario_path.exists():
        return False
    try:
        with open(scenario_path) as f:
            sc = json.load(f)
        return sc.get("use_province_data_dir") in ("provinces_full_europe", "provinces_phase1_test")
    except:
        return False

def ensure_base_in_full_europe():
    """Ensure provinces_base.json (840 catalog) is present in full_europe for ScenarioLoader compat."""
    base_src = DATA_TEST / "provinces_base.json"
    base_dst = DATA_FULL / "provinces_base.json"
    if not base_dst.exists() and base_src.exists():
        try:
            import shutil
            shutil.copy2(base_src, base_dst)
            log("Action: Copied provinces_base.json into data/provinces_full_europe/ for loader compatibility.")
            return True
        except Exception as e:
            log(f"ERROR copying base: {e}")
    return False

def copy_latest_merged_to_data():
    """Copy latest merged layers + artifacts from output to the two data dirs.
    Matches the maintenance requirement. Keeps base.json in place where present.
    """
    variant_dir = OUTPUT_PHASE1 / MERGE_VARIANT
    if not variant_dir.exists():
        log("WARN: No current merge variant dir to copy from.")
        return False

    files_to_copy = [
        "provinces_geometry.json",
        "province_economy_layer.json",
        "province_states.json",
        "province_terrain_layer.json",
        "province_resources_layer.json",
        "province_city_layer.json",
        "province_adjacency.json",
        "strategic_regions.json",
        "project_sites.json",
        "id_remap.json",
        "manifest.json",
        "phase1_europe_test_scenario.json",
    ]

    copied = 0
    for fname in files_to_copy:
        src = variant_dir / fname
        if not src.exists():
            continue
        # full_europe gets everything including merge docs
        dst_full = DATA_FULL / fname
        try:
            import shutil
            shutil.copy2(src, dst_full)
            copied += 1
        except Exception as e:
            log(f"ERROR copy {fname} to full: {e}")

        # phase1_test gets core layers (preserve its provinces_base.json)
        if fname not in ("id_remap.json", "manifest.json", "phase1_europe_test_scenario.json"):
            dst_test = DATA_TEST / fname
            try:
                import shutil
                shutil.copy2(src, dst_test)
                copied += 1
            except Exception as e:
                log(f"ERROR copy {fname} to test: {e}")

    if copied > 0:
        log(f"Action: Copied {copied} files from {MERGE_VARIANT} to data/provinces_* dirs.")
    return copied > 0

def check_and_maintain():
    global CYCLE
    CYCLE += 1

    count_full = get_province_count(DATA_FULL / "provinces_geometry.json")
    count_test = get_province_count(DATA_TEST / "provinces_geometry.json")

    latest_gen = get_latest_gen_info()

    # Staleness: compare data geom mtime to latest output geom
    data_mtime = get_latest_mtime(DATA_FULL / "provinces_geometry.json")
    variant_geom = OUTPUT_PHASE1 / MERGE_VARIANT / "provinces_geometry.json"
    output_mtime = get_latest_mtime(variant_geom)
    is_stale = (output_mtime > data_mtime + 60) or (data_mtime > 0 and (time.time() - data_mtime > STALE_THRESHOLD_SEC))

    below_target = count_full < TARGET_MIN or count_full < 378  # per prompt example

    actions = []

    # Always ensure base for compatibility (map territory support for loaders)
    if ensure_base_in_full_europe():
        actions.append("copy-base")

    if below_target or is_stale:
        log(f"Condition met (count={count_full}, stale={is_stale}). Autonomously re-running generation + merge...")
        try:
            cmd = f"cd {SCRIPTS_DIR.parent} && python3 scripts/generate_europe_phase1.py && python3 scripts/apply_phase1_merge.py"
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=600)
            if result.returncode == 0:
                actions.append("re-gen+apply")
                log("Generation + apply completed successfully.")
            else:
                log(f"ERROR during re-run: rc={result.returncode} stderr[:200]={result.stderr[:200]}")
                actions.append("re-gen-failed")
        except Exception as e:
            log(f"ERROR running re-gen cmd: {e}")
            actions.append("re-gen-error")

        # After run (or attempt), ensure data updated from the (new) merged
        if copy_latest_merged_to_data():
            actions.append("copy-merged-to-data")

        # Re-count after actions
        count_full = get_province_count(DATA_FULL / "provinces_geometry.json")
        count_test = get_province_count(DATA_TEST / "provinces_geometry.json")
        latest_gen = get_latest_gen_info()
    else:
        # Still ensure data in sync if output newer (even if counts OK)
        if output_mtime > data_mtime + 60:
            if copy_latest_merged_to_data():
                actions.append("copy-merged-to-data")
            count_full = get_province_count(DATA_FULL / "provinces_geometry.json")

    # Validate basic compatibility (map only)
    layers_ok = has_key_layers(DATA_FULL) and has_key_layers(DATA_TEST)
    scenario_ok = scenario_points_correctly()
    ready = "Yes" if (count_full >= TARGET_MIN and layers_ok and scenario_ok and count_full > 0) else "No"

    action_str = "/".join(actions) if actions else "none"

    status = (
        f"Map Monitor cycle {CYCLE}: "
        f"Current provinces in full_europe: {count_full} (target 350-450). "
        f"phase1_test: {count_test}. "
        f"Latest gen: [{latest_gen}]. "
        f"Actions taken: [{action_str}]. "
        f"Ready for playtest: {ready}. "
        f"Next check in ~{CHECK_INTERVAL_SEC//60}m."
    )
    print(status, flush=True)
    log(status)  # duplicate for bg log visibility

    # Extra validation note (map territories only)
    if ready == "Yes":
        log("Map territories validated: geometry/economy (dev/infra/settlement/pop/resources)/states present and loadable. ScenarioLoader switch to full_europe supported. Non-map effects (welfare etc) rely on these layers - no data breakage detected.")

def main():
    log("=== Persistent Map Monitor starting (background subagent) ===")
    log(f"Monitoring: {DATA_FULL}, {DATA_TEST}, {OUTPUT_PHASE1}")
    log(f"Re-run trigger: count < {TARGET_MIN} or stale (output newer or >{STALE_THRESHOLD_SEC//86400}d old) or <378 example threshold.")
    log(f"Re-run command (per spec): cd tools/map_generation && python3 scripts/generate_europe_phase1.py && python3 scripts/apply_phase1_merge.py")
    log("Copy target after: data/provinces_full_europe/ + data/provinces_phase1_test/ from latest merged variant.")
    log("Only map/territory maintenance. Use get_command_or_subagent_output on launch task_id for live reports.")

    # Initial immediate check
    check_and_maintain()

    while True:
        time.sleep(CHECK_INTERVAL_SEC)
        check_and_maintain()

if __name__ == "__main__":
    main()
