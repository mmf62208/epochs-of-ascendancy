"""Basing fleet station — treaty docking rights tip fleet station preference (R7 follow-on)."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict, Optional

from naval_basing import compute_naval_basing  # type: ignore
from naval_fleet_ops import (  # type: ignore
    format_fleet_station_preference,
    rank_fleet_station_candidates,
    score_fleet_station_candidate,
    treaty_basing_beats_unowned_foreign,
)

ROOT = Path(__file__).resolve().parents[3]

SURFACE_KEYS = (
    "bfs_primary_catalog",
    "bfs_primary_score",
    "bfs_primary_grant",
    "bfs_primary_prefer",
    "bfs_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "bfs_catalog",
    "bfs_score",
    "bfs_grant",
    "bfs_prefer",
    "bfs_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "bfs_catalog": "apply_basing_fleet_station_catalog_live",
    "bfs_score": "apply_basing_fleet_station_score_live",
    "bfs_grant": "apply_basing_fleet_station_grant_live",
    "bfs_prefer": "apply_basing_fleet_station_prefer_live",
    "bfs_close": "apply_basing_fleet_station_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": ok,
        "summary": "Basing fleet station audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL"),
        "plain": "Basing fleet station audit", "empty": False,
    }


def build_basing_fleet_station_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    owned_anch = compute_naval_basing(domain="coastal_land", is_coastal=True, province_id=1)
    foreign_maj = compute_naval_basing(
        domain="coastal_land",
        is_coastal=True,
        has_naval_shipyard=True,
        port_tier=3,
        is_chokepoint=True,
        province_id=2,
    )
    tip = treaty_basing_beats_unowned_foreign(owned_anch, foreign_maj)
    score_ok = bool(tip.get("ok"))
    ranked = rank_fleet_station_candidates([
        {"province_id": 1, "basing": owned_anch, "is_owned": True},
        {"province_id": 2, "basing": foreign_maj, "is_owned": False, "has_treaty_basing": True},
    ])
    prefer_ok = int(ranked.get("best_province_id", -1)) == 2
    plain = format_fleet_station_preference(ranked)
    plain_ok = "treaty basing" in plain or "Fleet basing prefer #2" in plain
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = score_ok and prefer_ok and plain_ok and audit["ok"]
    steps_out = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step],
            "live_api": api, "leaf_action": api,
            "label": "BFS · %s · live %s" % (step, api),
            "score": 0.81 + 0.02 * i, "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Basing fleet station · score_ok=%s prefer_ok=%s" % (score_ok, prefer_ok)
    return {
        "score": 0.87 if all_ok else 0.4,
        "plain": label, "summary": label, "empty": False, "province_id": pid,
        "score_ok": score_ok, "prefer_ok": prefer_ok, "plain_ok": plain_ok,
        "tip": tip, "ranked": ranked, "preference_plain": plain,
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": [
            "basing_fleet_station_product", "treaty_basing", "fleet_station_preference",
            "docking_rights", "strategic_compact_ledger",
        ],
    }
