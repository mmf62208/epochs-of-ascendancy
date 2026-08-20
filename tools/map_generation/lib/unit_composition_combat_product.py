"""Unit composition — battalions, support, fuel/width/pierce, combat losses.

Pick infantry battalions, mount with motorcycle / truck / halftrack, add
tank battalions and support (artillery, recon, engineers, AT, AA). Speed
is the min of remaining elements (mounted infantry/guns ride). Combat
uses armor, pierce (hard vs defender armor), width, fuel, and TOE
shortage. Daily fight writes manpower AND equipment for both sides.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
POWER = ROOT / "scripts" / "combat" / "LandCombatPower.gd"
POPUP = ROOT / "scripts" / "ui" / "DomainDesignPopup.gd"
ATTR = ROOT / "scripts" / "combat" / "LandBattleAttrition.gd"
BM = ROOT / "scripts" / "combat" / "BattleManager.gd"
MV = ROOT / "scripts" / "formations" / "FormationMovement.gd"
STRIP = ROOT / "scripts" / "ui" / "UnitCardCombatStrip.gd"
LM = ROOT / "scripts" / "leaders" / "LeaderManager.gd"
HARNESS = ROOT / "scripts" / "core" / "HeadlessWorldAccurateUnitOrderLoopTest.gd"
GATES = ROOT / "tools" / "eoa_full_test_gates.sh"
TM = ROOT / "scripts" / "autoload" / "TimeManager.gd"

ELEMENTS: Dict[str, Dict[str, Any]] = {
    "infantry": {
        "speed": 1.0,
        "armor": 0.0,
        "defense": 1.0,
        "manpower": 3000,
        "mounted": False,
        "soft": 1.0,
        "hard": 0.15,
        "breakthrough": 0.40,
        "hardness": 0.0,
        "fuel": 0.0,
        "supply": 0.8,
        "width": 2.0,
        "equip": {"infantry_equipment": 80},
    },
    "motorcycle": {
        "speed": 2.4,
        "armor": 0.0,
        "defense": 0.65,
        "manpower": 400,
        "mounted": True,
        "soft": 0.85,
        "hard": 0.10,
        "breakthrough": 0.50,
        "hardness": 0.0,
        "fuel": 0.04,
        "supply": 0.4,
        "width": 0.0,
        "equip": {"motorcycles": 40},
    },
    "truck": {
        "speed": 2.0,
        "armor": 0.05,
        "defense": 0.75,
        "manpower": 200,
        "mounted": True,
        "soft": 1.0,
        "hard": 0.10,
        "breakthrough": 0.60,
        "hardness": 0.05,
        "fuel": 0.06,
        "supply": 0.5,
        "width": 0.0,
        "equip": {"trucks": 24},
    },
    "halftrack": {
        "speed": 1.6,
        "armor": 0.35,
        "defense": 1.20,
        "manpower": 280,
        "mounted": True,
        "soft": 1.05,
        "hard": 0.35,
        "breakthrough": 0.80,
        "hardness": 0.35,
        "fuel": 0.08,
        "supply": 0.6,
        "width": 0.0,
        "equip": {"halftracks": 16},
    },
    "artillery": {
        "speed": 0.85,
        "armor": 0.05,
        "defense": 0.80,
        "manpower": 350,
        "mounted": False,
        "soft": 1.40,
        "hard": 0.45,
        "breakthrough": 0.20,
        "hardness": 0.05,
        "fuel": 0.02,
        "supply": 0.5,
        "width": 0.0,
        "equip": {"artillery": 12},
    },
    "recon": {
        "speed": 1.20,
        "armor": 0.0,
        "defense": 0.40,
        "manpower": 120,
        "mounted": False,
        "soft": 0.35,
        "hard": 0.05,
        "breakthrough": 0.30,
        "hardness": 0.0,
        "fuel": 0.03,
        "supply": 0.25,
        "width": 0.0,
        "equip": {"recon_equipment": 12},
    },
    "engineer": {
        "speed": 1.0,
        "armor": 0.0,
        "defense": 0.90,
        "manpower": 250,
        "mounted": False,
        "soft": 0.25,
        "hard": 0.10,
        "breakthrough": 0.30,
        "hardness": 0.0,
        "fuel": 0.02,
        "supply": 0.35,
        "width": 0.0,
        "equip": {"support_equipment": 20},
    },
    "anti_tank": {
        "speed": 0.90,
        "armor": 0.05,
        "defense": 0.60,
        "manpower": 220,
        "mounted": False,
        "soft": 0.20,
        "hard": 0.85,
        "breakthrough": 0.25,
        "hardness": 0.05,
        "fuel": 0.02,
        "supply": 0.40,
        "width": 0.0,
        "equip": {"anti_tank": 12},
    },
    "anti_air": {
        "speed": 0.90,
        "armor": 0.05,
        "defense": 0.50,
        "manpower": 200,
        "mounted": False,
        "soft": 0.40,
        "hard": 0.20,
        "breakthrough": 0.20,
        "hardness": 0.05,
        "fuel": 0.02,
        "supply": 0.35,
        "width": 0.0,
        "equip": {"anti_air": 12},
    },
    "light_tank": {
        "speed": 1.8,
        "armor": 0.45,
        "defense": 1.10,
        "manpower": 400,
        "mounted": False,
        "soft": 1.10,
        "hard": 0.70,
        "breakthrough": 1.40,
        "hardness": 0.55,
        "fuel": 0.12,
        "supply": 0.8,
        "width": 2.0,
        "equip": {"tanks": 12},
    },
    "medium_tank": {
        "speed": 1.5,
        "armor": 0.70,
        "defense": 1.30,
        "manpower": 500,
        "mounted": False,
        "soft": 1.20,
        "hard": 1.00,
        "breakthrough": 1.80,
        "hardness": 0.70,
        "fuel": 0.16,
        "supply": 1.0,
        "width": 3.0,
        "equip": {"tanks": 10},
    },
    "heavy_tank": {
        "speed": 1.2,
        "armor": 0.90,
        "defense": 1.50,
        "manpower": 520,
        "mounted": False,
        "soft": 1.15,
        "hard": 1.25,
        "breakthrough": 1.40,
        "hardness": 0.85,
        "fuel": 0.20,
        "supply": 1.2,
        "width": 3.0,
        "equip": {"tanks": 8},
    },
}

MOBILITY_IDS = ("foot", "motorcycle", "truck", "halftrack")
ARMOR_IDS = ("", "none", "light_tank", "medium_tank", "heavy_tank")
SUPPORT_IDS = ("artillery", "recon", "engineer", "anti_tank", "anti_air")
SKIP_SPEED_WHEN_MOUNTED = (
    "infantry",
    "artillery",
    "recon",
    "engineer",
    "anti_tank",
    "anti_air",
)
INFANTRY_BNS_MIN = 1
INFANTRY_BNS_MAX = 6
TANK_BNS_MAX = 3


def _el(eid: str) -> Optional[Dict[str, Any]]:
    return ELEMENTS.get(str(eid or "").strip().lower())


def _clamp_int(raw: Any, lo: int, hi: int, default: int) -> int:
    try:
        v = int(raw)
    except (TypeError, ValueError):
        v = int(default)
    return max(int(lo), min(int(hi), v))


def _split_supports(support: Any, extra: Any = None) -> List[str]:
    bits: List[str] = []
    for raw in (support, extra):
        if raw is None:
            continue
        if isinstance(raw, (list, tuple)):
            parts = [str(x) for x in raw]
        else:
            parts = str(raw).replace(";", ",").split(",")
        for p in parts:
            s = str(p or "").strip().lower()
            if s in ("", "none", "foot"):
                continue
            if s == "engineers":
                s = "engineer"
            if s in ("at", "anti-tank"):
                s = "anti_tank"
            if s in ("aa", "anti-air"):
                s = "anti_air"
            if s in ELEMENTS and s not in bits:
                bits.append(s)
    return bits


def compose(
    *,
    core: str = "infantry",
    mobility: str = "foot",
    armor: str = "",
    support: str = "",
    infantry_bns: int = 1,
    tank_bns: int = -1,
    supports: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Build a division from infantry battalions + transport + tanks + support."""
    core_id = str(core or "infantry").strip().lower() or "infantry"
    if core_id not in ELEMENTS:
        core_id = "infantry"
    mob_id = str(mobility or "foot").strip().lower() or "foot"
    arm_id = str(armor or "").strip().lower()
    if arm_id in ("none", "foot"):
        arm_id = ""
    inf_n = _clamp_int(infantry_bns, INFANTRY_BNS_MIN, INFANTRY_BNS_MAX, 1)
    if int(tank_bns) < 0:
        tank_n = 1 if arm_id in ELEMENTS else 0
    else:
        tank_n = _clamp_int(tank_bns, 0, TANK_BNS_MAX, 0)
        if tank_n <= 0:
            arm_id = ""
    if arm_id not in ELEMENTS:
        arm_id = ""
        tank_n = 0
    sup_list = _split_supports(support, supports)
    counts: Dict[str, int] = {core_id: inf_n}
    if mob_id in ELEMENTS:
        counts[mob_id] = inf_n
    if arm_id:
        counts[arm_id] = tank_n
    for sid in sup_list:
        counts[sid] = 1
    ids: List[str] = [core_id]
    for eid in (mob_id, arm_id):
        if eid in ELEMENTS and eid not in ids:
            ids.append(eid)
    for sid in sup_list:
        if sid not in ids:
            ids.append(sid)
    mounted = any(eid in MOBILITY_IDS[1:] for eid in ids)
    speeds: List[float] = []
    armor_v = 0.0
    defense = 0.0
    manpower = 0
    soft = 0.0
    hard = 0.0
    breakthrough = 0.0
    hardness_w = 0.0
    hardness_n = 0.0
    fuel_use = 0.0
    supply_need = 0.0
    width = 0.0
    equip: Dict[str, int] = {}
    for eid in ids:
        e = _el(eid)
        if not e:
            continue
        n = int(counts.get(eid, 1))
        if n <= 0:
            continue
        if not (mounted and eid in SKIP_SPEED_WHEN_MOUNTED):
            speeds.append(float(e["speed"]))
        armor_v = max(armor_v, float(e["armor"]))
        defense += float(e["defense"]) * n
        manpower += int(e["manpower"]) * n
        soft += float(e.get("soft", 1.0)) * n
        hard += float(e.get("hard", 0.0)) * n
        breakthrough += float(e.get("breakthrough", 0.0)) * n
        hardness_w += float(e.get("hardness", 0.0)) * n
        hardness_n += float(n)
        fuel_use += float(e.get("fuel", 0.0)) * n
        supply_need += float(e.get("supply", 0.0)) * n
        width += float(e.get("width", 0.0)) * n
        raw = e.get("equip") or {}
        if isinstance(raw, dict):
            for k, v in raw.items():
                equip[str(k)] = int(equip.get(str(k), 0)) + int(v) * n
    if not speeds:
        speeds = [1.0]
    speed = min(speeds)
    kind = "infantry"
    if arm_id:
        kind = "armor"
    elif mounted:
        kind = "motor"
    return {
        "ok": True,
        "ids": ids,
        "counts": counts,
        "mobility": mob_id,
        "armor_element": arm_id,
        "support": ",".join(sup_list),
        "supports": sup_list,
        "infantry_bns": inf_n,
        "tank_bns": tank_n,
        "speed": round(speed, 3),
        "armor": round(armor_v, 3),
        "defense": round(defense, 3),
        "manpower": manpower,
        "soft": round(soft, 3),
        "hard": round(hard, 3),
        "breakthrough": round(breakthrough, 3),
        "hardness": round((hardness_w / hardness_n) if hardness_n > 0 else 0.0, 3),
        "fuel_use": round(fuel_use, 3),
        "supply_need": round(supply_need, 3),
        "width": round(width, 3),
        "equipment": equip,
        "mounted": mounted,
        "kind": kind,
        "has_composition": mounted or bool(arm_id) or mob_id != "foot" or bool(sup_list) or inf_n != 1 or tank_n > 1,
    }


