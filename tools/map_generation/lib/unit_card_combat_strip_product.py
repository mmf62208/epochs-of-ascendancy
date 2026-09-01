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
    ft = str(data.get("formation_type") or "").strip().lower()
    if ft in ("air_wing", "air_squadron", "air_group"):
        mission = str(data.get("current_air_mission") or "CAS").strip() or "CAS"
        try:
            rid = int(data.get("assigned_region_id") or 0)
        except (TypeError, ValueError):
            rid = 0
        rng = str(data.get("air_range_config") or "COMBAT_LOAD").strip() or "COMBAT_LOAD"
        try:
            fuel_pct = float(data.get("fuel_level") if data.get("fuel_level") is not None else 1.0)
        except (TypeError, ValueError):
            fuel_pct = 1.0
        if fuel_pct <= 1.5:
            fuel_pct *= 100.0
        out.append("%s · region %d · range %s · fuel %.0f%%" % (mission, rid, rng, fuel_pct))
        if rid > 0:
            out.append("CAS assigned · Unassign")
        else:
            out.append("CAS unassigned · Assign")
    fold = fill_toe_fold_line(data)
    if fold:
        out.append(fold)
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
    clog = data.get("combat_log")
    if isinstance(clog, (list, tuple)):
        for raw in list(clog)[-3:]:
            if not isinstance(raw, Mapping):
                continue
            date = str(raw.get("date") or "").strip()
            outcome = str(raw.get("outcome") or raw.get("result") or "").strip()
            bits = [b for b in (date, outcome) if b]
            if bits:
                out.append(" ".join(bits))
    return out


def _fill_percent_line(data: Mapping[str, Any]) -> str:
    if "toe_fill" not in data and data.get("fill_percent") is None:
        return ""
    try:
        fill_pct = float(data.get("toe_fill") if data.get("toe_fill") is not None else 0.0) * 100.0
    except (TypeError, ValueError):
        fill_pct = 0.0
    if data.get("fill_percent") is not None and "toe_fill" not in data:
        try:
            fill_pct = float(data.get("fill_percent") or 0.0)
        except (TypeError, ValueError):
            fill_pct = 0.0
    return "Fill %.0f%%" % fill_pct


def _toe_bits(data: Mapping[str, Any], limit: int = 4) -> List[str]:
    equip = data.get("equipment")
    if not isinstance(equip, Mapping):
        equip = data.get("toe") if isinstance(data.get("toe"), Mapping) else {}
    if not isinstance(equip, Mapping) or not equip:
        return []
    rows: List[tuple] = []
    for k, raw in equip.items():
        try:
            n = int(raw)
        except (TypeError, ValueError):
            continue
        if n <= 0:
            continue
        short = str(k).replace("_equipment", "").replace("_", " ").strip() or str(k)
        rows.append((short, n))
    rows.sort(key=lambda r: r[0])
    return ["%s %d" % (name, n) for name, n in rows[: max(1, int(limit))]]


def fill_toe_fold_line(formation: Any) -> str:
    """Card-fold extra: Fill NN% · TOE infantry 80 · tanks 12 (no Speed/Width)."""
    data = _as_map(formation)
    if data is None:
        return ""
    fill_s = _fill_percent_line(data)
    bits = _toe_bits(data)
    if not fill_s and not bits:
        return ""
    if not bits:
        return fill_s
    toe_s = "TOE " + " · ".join(bits)
    if not fill_s:
        return toe_s
    return "%s · %s" % (fill_s, toe_s)


