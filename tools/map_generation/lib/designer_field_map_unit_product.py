"""Designer → fielded map unit (selectable chip + orders).

Wiring gate. Live proof is HeadlessWorldAccurateUnitOrderLoopTest
_test_designer_field. Dual apply_designer_field_live must call
LeaderManager.field_designed_unit so Field seed lands a chip.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
LEADER = ROOT / "scripts" / "leaders" / "LeaderManager.gd"
DESIGN = ROOT / "scripts" / "production" / "DesignManager.gd"
POPUP = ROOT / "scripts" / "ui" / "DomainDesignPopup.gd"
GAMEDATA = ROOT / "scripts" / "autoload" / "GameData.gd"
HARNESS = ROOT / "scripts" / "core" / "HeadlessWorldAccurateUnitOrderLoopTest.gd"
GATES = ROOT / "tools" / "eoa_full_test_gates.sh"


def build_designer_field_map_unit_product(*, check_wiring: bool = True) -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    wiring: Dict[str, bool] = {}

    lm = LEADER.read_text(encoding="utf-8") if LEADER.is_file() else ""
    dm = DESIGN.read_text(encoding="utf-8") if DESIGN.is_file() else ""
    pop = POPUP.read_text(encoding="utf-8") if POPUP.is_file() else ""
    gd = GAMEDATA.read_text(encoding="utf-8") if GAMEDATA.is_file() else ""
    harness = HARNESS.read_text(encoding="utf-8") if HARNESS.is_file() else ""
    gates = GATES.read_text(encoding="utf-8") if GATES.is_file() else ""

    field_fn = "func field_designed_unit" in lm
    wiring["leader_field_api"] = field_fn
    (passes if field_fn else fails).append("leader_field_api")

    wrap = "func field_design_on_map" in dm and "field_designed_unit" in dm
    wiring["design_manager_wrap"] = wrap
    (passes if wrap else fails).append("design_manager_wrap")

    popup_fields = "field_design_on_map" in pop
    wiring["designer_popup_fields"] = popup_fields
    (passes if popup_fields else fails).append("designer_popup_fields")

    live = "field_designed_unit" in gd and "func apply_designer_field_live" in gd
    wiring["field_seed_lands_chip"] = live
    (passes if live else fails).append("field_seed_lands_chip")

    harness_ok = "_test_designer_field" in harness and "field_designed_unit" in harness
    wiring["harness_designer_field"] = harness_ok
    (passes if harness_ok else fails).append("harness_designer_field")

    on_quick = "test_designer_field_map_unit_product" in gates
    wiring["on_official_quick"] = on_quick
    (passes if on_quick else fails).append("on_official_quick")

    ok = (len(fails) == 0) if check_wiring else field_fn
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "wiring": wiring,
        "pass": passes,
        "fail": fails,
        "summary": "designer_field_map_unit · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "designer_register_fields_selectable_map_unit",
    }


def designer_field_map_unit_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_designer_field_map_unit_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
