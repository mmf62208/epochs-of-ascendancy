"""Multi-day land battle equipment attrition — visible, honest daily write-off.

Offline SOT for CombatLoop. Godot helper: scripts/combat/LandBattleAttrition.gd
Winner-lean daily severity is lighter than loser/even; empty stock formats as
"no stock to lose". ProductionManager.ensure_demo_combat_stock seeds a small
on-hand pack so apply_combat_equipment_loss is not a no-op on unequipped units.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Tuple

ROOT = Path(__file__).resolve().parents[3]
ATTRITION_GD = ROOT / "scripts" / "combat" / "LandBattleAttrition.gd"
PM_GD = ROOT / "scripts" / "autoload" / "ProductionManager.gd"

WINNER_LEAN = 0.06
LOSER_EVEN = 0.10
DAY3_EXTRA = 0.01
SEV_MIN = 0.05
SEV_MAX = 0.22

MINUS = "\u2212"  # −
DOT = " \u00b7 "  # ·
NO_STOCK = "no stock to lose"

_GD_FUNCS = (
    "daily_severity",
    "format_loss_plain",
    "apply_daily_to_formation",
)

# (tokens matched against equipment id, display name)
_SHORT_NAMES: Tuple[Tuple[Tuple[str, ...], str], ...] = (
    (("infantry_equipment", "infantry", "small_arms", "rifle", "rifles"), "rifles"),
    (("truck", "trucks", "motorized", "motorized_equipment"), "trucks"),
    (("support_equipment", "support"), "support"),
    (("artillery_equipment", "artillery"), "artillery"),
    (("tank", "tanks", "armor", "armour", "panzer"), "tanks"),
)
_PREFERRED = ("rifles", "support", "trucks", "artillery", "tanks")


def daily_severity(*, is_winner_lean: bool, days_elapsed: int) -> float:
    """Winner lean 0.06, loser/even 0.10; +0.01 per day after day 3; clamp 0.05–0.22."""
    base = WINNER_LEAN if bool(is_winner_lean) else LOSER_EVEN
    extra = max(0, int(days_elapsed) - 3) * DAY3_EXTRA
    return max(SEV_MIN, min(SEV_MAX, float(base + extra)))


def _short_name(equipment_id: Any) -> str:
    key = str(equipment_id or "").strip().lower()
    if not key:
        return "equip"
    for tokens, name in _SHORT_NAMES:
        if key in tokens or any(tok in key for tok in tokens):
            return name
    return key.replace("_", " ")


def format_loss_plain(removed: Any) -> str:
    """'rifles −12 · trucks −2' or 'no stock to lose'."""
    if not isinstance(removed, Mapping) or not removed:
        return NO_STOCK
    rows: List[Tuple[str, int]] = []
    for raw_id, raw_n in removed.items():
        try:
            n = int(raw_n)
        except (TypeError, ValueError):
            continue
        if n <= 0:
            continue
        rows.append((_short_name(raw_id), n))
    if not rows:
        return NO_STOCK
    rows.sort(
        key=lambda row: (
            _PREFERRED.index(row[0]) if row[0] in _PREFERRED else 99,
            row[0],
        )
    )
    return DOT.join("%s %s%d" % (name, MINUS, n) for name, n in rows)


def _gd_has_helpers(src: str) -> bool:
    if "class_name LandBattleAttrition" not in src:
        return False
    return all("static func %s" % name in src for name in _GD_FUNCS)


def _gd_calls_apply_loss(src: str) -> bool:
    return "apply_combat_equipment_loss" in src and "apply_daily_to_formation" in src


def _pm_has_demo_stock(src: str) -> bool:
    return "func ensure_demo_combat_stock" in src


def build_land_battle_attrition_product() -> Dict[str, Any]:
    """Fixtures + GD greps. ok iff loser>winner, empty format, three GD funcs."""
    passes: List[str] = []
    fails: List[str] = []

    win_d1 = daily_severity(is_winner_lean=True, days_elapsed=1)
    lose_d1 = daily_severity(is_winner_lean=False, days_elapsed=1)
    even_d1 = daily_severity(is_winner_lean=False, days_elapsed=1)
    win_d4 = daily_severity(is_winner_lean=True, days_elapsed=4)
    lose_d4 = daily_severity(is_winner_lean=False, days_elapsed=4)
    lose_late = daily_severity(is_winner_lean=False, days_elapsed=40)

    if lose_d1 > win_d1 and even_d1 > win_d1:
        passes.append("loser_severity_gt_winner")
    else:
        fails.append("loser_severity_gt_winner")

    if abs(win_d1 - WINNER_LEAN) < 1e-9 and abs(lose_d1 - LOSER_EVEN) < 1e-9:
        passes.append("day1_bases")
    else:
        fails.append("day1_bases")

    if win_d4 > win_d1 and lose_d4 > lose_d1:
        passes.append("after_day3_escalates")
    else:
        fails.append("after_day3_escalates")

    if SEV_MIN - 1e-9 <= lose_late <= SEV_MAX + 1e-9 and lose_late >= SEV_MAX - 1e-9:
        passes.append("severity_clamped")
    else:
        fails.append("severity_clamped")

    empty_plain = format_loss_plain({})
    if "no stock" in empty_plain:
        passes.append("empty_format_no_stock")
    else:
        fails.append("empty_format_no_stock")

    sample_plain = format_loss_plain({"infantry_equipment": 12, "trucks": 2})
    if "rifles" in sample_plain and MINUS in sample_plain and "12" in sample_plain:
        if "trucks" in sample_plain and "2" in sample_plain:
            passes.append("format_rifles_trucks")
        else:
            fails.append("format_rifles_trucks")
    else:
        fails.append("format_rifles_trucks")

    gd_src = ATTRITION_GD.read_text(encoding="utf-8") if ATTRITION_GD.is_file() else ""
    if _gd_has_helpers(gd_src):
        passes.append("gd_helpers")
    else:
        fails.append("gd_helpers")

    if _gd_calls_apply_loss(gd_src):
        passes.append("gd_calls_apply_loss")
    else:
        fails.append("gd_calls_apply_loss")

    pm_src = PM_GD.read_text(encoding="utf-8") if PM_GD.is_file() else ""
    if _pm_has_demo_stock(pm_src):
        passes.append("pm_ensure_demo_combat_stock")
    else:
        fails.append("pm_ensure_demo_combat_stock")

    ok = len(fails) == 0
    fixtures: Dict[str, Any] = {
        "winner_day1": win_d1,
        "loser_day1": lose_d1,
        "winner_day4": win_d4,
        "loser_day4": lose_d4,
        "loser_day40": lose_late,
        "empty_plain": empty_plain,
        "sample_plain": sample_plain,
    }
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "fixtures": fixtures,
        "summary": "land_battle_attrition · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "winner_0.06_loser_0.10_plus_0.01_after_day3_clamp_0.05_0.22",
        "combatloop_seed": "ProductionManager.ensure_demo_combat_stock(fid, tag)",
        "integration": [
            "land_battle_attrition_product",
            "LandBattleAttrition.gd",
            "ProductionManager.ensure_demo_combat_stock",
        ],
    }


def land_battle_attrition_integrity() -> Dict[str, Any]:
    p = build_land_battle_attrition_product()
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
