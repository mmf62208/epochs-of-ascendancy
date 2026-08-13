"""Space discovery UI primary product — board/lobby surface dual."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[3]
SURFACE_KEYS = ('sdu_primary_catalog', 'sdu_primary_unresolved', 'sdu_primary_choose', 'sdu_primary_reresolve', 'sdu_primary_close')
PRIMARY_COMMAND_STEPS = ('sdu_catalog', 'sdu_unresolved', 'sdu_choose', 'sdu_reresolve', 'sdu_close')
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {'sdu_catalog': 'apply_space_discovery_ui_catalog_live', 'sdu_unresolved': 'apply_space_discovery_ui_unresolved_live', 'sdu_choose': 'apply_space_discovery_ui_choose_live', 'sdu_reresolve': 'apply_space_discovery_ui_reresolve_live', 'sdu_close': 'apply_space_discovery_ui_close_live'}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)
HOOKS = [('scripts/ui/SpaceLayerBoardView.gd', 'func apply_discovery_choice_from_board'), ('scripts/ui/SpaceLayerBoardView.gd', 'func get_unresolved_from_board'), ('scripts/space/SpaceLayerManager.gd', 'func list_unresolved_discoveries'), ('scripts/space/SpaceLayerManager.gd', 'func resolve_discovery_choice')]

def primary_command_dead_audit(action_ids=None, *, live_ids=None):
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    return {"action_ids": ids, "dead": dead, "dead_n": len(dead), "ok": len(dead)==0 and len(ids)>=5,
            "summary": "Space discovery UI audit", "plain": "Space discovery UI audit", "empty": False}

def build_space_discovery_ui_primary_command_product(*, province_id: int = 1, live_ids=None) -> Dict[str, Any]:
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
            "leaf_action": api, "label": "SDU · %s" % step, "score": 0.87+0.02*i,
            "enabled": True, "province_id": pid})
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Space discovery UI · hooks_ok=%s" % hooks_ok
    return {"score": 0.94 if all_ok else 0.4, "plain": label, "summary": label, "empty": False,
        "province_id": pid, "hooks_ok": hooks_ok, "model": "orbital_compact_ledger",
        "surface_keys": list(SURFACE_KEYS), "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0, "all_majors_ok": all_ok,
        "dead_n": int(audit["dead_n"]), "audit": audit, "steps": steps_out,
        "step_ids": list(PRIMARY_COMMAND_STEPS), "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS), "apply_queue": apply_queue,
        "integration": ["space_discovery_ui_product"]}
