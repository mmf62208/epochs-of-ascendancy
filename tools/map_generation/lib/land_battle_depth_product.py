"""Land battle depth SOT — daily equip, CAS, planning, trench, XP, recovery.

Offline product for CombatLoop. Godot: BattleManager + TimeManager + Formation.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
BM_GD = ROOT / "scripts" / "combat" / "BattleManager.gd"
TM_GD = ROOT / "scripts" / "autoload" / "TimeManager.gd"
FM_GD = ROOT / "scripts" / "formations" / "Formation.gd"

ATT_EQUIP_SEV = 0.08
DEF_EQUIP_SEV = 0.10
LOSER_EQUIP_BUMP = 0.02
PLANNING_MULT = 0.25
TRENCH_MULT = 0.20
CAS_BASE = 25.0
CAS_MISSION_MULT = 1.2


def planning_bonus(planning: float) -> float:
    """First-day attack multiplier: 1 + 0.25 * planning. planning_bonus(0.8) == 1.2."""
    p = max(0.0, min(1.0, float(planning)))
    return 1.0 + PLANNING_MULT * p


def trench_bonus(entrenchment: float) -> float:
    """Defender power multiplier: 1 + 0.20 * entrenchment. trench_bonus(1.0) == 1.2."""
    e = max(0.0, min(1.0, float(entrenchment)))
    return 1.0 + TRENCH_MULT * e


def daily_equip_severity(side: str, lean: str) -> float:
    """~0.08 attacker / 0.10 defender; loser-lean slightly higher."""
    s = str(side or "").strip().lower()
    L = str(lean or "even").strip().lower()
    if s not in ("attacker", "defender"):
        s = "attacker"
    if L not in ("attacker", "defender", "even"):
        L = "even"
    base = ATT_EQUIP_SEV if s == "attacker" else DEF_EQUIP_SEV
    is_loser = (s == "attacker" and L == "defender") or (
        s == "defender" and L == "attacker"
    )
    if is_loser:
        return float(base + LOSER_EQUIP_BUMP)
    if L == "defender" and s == "defender":
        # Winner-lean defender sits just under loser-attacker (0.10).
        return float(DEF_EQUIP_SEV - LOSER_EQUIP_BUMP)
    return float(base)


def cas_wing_power(readiness: float, mission: str) -> float:
    rdy = max(0.0, float(readiness))
    m = str(mission or "").strip().upper()
    if m not in ("CAS", "CLOSE_AIR_SUPPORT", "INTERDICTION", "AIR_SUPERIORITY"):
        return 0.0
    mult = CAS_MISSION_MULT if m in ("CAS", "CLOSE_AIR_SUPPORT") else 1.0
    return float(CAS_BASE * rdy * mult)


def build_land_battle_depth_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []

    pb = planning_bonus(0.8)
    if abs(pb - 1.2) < 1e-9:
        passes.append("planning_bonus_0.8")
    else:
        fails.append("planning_bonus_0.8")

    tb = trench_bonus(1.0)
    if abs(tb - 1.2) < 1e-9:
        passes.append("trench_bonus_1.0")
    else:
        fails.append("trench_bonus_1.0")

    att_win = daily_equip_severity("attacker", "attacker")
    def_lose = daily_equip_severity("defender", "attacker")
    att_lose = daily_equip_severity("attacker", "defender")
    def_win = daily_equip_severity("defender", "defender")
    if def_lose > att_win and att_lose > def_win:
        passes.append("daily_equip_severity_loser_gt_winner")
    else:
        fails.append("daily_equip_severity_loser_gt_winner")

    even_att = daily_equip_severity("attacker", "even")
    even_def = daily_equip_severity("defender", "even")
    if abs(even_att - ATT_EQUIP_SEV) < 1e-9 and abs(even_def - DEF_EQUIP_SEV) < 1e-9:
        passes.append("even_equip_0.08_0.10")
    else:
        fails.append("even_equip_0.08_0.10")

    if cas_wing_power(1.0, "CAS") == 30.0 and cas_wing_power(1.0, "AIR_SUPERIORITY") == 25.0:
        passes.append("cas_wing_power")
    else:
        fails.append("cas_wing_power")

    bm = BM_GD.read_text(encoding="utf-8") if BM_GD.is_file() else ""
    tm = TM_GD.read_text(encoding="utf-8") if TM_GD.is_file() else ""
    fm = FM_GD.read_text(encoding="utf-8") if FM_GD.is_file() else ""

    if "apply_combat_equipment_loss" in bm:
        passes.append("bm_apply_combat_equipment_loss")
    else:
        fails.append("bm_apply_combat_equipment_loss")

    if "cas_att" in bm or "_land_battle_cas" in bm:
        passes.append("bm_cas_att_or_helper")
    else:
        fails.append("bm_cas_att_or_helper")

    plan_src = bm + "\n" + fm
    if "planning" in plan_src and "entrenchment" in plan_src:
        passes.append("planning_and_entrenchment")
    else:
        fails.append("planning_and_entrenchment")

    if "_tick_out_of_combat_recovery" in tm:
        passes.append("tm_out_of_combat_recovery")
    else:
        fails.append("tm_out_of_combat_recovery")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "summary": "land_battle_depth · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "daily_equip_cas_planning_trench_xp_recovery",
        "fixtures": {
            "planning_bonus_0.8": pb,
            "trench_bonus_1.0": tb,
            "equip_att_win": att_win,
            "equip_def_lose": def_lose,
            "equip_att_lose": att_lose,
            "equip_def_win": def_win,
            "equip_even_att": even_att,
            "equip_even_def": even_def,
        },
    }


def land_battle_depth_integrity() -> Dict[str, Any]:
    p = build_land_battle_depth_product()
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