def remaining_men(toe: int, strength: float) -> int:
    return max(0, int(round(float(max(0, int(toe))) * max(0.0, min(1.0, float(strength))))))


def hardness_mix(soft: float, hard: float, defender_hardness: float) -> float:
    """Share of attack that lands: (1-hardness)*soft + hardness*hard."""
    try:
        s = float(soft)
    except (TypeError, ValueError):
        s = 0.0
    try:
        h_atk = float(hard)
    except (TypeError, ValueError):
        h_atk = 0.0
    try:
        h = max(0.0, min(1.0, float(defender_hardness)))
    except (TypeError, ValueError):
        h = 0.0
    return round((1.0 - h) * s + h * h_atk, 4)


def absorb_mult(role: str, breakthrough: float, defense: float) -> float:
    """Attacker uses breakthrough; defender uses defense. Extra absorb = more power kept."""
    r = str(role or "").strip().lower()
    try:
        bt = max(0.0, float(breakthrough))
    except (TypeError, ValueError):
        bt = 0.0
    try:
        df = max(0.0, float(defense))
    except (TypeError, ValueError):
        df = 0.0
    if r in ("defend", "defender", "defense", "def"):
        return round(max(0.75, min(1.40, 0.75 + 0.18 * df)), 4)
    return round(max(0.75, min(1.40, 0.78 + 0.16 * bt)), 4)


