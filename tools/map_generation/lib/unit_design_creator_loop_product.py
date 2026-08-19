"""Unit designer creator + type-based combat/move SFX.

Wiring: DomainDesignPopup symbol/strength, field extras, LandBattleSfx.key_for_unit,
MapRenderer._play_unit_loop_sfx. No new wav files — existing pack keys only.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
POPUP = ROOT / "scripts" / "ui" / "DomainDesignPopup.gd"
SFX = ROOT / "scripts" / "audio" / "LandBattleSfx.gd"
RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
LEADER = ROOT / "scripts" / "leaders" / "LeaderManager.gd"
HARNESS = ROOT / "scripts" / "core" / "HeadlessWorldAccurateUnitOrderLoopTest.gd"
GATES = ROOT / "tools" / "eoa_full_test_gates.sh"


def build_unit_design_creator_loop_product(*, check_wiring: bool = True) -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    wiring: Dict[str, bool] = {}
    pop = POPUP.read_text(encoding="utf-8") if POPUP.is_file() else ""
    sfx = SFX.read_text(encoding="utf-8") if SFX.is_file() else ""
    ren = RENDERER.read_text(encoding="utf-8") if RENDERER.is_file() else ""
    lm = LEADER.read_text(encoding="utf-8") if LEADER.is_file() else ""
    harness = HARNESS.read_text(encoding="utf-8") if HARNESS.is_file() else ""
    gates = GATES.read_text(encoding="utf-8") if GATES.is_file() else ""

    def _ok(name: str, cond: bool) -> None:
        wiring[name] = cond
        (passes if cond else fails).append(name)

    _ok("symbol_picker", "DOMAIN_SYMBOLS" in pop and "_symbol_option" in pop)
    _ok("strength_slider", "_strength_slider" in pop and "visual_archetype" in pop)
    _ok("field_on_map_label", "Field on map" in pop)
    _ok("sfx_key_for_unit", "func key_for_unit" in sfx)
    _ok("existing_sfx_keys", all(k in sfx for k in ("KEY_ORDER_CONFIRM", "KEY_DAILY_CLASH")))
    _ok("play_unit_loop_sfx", "func _play_unit_loop_sfx" in ren)
    _ok("no_new_sfx_paths", '"confirm"' in ren and "Sound FX Starter Pack" in ren)
    _ok("combat_pulse", "CombatPulse" in ren)
    _ok("field_extras", "visual_archetype" in lm and "extras" in lm)
    _ok("harness_sfx", "key_for_unit" in harness)
    _ok("on_official_quick", "test_unit_design_creator_loop_product" in gates)

    ok = len(fails) == 0 if check_wiring else wiring.get("symbol_picker", False)
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "wiring": wiring,
        "pass": passes,
        "fail": fails,
        "summary": "unit_design_creator_loop · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "symbol_strength_field_type_sfx_existing_pack",
    }


def unit_design_creator_loop_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_unit_design_creator_loop_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
