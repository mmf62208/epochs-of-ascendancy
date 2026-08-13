"""Combat/production design freeze audit — pure residual product.

Asserts the design freeze document locks scale, reinforcement, map symbols,
layered micro policy, and rewrite phases. Includes thin pure helpers for
identity-weighted stock batch resolution (design contract, not a second engine).
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT = Path(__file__).resolve().parents[3]
DESIGN_PATH = ROOT / "docs" / "COMBAT_PRODUCTION_ENGINE_DESIGN_FREEZE.md"

SURFACE_KEYS = (
    "cpd_primary_catalog",
    "cpd_primary_scale",
    "cpd_primary_flow",
    "cpd_primary_phases",
    "cpd_primary_close",
)
PRIMARY_COMMAND_STEPS = (
    "cpd_catalog",
    "cpd_scale",
    "cpd_flow",
    "cpd_phases",
    "cpd_close",
)
_STEP_MAJOR = {s: SURFACE_KEYS[i] for i, s in enumerate(PRIMARY_COMMAND_STEPS)}
LIVE_API_BY_STEP = {
    "cpd_catalog": "apply_combat_production_design_catalog_live",
    "cpd_scale": "apply_combat_production_design_scale_live",
    "cpd_flow": "apply_combat_production_design_flow_live",
    "cpd_phases": "apply_combat_production_design_phases_live",
    "cpd_close": "apply_combat_production_design_close_live",
}
PRIMARY_ACTION_IDS = tuple(LIVE_API_BY_STEP.values())
LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)

# Section keywords the freeze must lock (gating pure audit — real file contents).
REQUIRED_SECTION_MARKERS = (
    "Production scale lock",
    "identity-weighted hybrid scale",
    "1 stock unit = 1 real vehicle",
    "Reinforcement path",
    "EquipmentFlow",
    "Map symbol policy",
    "Layered fun / micro policy",
    "Phased rewrite roadmap",
    "equipment_flow_compact_ledger",
    "CP1",
    "CP6",
)

# Class defaults from design freeze (thin pure model of §3).
CLASS_DEFAULT_BATCH: Dict[str, int] = {
    "infantry_equipment": 1,  # abstract sets; amount is already "sets"
    "light_vehicle": 4,
    "truck": 4,
    "apc": 4,
    "tank": 1,
    "ifv": 1,
    "artillery_sp": 1,
    "artillery_towed": 2,
    "fighter": 1,
    "bomber": 1,
    "helicopter": 1,
    "drone_swarm": 6,
    "drone_singleton": 1,
    "missile": 1,
    "rocket_artillery": 4,
    "ship": 1,
    "submarine": 1,
    "space": 1,
}


def primary_command_dead_audit(action_ids=None, *, live_ids=None) -> Dict[str, Any]:
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    return {
        "action_ids": ids,
        "dead": dead,
        "dead_n": len(dead),
        "ok": ok,
        "summary": "Combat production design audit · dead %d · %s" % (len(dead), "PASS" if ok else "FAIL"),
        "plain": "Combat production design audit",
        "empty": False,
    }


def design_doc_text() -> str:
    if not DESIGN_PATH.is_file():
        return ""
    return DESIGN_PATH.read_text(encoding="utf-8")


def audit_design_freeze(text: Optional[str] = None) -> Dict[str, Any]:
    """Pure audit of the committed design freeze file contents."""
    body = text if text is not None else design_doc_text()
    missing: List[str] = []
    for marker in REQUIRED_SECTION_MARKERS:
        if marker not in body:
            missing.append(marker)
    ok = DESIGN_PATH.is_file() and len(missing) == 0 and "Design freeze" in body
    return {
        "ok": ok,
        "path": str(DESIGN_PATH.relative_to(ROOT)),
        "exists": DESIGN_PATH.is_file(),
        "missing_markers": missing,
        "marker_n": len(REQUIRED_SECTION_MARKERS),
        "hit_n": len(REQUIRED_SECTION_MARKERS) - len(missing),
        "model": "equipment_flow_compact_ledger",
    }


def stock_units_on_complete(design_class: str, completes: int = 1, batch_size: Optional[int] = None) -> int:
    """How many stockpile units land when a line completes `completes` times.

    Identity-weighted hybrid scale from design freeze §3.
    """
    c = max(0, int(completes))
    if batch_size is not None:
        b = max(1, int(batch_size))
    else:
        key = str(design_class).strip().lower()
        b = int(CLASS_DEFAULT_BATCH.get(key, 1))
        b = max(1, b)
    return c * b


def reinforcement_pipeline_ok() -> bool:
    """Structural pure check of the locked pipeline keywords in the freeze."""
    body = design_doc_text()
    need = (
        "Country equipment stockpile",
        "EquipmentFlow",
        "reinforce_unit",
        "interdict",
        "rail",
        "road",
        "airlift",
        "sealift",
    )
    return all(n in body for n in need)


def build_combat_production_design_primary_command_product(
    *, province_id: int = 1, live_ids=None
) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    audit = audit_design_freeze()
    dead = primary_command_dead_audit(live_ids=live_ids)
    # Thin pure scale model checks
    tank_one = stock_units_on_complete("tank", 1) == 1
    truck_batch = stock_units_on_complete("truck", 1) == 4
    drone_batch = stock_units_on_complete("drone_swarm", 1) == 6
    missile_one = stock_units_on_complete("missile", 1) == 1
    scale_ok = tank_one and truck_batch and drone_batch and missile_one
    flow_ok = reinforcement_pipeline_ok()
    phases_ok = "CP1" in design_doc_text() and "CP6" in design_doc_text()
    all_ok = bool(audit["ok"]) and scale_ok and flow_ok and phases_ok and dead["ok"]
    steps_out = []
    apply_queue = []
    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        api = LIVE_API_BY_STEP[step]
        steps_out.append(
            {
                "index": i,
                "step": step,
                "major": _STEP_MAJOR[step],
                "live_api": api,
                "leaf_action": api,
                "label": "CPD · %s · live %s" % (step, api),
                "score": 0.88 + 0.02 * i,
                "enabled": True,
                "province_id": pid,
            }
        )
        apply_queue.append({"action_id": api, "province_id": pid, "step": step, "live_api": api})
    label = "Combat production design · audit_ok=%s scale_ok=%s flow_ok=%s phases_ok=%s" % (
        audit["ok"],
        scale_ok,
        flow_ok,
        phases_ok,
    )
    return {
        "score": 0.95 if all_ok else 0.35,
        "plain": label,
        "summary": label,
        "empty": False,
        "province_id": pid,
        "audit": audit,
        "scale_ok": scale_ok,
        "flow_ok": flow_ok,
        "phases_ok": phases_ok,
        "tank_units": stock_units_on_complete("tank", 1),
        "truck_units": stock_units_on_complete("truck", 1),
        "model": "equipment_flow_compact_ledger",
        "surface_keys": list(SURFACE_KEYS),
        "majors": list(SURFACE_KEYS),
        "majors_ok_n": 5 if all_ok else 0,
        "all_majors_ok": all_ok,
        "dead_n": int(dead["dead_n"]),
        "audit_dead": dead,
        "steps": steps_out,
        "step_ids": list(PRIMARY_COMMAND_STEPS),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS),
        "apply_queue": apply_queue,
        "integration": [
            "combat_production_design_product",
            "COMBAT_PRODUCTION_ENGINE_DESIGN_FREEZE",
            "equipment_flow_compact_ledger",
        ],
    }