def pierce_mult(hard: float, defender_armor: float) -> float:
    """Attacker hard attack vs defender armor. <1 if they bounce, >1 if they pierce."""
    try:
        h = float(hard)
    except (TypeError, ValueError):
        h = 0.0
    try:
        a = float(defender_armor)
    except (TypeError, ValueError):
        a = 0.0
    return round(max(0.70, min(1.35, 1.0 + 0.18 * (h - a))), 4)


def shortage_mult(stock: Mapping[str, Any] | None, toe: Mapping[str, Any] | None) -> float:
    """On-hand vs TOE fill. Empty stock (untracked) is 1.0 so unseeded units aren't nerfed."""
    if not isinstance(toe, Mapping) or not toe:
        return 1.0
    need = 0
    have = 0
    tracked = isinstance(stock, Mapping) and bool(stock)
    for k, raw in toe.items():
        try:
            n = int(raw)
        except (TypeError, ValueError):
            continue
        if n <= 0:
            continue
        need += n
        if tracked:
            try:
                have += min(n, max(0, int(stock.get(k, 0))))
            except (TypeError, ValueError):
                pass
    if need <= 0 or not tracked:
        return 1.0
    ratio = float(have) / float(need)
    return round(max(0.55, min(1.0, 0.55 + 0.45 * ratio)), 4)


