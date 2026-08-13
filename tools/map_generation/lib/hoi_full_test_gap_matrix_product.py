"""HOI4 ↔ EOA full-test gap matrix — pure product driving real shipped builders.

Proves P0 machine pillars are LANDED by calling actual product entry points
(not re-implementing them). Open P0 count is expected 0 after map machine close.

See docs/HOI4_EOA_GAP_REVIEW.md.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[3]
REVIEW = ROOT / "docs" / "HOI4_EOA_GAP_REVIEW.md"
SNAPSHOT = ROOT / "docs" / "GAME_STATUS_SNAPSHOT.md"

# (pillar_id, display name, import_module, builder_name, kwargs)
# Builder must return dict with ok / all_majors_ok / status PASS.
P0_PILLARS: List[Tuple[str, str, str, str, Dict[str, Any]]] = [
    (
        "map_board_capitals",
        "Capitals pickable on world_accurate",
        "world_accurate_capital_pick_product",
        "build_world_accurate_capital_pick_product",
        {},
    ),
    (
        "map_density_us",
        "US playable density band",
        "us_state_province_density_product",
        "build_us_state_province_density_product",
        {},
    ),
    (
        "map_density_row",
        "RoW sparse densify closed",
        "row_sparse_density_product",
        "build_row_sparse_density_product",
        {},
    ),
    (
        "political_readability",
        "Political/ownership mapmode readability",
        "ownership_mapmode_readability_product",
        "build_ownership_mapmode_readability_product",
        {},
    ),
    (
        "land_multi_front_warloop",
        "WarLoop first-session surface",
        "map_war_path_surface_product",
        "build_map_war_path_surface_product",
        {"country_tag": "GER"},
    ),
    (
        "land_multi_front_fronts",
        "Live border fronts surface",
        "map_live_border_fronts_surface_product",
        "build_map_live_border_fronts_surface_product",
        {"country_tag": "GER"},
    ),
    (
        "supply_corridor",
        "Supply capital→front corridor",
        "map_supply_corridor_product",
        "build_supply_corridor_product",
        {},
    ),
    (
        "industry_production",
        "Production honesty primary",
        "production_honesty_primary_command_product",
        "build_production_honesty_primary_command_product",
        {},
    ),
    (
        "research",
        "Research queue primary",
        "research_queue_primary_command_product",
        "build_research_queue_primary_command_product",
        {},
    ),
    (
        "politics_diplomacy",
        "Peace conference primary",
        "peace_conference_primary_command_product",
        "build_peace_conference_primary_command_product",
        {},
    ),
    (
        "air_theater",
        "Air theater primary",
        "air_theater_primary_command_product",
        "build_air_theater_primary_command_product",
        {},
    ),
    (
        "naval_fleet",
        "Fleet autonomy primary",
        "fleet_autonomy_primary_command_product",
        "build_fleet_autonomy_primary_command_product",
        {},
    ),
    (
        "intel",
        "Intel network primary",
        "intel_network_primary_command_product",
        "build_intel_network_primary_command_product",
        {},
    ),
    (
        "oob",
        "Historical OOB primary",
        "historical_oob_primary_command_product",
        "build_historical_oob_primary_command_product",
        {},
    ),
    (
        "logistics",
        "Logistics supply primary",
        "logistics_supply_primary_command_product",
        "build_logistics_supply_primary_command_product",
        {},
    ),
    (
        "multi_front_primary",
        "Multi-front primary command",
        "multi_front_primary_command_product",
        "build_multi_front_primary_command_product",
        {},
    ),
    (
        "save_resume",
        "Save/resume primary (campaign continuity)",
        "save_resume_primary_command_product",
        "build_save_resume_primary_command_product",
        {"province_id": 710300},
    ),
]


def _product_ok(p: Dict[str, Any]) -> bool:
    if bool(p.get("ok")):
        return True
    if bool(p.get("all_majors_ok")) and int(p.get("dead_n") or 0) == 0:
        return True
    status = str(p.get("status") or "").upper()
    if status in ("PASS", "PASS_30", "OK"):
        return True
    summary = str(p.get("summary") or "")
    if "PASS" in summary and "FAIL" not in summary.split("·")[-1]:
        # e.g. "... · PASS" at end
        if summary.rstrip().endswith("PASS") or " · PASS" in summary:
            return True
    return False


def _call_builder(mod_name: str, fn_name: str, kwargs: Dict[str, Any]) -> Dict[str, Any]:
    mod = __import__(mod_name)
    fn: Callable[..., Dict[str, Any]] = getattr(mod, fn_name)
    return fn(**kwargs) if kwargs else fn()


def build_hoi_full_test_gap_matrix_product() -> Dict[str, Any]:
    """Run all P0 pillar builders; return matrix with open_p0_n (expect 0)."""
    passes: List[str] = []
    fails: List[str] = []
    rows: List[Dict[str, Any]] = []

    if REVIEW.is_file():
        body = REVIEW.read_text(encoding="utf-8")
        if "Open P0 count: 0" in body or "open P0 count: 0" in body.lower():
            passes.append("review_claims_zero_open_p0")
        else:
            fails.append("review_missing_zero_open_p0_claim")
        if "Industry" in body or "industry" in body.lower():
            passes.append("review_has_industry_pillar")
        for needle in (
            "research",
            "diplomacy",
            "multi-front",
            "supply",
            "air",
            "naval",
            "intel",
            "OOB",
        ):
            if needle.lower() in body.lower():
                passes.append("review_mentions_%s" % needle.replace(" ", "_"))
    else:
        fails.append("missing_HOI4_EOA_GAP_REVIEW")

    if SNAPSHOT.is_file():
        snap = SNAPSHOT.read_text(encoding="utf-8")
        if "3520" in snap:
            passes.append("snapshot_3520")
        else:
            fails.append("snapshot_missing_3520")
        if "M6" in snap and ("open" in snap.lower() or "human" in snap.lower()):
            passes.append("snapshot_m6_human_open")
        if "machine" in snap.lower() and "closed" in snap.lower():
            passes.append("snapshot_map_machine_closed")
    else:
        fails.append("missing_GAME_STATUS_SNAPSHOT")

    open_p0: List[str] = []
    for pillar_id, label, mod_name, fn_name, kwargs in P0_PILLARS:
        row: Dict[str, Any] = {
            "pillar_id": pillar_id,
            "label": label,
            "module": mod_name,
            "builder": fn_name,
            "status": "OPEN",
        }
        try:
            p = _call_builder(mod_name, fn_name, kwargs)
            ok = _product_ok(p)
            row["product_ok"] = ok
            row["summary"] = str(p.get("summary") or p.get("status") or "")[:160]
            if ok:
                row["status"] = "LANDED"
                passes.append("p0_%s" % pillar_id)
            else:
                row["status"] = "OPEN"
                open_p0.append(pillar_id)
                fails.append("p0_fail_%s" % pillar_id)
        except Exception as exc:  # noqa: BLE001 — surface real import/build errors
            row["product_ok"] = False
            row["status"] = "OPEN"
            row["error"] = str(exc)[:200]
            open_p0.append(pillar_id)
            fails.append("p0_exc_%s=%s" % (pillar_id, type(exc).__name__))
        rows.append(row)

    open_n = len(open_p0)
    if open_n == 0:
        passes.append("zero_open_p0")
    else:
        fails.append("open_p0_n=%d" % open_n)

    ok = len(fails) == 0 and open_n == 0
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "open_p0_n": open_n,
        "open_p0": open_p0,
        "landed_n": sum(1 for r in rows if r.get("status") == "LANDED"),
        "pillar_n": len(rows),
        "rows": rows,
        "pass": passes,
        "fail": fails,
        "review_path": str(REVIEW.relative_to(ROOT)) if REVIEW.is_file() else "",
        "summary": (
            "HOI full-test gap matrix · pillars=%d · landed=%d · open_p0=%d · %s"
            % (
                len(rows),
                sum(1 for r in rows if r.get("status") == "LANDED"),
                open_n,
                "PASS" if ok else "FAIL",
            )
        ),
        "integration": [
            "hoi_full_test_gap_matrix_product",
            "HOI4_EOA_GAP_REVIEW",
            "world_accurate",
            "full_test",
        ],
        "non_goals": [
            "m6_human_20d_60d",
            "museum_borders",
            "13k_provinces",
            "multiplayer",
            "soft_30fps_hard_pass",
            "full_designer_parity",
        ],
    }


def hoi_full_test_gap_matrix_integrity() -> Dict[str, Any]:
    p = build_hoi_full_test_gap_matrix_product()
    return {
        "ok": bool(p.get("ok")),
        "open_p0_n": p.get("open_p0_n"),
        "landed_n": p.get("landed_n"),
        "fail": p.get("fail") or [],
        "summary": p.get("summary"),
        "empty": False,
    }
