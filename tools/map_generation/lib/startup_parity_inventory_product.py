"""STARTUP-PARITY static board inventory (no Godot, no seed/perf suite).

Reads shipped world_accurate files and reports counts + SHA-256.
576 garrisons is a runtime empty-board seed_1936_start_garrisons count,
not a static file total. Live F5 occupancy skip is observed in Godot.
The dict key stays garrison_575 from the earlier baseline.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"

KEY_FILES: List[str] = [
    "manifest_world_accurate.json",
    "provinces_base.json",
    "province_ownership_1936.json",
    "province_adjacency.json",
    "hierarchy_membership_1936.json",
]

BERLIN_PID = 710300
MANIFEST_PROVINCES = 3596
MANIFEST_LAND = 3256
MANIFEST_SEA = 340
EMPTY_BOARD_GARRISONS = 576


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def inventory_world_accurate_board(data_dir: Path | None = None) -> Dict[str, Any]:
    d = Path(data_dir) if data_dir is not None else DEFAULT_DIR
    out: Dict[str, Any] = {
        "ok": False,
        "data_dir": str(d),
        "file_sha256": {},
        "missing": [],
        "province_ids_n": 0,
        "has_berlin_710300": False,
        "manifest_provinces": None,
        "manifest_land": None,
        "manifest_sea": None,
        "fail": [],
    }
    if not d.is_dir():
        out["fail"].append("data_dir_missing")
        return out

    for name in KEY_FILES:
        p = d / name
        if not p.is_file():
            out["missing"].append(name)
            continue
        out["file_sha256"][name] = _sha256_file(p)

    if out["missing"]:
        out["fail"].append("missing_key_files")
        return out

    manifest = json.loads((d / "manifest_world_accurate.json").read_text(encoding="utf-8"))
    stats = manifest.get("stats") if isinstance(manifest, dict) else {}
    if not isinstance(stats, dict):
        stats = {}
    out["manifest_provinces"] = stats.get("provinces")
    out["manifest_land"] = stats.get("land")
    out["manifest_sea"] = stats.get("sea")

    base = json.loads((d / "provinces_base.json").read_text(encoding="utf-8"))
    rows = base.get("provinces") if isinstance(base, dict) else None
    if not isinstance(rows, list):
        out["fail"].append("provinces_base_not_list")
        return out
    ids: List[int] = []
    for row in rows:
        if isinstance(row, dict) and "id" in row:
            ids.append(int(row["id"]))
    out["province_ids_n"] = len(ids)
    out["has_berlin_710300"] = BERLIN_PID in ids

    if out["manifest_provinces"] != MANIFEST_PROVINCES:
        out["fail"].append(
            "manifest_provinces=%s want %d" % (out["manifest_provinces"], MANIFEST_PROVINCES)
        )
    if out["manifest_land"] != MANIFEST_LAND:
        out["fail"].append("manifest_land=%s want %d" % (out["manifest_land"], MANIFEST_LAND))
    if out["manifest_sea"] != MANIFEST_SEA:
        out["fail"].append("manifest_sea=%s want %d" % (out["manifest_sea"], MANIFEST_SEA))
    if out["province_ids_n"] != MANIFEST_PROVINCES:
        out["fail"].append(
            "province_ids_n=%d want %d" % (out["province_ids_n"], MANIFEST_PROVINCES)
        )
    if not out["has_berlin_710300"]:
        out["fail"].append("berlin_710300_missing")

    out["ok"] = len(out["fail"]) == 0
    out["garrison_575"] = {
        "kind": "empty_board_runtime",
        "empty_board_targets": EMPTY_BOARD_GARRISONS,
        "note": (
            "576 is seed_1936_start_garrisons on an empty formation table "
            "(HeadlessGarrison1Test). MAP-2a residual added Kingston--Pembroke "
            "903045 to New York West 800446, so ENG gained one border garrison. "
            "Live F5 TestScenario already has OOB land on some border/capital hexes; "
            "those hexes are skipped, so placed < 576 while targets stay 576."
        ),
    }
    out["seed_20fe9063"] = {
        "kind": "godot_runtime",
        "method": (
            "md5 of text after 'HeadlessPerf4LiveMultiAiDayTest: ' on the "
            "multi_ai_decisions= line, plus a trailing newline"
        ),
        "expect_prefix": "20fe9063",
        "expect_full": "20fe9063de285f19d4f9b8a105abfd31",
        "note": "Recomputed by tools/eoa_startup_parity.sh via EOA_PERF4_SEED_ONLY=1",
    }
    return out


def build_startup_parity_inventory_product(data_dir: Path | None = None) -> Dict[str, Any]:
    inv = inventory_world_accurate_board(data_dir)
    return {
        "ok": bool(inv.get("ok")),
        "status": "PASS" if inv.get("ok") else "FAIL",
        "inventory": inv,
    }