def fuel_speed_mult(fuel_level: float, fuel_use: float) -> float:
    try:
        use = float(fuel_use)
    except (TypeError, ValueError):
        use = 0.0
    if use <= 1e-9:
        return 1.0
    try:
        f = max(0.0, min(1.0, float(fuel_level)))
    except (TypeError, ValueError):
        f = 1.0
    if f >= 0.35:
        return 1.0
    return round(0.45 + 0.55 * (f / 0.35), 4)


def fuel_power_mult(fuel_level: float, fuel_use: float) -> float:
    try:
        use = float(fuel_use)
    except (TypeError, ValueError):
        use = 0.0
    if use <= 1e-9:
        return 1.0
    try:
        f = max(0.0, min(1.0, float(fuel_level)))
    except (TypeError, ValueError):
        f = 1.0
    if f >= 0.30:
        return 1.0
    return round(0.55 + 0.45 * (f / 0.30), 4)


def fuel_burn(fuel_level: float, fuel_use: float, kind: str = "march") -> float:
    try:
        use = max(0.0, float(fuel_use))
    except (TypeError, ValueError):
        use = 0.0
    try:
        cur = max(0.0, min(1.0, float(fuel_level)))
    except (TypeError, ValueError):
        cur = 1.0
    if use <= 1e-9:
        return cur
    k = str(kind or "march").strip().lower()
    rate = 0.10 + use * 0.22 if k == "combat" else 0.08 + use * 0.18
    return round(max(0.0, min(1.0, cur - rate)), 4)


