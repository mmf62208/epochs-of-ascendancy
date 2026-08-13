"""CP3 map paint pure product — EquipmentFlow glyphs on strategic flow overlay."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]

SURFACE_KEYS = (
    "efp_primary_catalog",
    "efp_primary_symbols",
    "efp_primary_board",
    "efp_primary_paint",
    "efp_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "efp_catalog",
    "efp_symbols",
    "efp_board",
    "efp_paint",
    "efp_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "efp_catalog": "apply_equipment_flow_paint_catalog_live",
    "efp_symbols": "apply_equipment_flow_paint_symbols_live",
    "efp_board": "apply_equipment_flow_paint_board_live",
    "efp_paint": "apply_equipment_flow_paint_paint_live",
    "efp_close": "apply_equipment_flow_paint_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)


def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    return {
        "action_ids": ids, "dead": dead, "dead_n": len(dead),
        "ok": len(dead) == 0 and len(ids) >= 5,
        "summary": "Equipment flow paint audit", "plain": "Equipment flow paint audit", "empty": False,
    }


def build_equipment_flow_paint_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    layer = (ROOT / "scripts/map/StrategicFlowOverlayLayer.gd").read_text(encoding="utf-8")
    pm = (ROOT / "scripts/autoload/ProductionManager.gd").read_text(encoding="utf-8")
    gd = (ROOT / "scripts/autoload/GameData.gd").read_text(encoding="utf-8")
    sl = (ROOT / "scripts/core/ScenarioLoader.gd").read_text(encoding="utf-8")

    hooks_ok = all(
        s in layer for s in (
            "show_equipment_flows",
            "func _draw_equipment_flow_glyphs",
            "func _draw_equipment_symbol",
            "func collect_equipment_paint_preview",
            "train", "truck", "transport_plane", "merchant", "drone_convoy", "orbital_loft",
        )
    ) and "func get_equipment_flow_board" in pm and "glyphs" in pm \
        and "func apply_equipment_flow_paint_primary_live" in gd \
        and "equipment_flow_paint_primary_live=1" in sl

    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = hooks_ok and audit["ok"]
    steps_out, apply_queue = [], []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({
            "index": i, "step": step, "major": _STEP_MAJOR[step], "live_api": api,
            "leaf_action": api, "label": "EFP · %s" % step, "score": 0.88 + 0.02 * i,
            "enabled": True, "province_id": pid,
        })
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Equipment flow paint · hooks=%s" % hooks_ok
    return {
        "score": 0.95 if all_ok else 0.4, "plain": label, "summary": label, "empty": False,
        "province_id": pid, "hooks_ok": hooks_ok, "model": "equipment_flow_compact_ledger",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit,
        "steps": steps_out, "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": ["equipment_flow_paint_product", "StrategicFlowOverlayLayer", "ProductionManager"],
        "phase": "CP3_paint",
    }