def tooltip_lines_for(formation: Any) -> List[str]:
    """Speed / Armor / Men and Width / Fuel — parked off the fold."""
    data = _as_map(formation)
    if data is None:
        return []
    out: List[str] = []
    has_comp = bool(data.get("has_composition")) or any(
        k in data for k in ("speed", "armor", "width", "manpower", "fuel_level")
    )
    if has_comp and any(k in data for k in ("speed", "armor", "manpower", "width", "fuel_level")):
        try:
            str_v = float(data.get("strength") if data.get("strength") is not None else 1.0)
        except (TypeError, ValueError):
            str_v = 1.0
        try:
            toe = int(data.get("manpower") or 0)
        except (TypeError, ValueError):
            toe = 0
        left = max(0, int(round(float(toe) * str_v)))
        try:
            speed = float(data.get("speed") if data.get("speed") is not None else 1.0)
        except (TypeError, ValueError):
            speed = 1.0
        try:
            armor = float(data.get("armor") or 0.0)
        except (TypeError, ValueError):
            armor = 0.0
        if armor <= 1.5:
            armor_pct = armor * 100.0
        else:
            armor_pct = armor
        try:
            width = float(data.get("width") if data.get("width") is not None else 2.0)
        except (TypeError, ValueError):
            width = 2.0
        try:
            fuel = float(data.get("fuel_level") if data.get("fuel_level") is not None else 1.0)
        except (TypeError, ValueError):
            fuel = 1.0
        if fuel <= 1.5:
            fuel *= 100.0
        out.append("Speed %.1f · Armor %.0f%% · Men %d/%d" % (speed, armor_pct, left, toe))
        out.append("Width %.0f · Fuel %.0f%%" % (width, fuel))
    rifles = int(data.get("stock_rifles") or 0)
    trucks = int(data.get("stock_trucks") or 0)
    if rifles > 0 or trucks > 0:
        out.append("stock rifles %d · trucks %d" % (rifles, trucks))
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

    stock = lines_for({"toe_fill": 0.28, "stock_rifles": 12, "stock_trucks": 4})
    stock_ok = any(x.startswith("Fill") and "28%" in x for x in stock)
    wiring["stockpile_toe_line"] = stock_ok
    (passes if stock_ok else fails).append("stockpile_toe_line")

    land_fold = {
        "strength": 1.0,
        "toe_fill": 0.80,
        "equipment": {"infantry_equipment": 80, "tanks": 12},
        "speed": 4.0,
        "armor": 0.12,
        "manpower": 10000,
        "width": 9.0,
        "fuel_level": 0.7,
        "stock_rifles": 40,
        "stock_trucks": 6,
    }
    fold_lines = lines_for(land_fold)
    fold_join = "\n".join(fold_lines)
    fill_idx = next((i for i, ln in enumerate(fold_lines) if "Fill" in ln and "%" in ln), -1)
    toe_idx = next((i for i, ln in enumerate(fold_lines) if "TOE" in ln), -1)
    speed_in_fold = any("Speed" in ln for ln in fold_lines)
    width_in_fold = any(ln.startswith("Width") or "Width " in ln and "Fuel" in ln for ln in fold_lines)
    fold_ok = (
        fill_idx >= 0
        and toe_idx >= 0
        and fill_idx <= toe_idx
        and "80%" in fold_join
        and "infantry 80" in fold_join
        and "tanks 12" in fold_join
        and not speed_in_fold
        and not width_in_fold
    )
    wiring["fold_fill_toe_before_stats"] = fold_ok
    (passes if fold_ok else fails).append("fold_fill_toe_before_stats")
    tips = tooltip_lines_for(land_fold)
    tip_join = "\n".join(tips)
    tip_ok = (
        any("Speed" in ln for ln in tips)
        and any("Width" in ln and "Fuel" in ln for ln in tips)
        and "Armor" in tip_join
        and "stock rifles" in tip_join
    )
    wiring["tooltip_speed_width"] = tip_ok
    (passes if tip_ok else fails).append("tooltip_speed_width")

    if check_wiring:
        gd = STRIP_GD.read_text(encoding="utf-8") if STRIP_GD.is_file() else ""
        strip_ok = _gd_has_strip(gd)
        wiring["gd_strip"] = strip_ok
        (passes if strip_ok else fails).append("gd_strip")
        fill_ok = (
            "_stockpile_toe_line" in gd
            and "unit_toe_fill_ratio" in gd
            and "_fill_toe_fold_line" in gd
            and "Fill %.0f%%" in gd
        )
        wiring["gd_stockpile_toe"] = fill_ok
        (passes if fill_ok else fails).append("gd_stockpile_toe")
        # Fold builder must not emit Speed/Width; those belong on tooltip_lines_for.
        fn = gd
        i_lines = fn.find("func lines_for")
        i_tip = fn.find("func tooltip_lines_for")
        i_next = fn.find("\nstatic func ", i_lines + 1) if i_lines >= 0 else -1
        lines_fn = fn[i_lines:i_next] if i_lines >= 0 and i_next > i_lines else ""
        tip_fn = fn[i_tip : i_tip + 1800] if i_tip >= 0 else ""
        gd_fold_ok = (
            "Fill %.0f%%" in gd
            and "TOE " in gd
            and "Speed %.1f" not in lines_fn
            and "Width %.0f" not in lines_fn
            and "Speed %.1f" in tip_fn
            and "Width %.0f" in tip_fn
            and "func tooltip_lines_for" in gd
        )
        wiring["gd_fold_fill_toe_tooltip_stats"] = gd_fold_ok
        (passes if gd_fold_ok else fails).append("gd_fold_fill_toe_tooltip_stats")
        cas_line_ok = "CAS assigned · Unassign" in gd and "CAS unassigned · Assign" in gd
        wiring["gd_cas_assign_line"] = cas_line_ok
        (passes if cas_line_ok else fails).append("gd_cas_assign_line")

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