def fuel_resupply(fuel_level: float, amount: float = 0.10) -> float:
    try:
        cur = max(0.0, min(1.0, float(fuel_level)))
    except (TypeError, ValueError):
        cur = 1.0
    try:
        add = max(0.0, float(amount))
    except (TypeError, ValueError):
        add = 0.10
    return round(max(0.0, min(1.0, cur + add)), 4)


def toe_line(equip: Mapping[str, Any] | None, limit: int = 4) -> str:
    if not isinstance(equip, Mapping) or not equip:
        return ""
    rows: List[Tuple[str, int]] = []
    for k, raw in equip.items():
        try:
            n = int(raw)
        except (TypeError, ValueError):
            continue
        if n <= 0:
            continue
        rows.append((str(k).replace("_", " ").replace("equipment", "").strip() or str(k), n))
    rows.sort(key=lambda r: r[0])
    parts = ["%s %d" % (name, n) for name, n in rows[: max(1, int(limit))]]
    if not parts:
        return ""
    return "TOE " + " · ".join(parts)


def equipment_loss_from_toe(equip: Mapping[str, Any], drain: float) -> Dict[str, int]:
    out: Dict[str, int] = {}
    dr = max(0.0, min(1.0, float(drain)))
    if dr <= 0.0 or not isinstance(equip, Mapping):
        return out
    for k, raw in equip.items():
        try:
            have = int(raw)
        except (TypeError, ValueError):
            continue
        if have <= 0:
            continue
        n = max(1, int((have * dr) + 0.999))
        out[str(k)] = min(have, n)
    return out


def attack_armor_mult(armor: float) -> float:
    return 1.0 + 0.12 * max(0.0, min(1.0, float(armor)))


def defend_armor_mult(armor: float, defense: float) -> float:
    a = 1.0 + 0.30 * max(0.0, min(1.0, float(armor)))
    d = max(0.75, min(1.35, 0.75 + 0.20 * float(defense)))
    return a * d


def manpower_lost(toe: int, drain: float) -> int:
    """Men lost this day ≈ TOE × strength drain. Both sides."""
    try:
        t = max(0, int(toe))
    except (TypeError, ValueError):
        t = 0
    try:
        dr = max(0.0, float(drain))
    except (TypeError, ValueError):
        dr = 0.0
    return max(0, int(round(float(t) * dr)))


def format_combat_loss_plain(removed: Mapping[str, Any] | None, men: int = 0) -> str:
    from land_battle_attrition_product import NO_STOCK, format_loss_plain

    eq = format_loss_plain(removed if isinstance(removed, Mapping) else {})
    m = max(0, int(men))
    if m <= 0:
        return eq
    if eq == NO_STOCK:
        return "men −%d" % m
    return "men −%d · %s" % (m, eq)


