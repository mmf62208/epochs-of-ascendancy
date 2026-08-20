"""Unit-card combat strip — XP band / planning / entrench / last loss / strength.

Offline SOT for Director. Godot helper: scripts/ui/UnitCardCombatStrip.gd
Grep gate also checks LandBattleBubbleLayer CAS / planning chips.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional

ROOT = Path(__file__).resolve().parents[3]
STRIP_GD = ROOT / "scripts" / "ui" / "UnitCardCombatStrip.gd"
BUBBLE_GD = ROOT / "scripts" / "map" / "LandBattleBubbleLayer.gd"

# Formation.gd: Green 0–20 · trained 21–40 · regular 41–60 · seasoned 61–80 · veteran 81–100.
_XP_BANDS = (
    (20.0, "Green"),
    (40.0, "Trained"),
    (60.0, "Regular"),
    (80.0, "Seasoned"),
)
DEFAULT_XP = 48.0


def _as_map(formation: Any) -> Optional[Mapping[str, Any]]:
    if formation is None:
        return None
    if isinstance(formation, Mapping):
        return formation
    return None


def _as_percent(raw: Any) -> float:
    try:
        v = float(raw)
    except (TypeError, ValueError):
        return 0.0
    if v <= 1.5:
        v *= 100.0
    return max(0.0, min(150.0, v))


def xp_band(xp: Any) -> str:
    try:
        x = float(xp)
    except (TypeError, ValueError):
        x = DEFAULT_XP
    x = max(0.0, min(100.0, x))
    for hi, name in _XP_BANDS:
        if x <= hi:
            return name
    return "Veteran"


def lines_for(formation: Any) -> List[str]:
    data = _as_map(formation)
    if data is None:
        return []
    xp = DEFAULT_XP
    if "combat_experience" in data and data.get("combat_experience") is not None:
        try:
            xp = float(data.get("combat_experience"))
        except (TypeError, ValueError):
            xp = DEFAULT_XP
    out: List[str] = ["XP %s" % xp_band(xp)]
    if "planning" in data:
        out.append("Planning %.0f%%" % _as_percent(data.get("planning")))
    if "entrenchment" in data:
        out.append("Entrenchment %.0f%%" % _as_percent(data.get("entrenchment")))
    if "last_equip_loss_plain" in data:
        loss = str(data.get("last_equip_loss_plain") or "").strip()
        if loss:
            out.append(loss)
    str_v = 1.0
    if "strength" in data and data.get("strength") is not None:
        try:
            str_v = float(data.get("strength"))
        except (TypeError, ValueError):
            str_v = 1.0
    out.append("Strength %.0f%%" % _as_percent(str_v))
    if bool(data.get("is_training")):
        try:
            prog = float(data.get("training_progress", 0.0) or 0.0)
        except (TypeError, ValueError):
            prog = 0.0
        try:
            need = float(data.get("organize_days", data.get("train_days", 14.0)) or 14.0)
        except (TypeError, ValueError):
            need = 14.0
        mode = str(data.get("organize_mode", "new") or "new").strip().lower()
        if mode in ("refit", "convert"):
            out.append("Refit %d/%dd · org/str recovering" % (int(prog), int(need)))
        else:
            out.append("Training %d/%dd · not combat-ready" % (int(prog), int(need)))
    return out


def bbcode_for(formation: Any) -> str:
    return "\n".join(lines_for(formation))


def day_label_extras(battle: Any) -> str:
    """Cheap CAS / planning chips for LandBattleBubbleLayer day label."""
    if not isinstance(battle, Mapping):
        return ""
    bits: List[str] = []
    try:
        cas_att = float(battle.get("cas_att", 0.0) or 0.0)
    except (TypeError, ValueError):
        cas_att = 0.0
    try:
        cas_def = float(battle.get("cas_def", 0.0) or 0.0)
    except (TypeError, ValueError):
        cas_def = 0.0
    if cas_att > 0.0 or cas_def > 0.0:
        bits.append("CAS")
    if bool(battle.get("planning_used", False)):
        bits.append("P")
    return " ".join(bits)


def _gd_has_strip(src: str) -> bool:
    if "class_name UnitCardCombatStrip" not in src:
        return False
    if "func lines_for" not in src:
        return False
    if "combat_experience" not in src:
        return False
    if "last_equip_loss_plain" not in src and "Planning" not in src:
        return False
    return True


def _gd_has_bubble_chips(src: str) -> bool:
    if not src:
        return False
    if "CAS" not in src:
        return False
    if "cas_att" not in src and "cas_def" not in src:
        return False
    if "planning_used" not in src:
        return False
    return True


def build_unit_card_combat_strip_product(*, check_wiring: bool = True) -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    wiring: Dict[str, bool] = {}

    bare = {"strength": 1.0}
    bare_lines = lines_for(bare)
    bare_ok = bare_lines == ["XP Regular", "Strength 100%"]
    wiring["default_xp_strength"] = bare_ok
    (passes if bare_ok else fails).append("default_xp_strength")

    bands_ok = (
        xp_band(10.0) == "Green"
        and xp_band(30.0) == "Trained"
        and xp_band(50.0) == "Regular"
        and xp_band(70.0) == "Seasoned"
        and xp_band(90.0) == "Veteran"
        and xp_band(20.0) == "Green"
        and xp_band(21.0) == "Trained"
    )
    wiring["xp_bands"] = bands_ok
    (passes if bands_ok else fails).append("xp_bands")

    full = {
        "combat_experience": 85.0,
        "planning": 0.45,
        "entrenchment": 0.30,
        "last_equip_loss_plain": "Lost 12 rifles",
        "strength": 0.87,
    }
    full_lines = lines_for(full)
    expected_full = [
        "XP Veteran",
        "Planning 45%",
        "Entrenchment 30%",
        "Lost 12 rifles",
        "Strength 87%",
    ]
    full_ok = full_lines == expected_full
    wiring["full_strip"] = full_ok
    (passes if full_ok else fails).append("full_strip")

    empty_ok = lines_for(None) == []
    wiring["null_empty"] = empty_ok
    (passes if empty_ok else fails).append("null_empty")

    cas_ok = day_label_extras({"cas_att": 1.2, "cas_def": 0.0}) == "CAS"
    plan_ok = day_label_extras({"planning_used": True}) == "P"
    both_ok = day_label_extras({"cas_def": 0.4, "planning_used": 1}) == "CAS P"
    none_ok = day_label_extras({"cas_att": 0.0, "cas_def": 0.0}) == ""
    extras_ok = cas_ok and plan_ok and both_ok and none_ok
    wiring["day_label_extras"] = extras_ok
    (passes if extras_ok else fails).append("day_label_extras")

    if check_wiring:
        gd = STRIP_GD.read_text(encoding="utf-8") if STRIP_GD.is_file() else ""
        strip_ok = _gd_has_strip(gd)
        wiring["gd_strip"] = strip_ok
        (passes if strip_ok else fails).append("gd_strip")

        bubble = BUBBLE_GD.read_text(encoding="utf-8") if BUBBLE_GD.is_file() else ""
        bubble_ok = _gd_has_bubble_chips(bubble)
        wiring["gd_bubble_cas_p"] = bubble_ok
        (passes if bubble_ok else fails).append("gd_bubble_cas_p")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "wiring": wiring,
        "lines_sample": full_lines,
        "summary": "unit_card_combat_strip · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "xp_band_planning_entrench_loss_strength",
        "director": {
            "call": "lines.append_array(UnitCardCombatStrip.lines_for(formation))",
            "site": "MapRenderer._show_unit_detail_popup after org/str/rdy/xp line",
        },
    }


def unit_card_combat_strip_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_unit_card_combat_strip_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
