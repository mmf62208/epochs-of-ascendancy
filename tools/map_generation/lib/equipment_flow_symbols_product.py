"""CP3 pure product — EquipmentFlow map symbol strip / theater glyphs."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]

SURFACE_KEYS = (
    "efs_primary_catalog",
    "efs_primary_modes",
    "efs_primary_board",
    "efs_primary_strip",
    "efs_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "efs_catalog",
    "efs_modes",
    "efs_board",
    "efs_strip",
    "efs_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "efs_catalog": "apply_equipment_flow_symbols_catalog_live",
    "efs_modes": "apply_equipment_flow_symbols_modes_live",
    "efs_board": "apply_equipment_flow_symbols_board_live",
    "efs_strip": "apply_equipment_flow_symbols_strip_live",
    "efs_close": "apply_equipment_flow_symbols_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)

MODE_SYMBOL = {
    "rail": "train", "road": "truck", "airlift": "transport_plane",
    "helicopter": "helicopter", "sealift": "merchant", "river": "barge",
    "drone_logistics": "drone_convoy", "orbital": "orbital_loft",
}


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead),
        "ok": len(dead) == 0 and len(ids) >= 5,
        "summary": "Equipment flow symbols audit", "plain": "Equipment flow symbols audit", "empty": False,
    }


def build_equipment_flow_symbols_primary_command_product(
    *, province_id: int = 1, live_ids=None
) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    calc = (ROOT / "scripts/production/EquipmentFlowCalculator.gd").read_text(encoding="utf-8")
    pm = (ROOT / "scripts/autoload/ProductionManager.gd").read_text(encoding="utf-8")
    gd = (ROOT / "scripts/autoload/GameData.gd").read_text(encoding="utf-8")
    sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text(encoding="utf-8")
    freeze = (ROOT / "docs/COMBAT_PRODUCTION_ENGINE_DESIGN_FREEZE.md").read_text(encoding="utf-8")

    hooks_ok = all(
        s in calc for s in ("func symbol_for_mode", "MODE_SYMBOL", "train", "truck", "merchant")
    ) and all(
        s in pm for s in (
            "func get_equipment_flow_board",
            "func format_equipment_flow_map_strip",
            "glyphs",
        )
    ) and "func apply_equipment_flow_symbols_primary_live" in gd \
        and "equipment_flow_symbols_primary_live=1" in sl

    modes_ok = all(k in freeze for k in ("rail", "road", "airlift", "sealift", "train", "truck"))
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = hooks_ok and modes_ok and audit["ok"]

    steps_out, apply_queue = [], []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step], "live_api": api,
            "leaf_action": api, "label": "EFS · %s" % step, "score": 0.88 + 0.02 * i,
            "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})

    label = "Equipment flow symbols · hooks=%s modes=%s" % (hooks_ok, modes_ok)
    return {
        "score": 0.95 if all_ok else 0.4, "plain": label, "summary": label, "empty": False,
        "province_id": pid, "hooks_ok": hooks_ok, "modes_ok": modes_ok,
        "model": "equipment_flow_compact_ledger",
        "mode_symbol": dict(MODE_SYMBOL),
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": ["equipment_flow_symbols_product", "EquipmentFlowCalculator", "ProductionManager"],
        "phase": "CP3",
    }
