"""Space open path primary product."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]
SURFACE_KEYS = ('sop_primary_catalog', 'sop_primary_topbar', 'sop_primary_diplo', 'sop_primary_board', 'sop_primary_close')
PRIMARY_COMMAND_STEPS = ('sop_catalog', 'sop_topbar', 'sop_diplo', 'sop_board', 'sop_close')
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {'sop_catalog': 'apply_space_open_path_catalog_live', 'sop_topbar': 'apply_space_open_path_topbar_live', 'sop_diplo': 'apply_space_open_path_diplo_live', 'sop_board': 'apply_space_open_path_board_live', 'sop_close': 'apply_space_open_path_close_live'}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)
HOOKS = [('scripts/ui/TopInfoBar.gd', 'func _on_space_pressed'), ('scripts/ui/TopInfoBar.gd', 'space_button'), ('scripts/ui/DiplomacyView.gd', 'func _open_space_layer_board'), ('scripts/ui/DiplomacyView.gd', 'SpaceBoardButton'), ('scripts/ui/SpaceLayerBoardView.gd', 'func show_board'), ('scripts/ui/SpaceLayerBoardView.gd', 'class_name SpaceLayerBoardView')]

def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    return {"action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": len(dead)==0 and len(ids)>=5,
            "summary": "Space open path audit", "plain": "Space open path audit", "empty": False}

def build_space_open_path_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    hooks_ok = True
    for fpath, needle in HOOKS:
        txt = (ROOT / fpath).read_text(encoding="utf-8")
        if needle not in txt:
            hooks_ok = False
            break
    audit = primary_command_dead_audit(live_ids=live_ids)
    all_ok = hooks_ok and audit["ok"]
    steps_out, apply_queue = [], []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append({"index": i, "step": step, "major": _STEP_MAJOR[step], "live_api": api,
            "leaf_action": api, "label": "SOP · %s" % step, "score": 0.86+0.02*i,
            "enabled": True, "province_id": pid})
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Space open path · hooks_ok=%s" % hooks_ok
    return {"score": 0.93 if all_ok else 0.4, "plain": label, "summary": label, "empty": False,
        "province_id": pid, "hooks_ok": hooks_ok, "model": "orbital_compact_ledger",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit, "steps": steps_out,
        "step_ids": list(PRIMARY_COMMAND_STEPS), "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": ["space_open_path_product"]}