def daily_losses(
    *,
    role: str,
    lean: str,
    composition: Mapping[str, Any],
    days_elapsed: int = 1,
    strength: float = 1.0,
) -> Dict[str, Any]:
    from land_battle_attrition_product import daily_severity

    winner = (str(role) == "attacker" and str(lean) == "attacker") or (
        str(role) == "defender" and str(lean) == "defender"
    )
    sev = daily_severity(is_winner_lean=winner, days_elapsed=int(days_elapsed))
    drain = 0.5 * sev
    toe = int(composition.get("manpower", 3000) or 3000)
    men = manpower_lost(int(round(toe * max(0.0, float(strength)))), drain)
    removed = equipment_loss_from_toe(composition.get("equipment") or {}, drain)
    return {
        "role": str(role),
        "severity": sev,
        "strength_drain": drain,
        "manpower_lost": men,
        "removed": removed,
        "plain": format_combat_loss_plain(removed, men),
        "men_left": remaining_men(toe, max(0.0, float(strength) - drain)),
    }


def build_unit_composition_combat_product(*, check_wiring: bool = True) -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    wiring: Dict[str, bool] = {}

    foot = compose(mobility="foot")
    truck = compose(mobility="truck")
    mixed = compose(mobility="truck", armor="medium_tank")
    foot_tank = compose(mobility="foot", armor="medium_tank")
    if foot.get("speed") == 1.0 and truck.get("speed") == 2.0:
        passes.append("trucks_speed_infantry")
    else:
        fails.append("trucks_speed_infantry")
    if mixed.get("speed") == 1.5 and foot_tank.get("speed") == 1.0:
        passes.append("slowest_element")
    else:
        fails.append("slowest_element")
    if float(mixed.get("armor", 0)) > float(truck.get("armor", 0)):
        passes.append("tanks_add_armor")
    else:
        fails.append("tanks_add_armor")
    if attack_armor_mult(0.7) > attack_armor_mult(0.0) and defend_armor_mult(0.7, 2.0) > defend_armor_mult(0.0, 1.0):
        passes.append("armor_helps_combat")
    else:
        fails.append("armor_helps_combat")

    att = daily_losses(role="attacker", lean="defender", composition=truck, days_elapsed=2)
    dfn = daily_losses(role="defender", lean="defender", composition=truck, days_elapsed=2)
    if int(att.get("manpower_lost", 0)) > 0 and int(dfn.get("manpower_lost", 0)) > 0:
        passes.append("both_sides_men")
    else:
        fails.append("both_sides_men")
    if int(att.get("manpower_lost", 0)) >= int(dfn.get("manpower_lost", 0)):
        passes.append("loser_bleeds_more_or_equal")
    else:
        fails.append("loser_bleeds_more_or_equal")
    if "men" in str(att.get("plain", "")):
        passes.append("plain_has_men")
    else:
        fails.append("plain_has_men")
    guns = compose(mobility="truck", armor="medium_tank", support="artillery")
    if abs(float(guns.get("speed", 0)) - 1.5) < 0.01 and int((guns.get("equipment") or {}).get("artillery", 0)) == 12:
        passes.append("artillery_towed")
    else:
        fails.append("artillery_towed")
    lost_eq = equipment_loss_from_toe({"trucks": 24, "tanks": 10}, 0.05)
    if int(lost_eq.get("trucks", 0)) >= 1 and int(lost_eq.get("tanks", 0)) >= 1:
        passes.append("vehicle_writeoff")
    else:
        fails.append("vehicle_writeoff")

    triple = compose(
        mobility="truck",
        armor="medium_tank",
        support="artillery,recon",
        infantry_bns=3,
        tank_bns=2,
    )
    if int(triple.get("infantry_bns", 0)) == 3 and int(triple.get("manpower", 0)) > int(mixed.get("manpower", 0)):
        passes.append("battalion_counts")
    else:
        fails.append("battalion_counts")
    if int((triple.get("equipment") or {}).get("tanks", 0)) == 20 and int((triple.get("equipment") or {}).get("trucks", 0)) == 72:
        passes.append("toe_scales_with_bns")
    else:
        fails.append("toe_scales_with_bns")
    if abs(float(triple.get("width", 0)) - 12.0) < 0.01:
        passes.append("width_line_battalions")
    else:
        fails.append("width_line_battalions")
    if float(triple.get("fuel_use", 0)) > float(truck.get("fuel_use", 0)):
        passes.append("fuel_use_vehicles")
    else:
        fails.append("fuel_use_vehicles")
    if "recon" in list(triple.get("supports") or []) and int((triple.get("equipment") or {}).get("recon_equipment", 0)) == 12:
        passes.append("support_recon")
    else:
        fails.append("support_recon")
    atg = compose(mobility="truck", support="anti_tank,engineer")
    if abs(float(atg.get("speed", 0)) - 2.0) < 0.01 and float(atg.get("hard", 0)) > float(truck.get("hard", 0)):
        passes.append("at_towed_hard")
    else:
        fails.append("at_towed_hard")
    if pierce_mult(1.25, 0.0) > pierce_mult(0.15, 0.70):
        passes.append("pierce_hard_vs_armor")
    else:
        fails.append("pierce_hard_vs_armor")
    if float(mixed.get("hardness", 0)) > float(foot.get("hardness", 0)) and float(mixed.get("breakthrough", 0)) > float(foot.get("breakthrough", 0)):
        passes.append("tanks_hardness_breakthrough")
    else:
        fails.append("tanks_hardness_breakthrough")
    if hardness_mix(3.0, 0.3, 0.0) > hardness_mix(3.0, 0.3, 0.80):
        passes.append("hardness_mix_soft_vs_hard")
    else:
        fails.append("hardness_mix_soft_vs_hard")
    if absorb_mult("attack", 3.0, 1.0) > absorb_mult("attack", 0.4, 1.0) and absorb_mult("defend", 0.4, 3.0) > absorb_mult("attack", 0.4, 3.0):
        passes.append("breakthrough_attack_defense_defend")
    else:
        fails.append("breakthrough_attack_defense_defend")
    short = shortage_mult({"infantry_equipment": 20}, {"infantry_equipment": 80, "trucks": 24})
    full_fill = shortage_mult({"infantry_equipment": 80, "trucks": 24}, {"infantry_equipment": 80, "trucks": 24})
    if short < 0.85 and abs(full_fill - 1.0) < 0.001 and shortage_mult({}, {"infantry_equipment": 80}) == 1.0:
        passes.append("shortage_fill")
    else:
        fails.append("shortage_fill")
    if fuel_speed_mult(0.10, 0.20) < 0.80 and fuel_speed_mult(1.0, 0.20) == 1.0 and fuel_speed_mult(0.5, 0.0) == 1.0:
        passes.append("fuel_speed_dry")
    else:
        fails.append("fuel_speed_dry")
    burned = fuel_burn(1.0, 0.20, "march")
    if burned < 0.95 and burned > 0.80 and fuel_resupply(0.5, 0.10) == 0.6:
        passes.append("fuel_burn_resupply")
    else:
        fails.append("fuel_burn_resupply")
    if "TOE" in toe_line(mixed.get("equipment") or {}):
        passes.append("toe_line")
    else:
        fails.append("toe_line")

    if check_wiring:
        power = POWER.read_text(encoding="utf-8") if POWER.is_file() else ""
        pop = POPUP.read_text(encoding="utf-8") if POPUP.is_file() else ""
        attr = ATTR.read_text(encoding="utf-8") if ATTR.is_file() else ""
        bm = BM.read_text(encoding="utf-8") if BM.is_file() else ""
        mv = MV.read_text(encoding="utf-8") if MV.is_file() else ""
        strip = STRIP.read_text(encoding="utf-8") if STRIP.is_file() else ""
        lm = LM.read_text(encoding="utf-8") if LM.is_file() else ""
        harness = HARNESS.read_text(encoding="utf-8") if HARNESS.is_file() else ""
        gates = GATES.read_text(encoding="utf-8") if GATES.is_file() else ""
        tm = TM.read_text(encoding="utf-8") if TM.is_file() else ""

        def _ok(name: str, cond: bool) -> None:
            wiring[name] = cond
            (passes if cond else fails).append(name)

        _ok("compose_api", "func composition_stats" in power)
        _ok("speed_min", "func template_speed" in power)
        _ok("equip_toe", "equipment" in power or "EL_EQUIP" in power)
        _ok("gd_pierce", "func pierce_mult" in power)
        _ok("gd_hardness", "func hardness_mix" in power and "EL_HARDNESS" in power)
        _ok("gd_breakthrough", "func absorb_mult" in power and "EL_BREAKTHROUGH" in power)
        _ok("popup_bt_hard", "Breakthrough" in pop and "Hardness" in pop)
        _ok("gd_fuel", "fuel_use" in power and "func fuel_speed_mult" in power)
        _ok("gd_width", "EL_WIDTH" in power or '"width"' in power)
        _ok("gd_shortage", "func shortage_mult" in power)
        _ok("popup_mobility", "_mobility_option" in pop and "Half-track" in pop)
        _ok("popup_artillery", "Artillery" in pop)
        _ok("popup_bns", "infantry_bns" in pop and "tank_bns" in pop)
        _ok("popup_support_ex", "Recon" in pop and "Anti-tank" in pop and "Engineers" in pop)
        _ok("popup_prefield_stats", "slowest" in pop and "TOE" in pop and "Field on map" in pop)
        _ok("popup_existing_reload", "_apply_stored_template" in pop and "Existing template" in pop)
        _ok("attr_men", "manpower_lost" in attr and "men" in attr)
        _ok("national_manpower", "adjust_manpower" in attr)
        _ok("attr_fuel", "apply_fuel_burn" in attr or "fuel_level" in attr)
        _ok("both_sides", "att_fids" in bm and "def_fids" in bm and "apply_daily_to_formation" in bm)
        _ok("role_power", 'land_combat_power' in bm and '"defend"' in bm)
        _ok("pierce_wired", "opponent" in bm and "land_combat_power" in bm)
        _ok("march_uses_speed", "template_speed" in mv)
        _ok("march_fuel", "apply_fuel_burn" in mv or "fuel_level" in mv)
        _ok("card_speed_armor", "Speed" in strip or "Armor" in strip)
        _ok("card_width_fuel", "Width" in strip and "Fuel" in strip)
        _ok("save_comp", "mobility" in lm or "composition" in lm)
        _ok("save_bns_fuel", "infantry_bns" in lm and "fuel_level" in lm)
        _ok("recovery_fuel", "fuel_level" in tm)
        _ok("on_official_quick", "test_unit_composition_combat_product" in gates)
        _ok("harness_comp", "composition_stats" in harness and "manpower_lost" in harness)
        _ok("harness_full", "pierce_mult" in harness and "infantry_bns" in harness)
        _ok("harness_hardness", "hardness_mix" in harness or "vs_hard" in harness or "vs a hard" in harness.lower())
        _ok("harness_field_stamp", "force_new" in harness and "template_speed" in harness and "unit_width" in harness)
        dm = (ROOT / "scripts" / "production" / "DesignManager.gd").read_text(encoding="utf-8") if (ROOT / "scripts" / "production" / "DesignManager.gd").is_file() else ""
        _ok("design_persist", "func composition_from_design" in dm and "composition_blob_from_data" in dm)
        _ok("field_from_design", "composition_from_design" in lm and "_stamp_formation_composition" in lm)

    ok = len(fails) == 0
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "wiring": wiring,
        "pass": passes,
        "fail": fails,
        "foot": foot,
        "truck": truck,
        "mixed": mixed,
        "summary": "unit_composition_combat · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "battalions_support_fuel_width_pierce_both_side_losses",
    }


def unit_composition_combat_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_unit_composition_combat_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
