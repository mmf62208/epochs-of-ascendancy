"""Unit composition — infantry + vehicles, slowest-element speed, combat losses.

Pick infantry, then motorcycle / truck / halftrack to mount it (mobility).
Optional tanks. Speed is the min of remaining elements (mounted infantry
drops the foot speed). Armor/defense feed combat. Daily fight writes
manpower AND equipment for attacker and defender.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence

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

ELEMENTS: Dict[str, Dict[str, Any]] = {
    "infantry": {
        "speed": 1.0,
        "armor": 0.0,
        "defense": 1.0,
        "manpower": 3000,
        "mounted": False,
    },
    "motorcycle": {
        "speed": 2.4,
        "armor": 0.0,
        "defense": 0.65,
        "manpower": 400,
        "mounted": True,
    },
    "truck": {
        "speed": 2.0,
        "armor": 0.05,
        "defense": 0.75,
        "manpower": 200,
        "mounted": True,
    },
    "halftrack": {
        "speed": 1.6,
        "armor": 0.35,
        "defense": 1.20,
        "manpower": 280,
        "mounted": True,
    },
    "light_tank": {
        "speed": 1.8,
        "armor": 0.45,
        "defense": 1.10,
        "manpower": 400,
        "mounted": False,
    },
    "medium_tank": {
        "speed": 1.5,
        "armor": 0.70,
        "defense": 1.30,
        "manpower": 500,
        "mounted": False,
    },
    "heavy_tank": {
        "speed": 1.2,
        "armor": 0.90,
        "defense": 1.50,
        "manpower": 520,
        "mounted": False,
    },
}

MOBILITY_IDS = ("foot", "motorcycle", "truck", "halftrack")
ARMOR_IDS = ("", "none", "light_tank", "medium_tank", "heavy_tank")


def _el(eid: str) -> Optional[Dict[str, Any]]:
    return ELEMENTS.get(str(eid or "").strip().lower())


def compose(
    *,
    core: str = "infantry",
    mobility: str = "foot",
    armor: str = "",
) -> Dict[str, Any]:
    """Build a division from infantry + optional transport + optional tanks."""
    core_id = str(core or "infantry").strip().lower() or "infantry"
    mob_id = str(mobility or "foot").strip().lower() or "foot"
    arm_id = str(armor or "").strip().lower()
    if arm_id in ("none", "foot"):
        arm_id = ""
    ids: List[str] = [core_id if core_id in ELEMENTS else "infantry"]
    if mob_id in ELEMENTS and mob_id not in ids:
        ids.append(mob_id)
    if arm_id in ELEMENTS and arm_id not in ids:
        ids.append(arm_id)
    elems = [_el(i) for i in ids]
    elems = [e for e in elems if e]
    mounted = any(bool(e.get("mounted")) for e in elems)
    speeds: List[float] = []
    for i, e in zip(ids, elems):
        if mounted and i == "infantry":
            continue  # infantry rides; foot speed no longer limits
        speeds.append(float(e["speed"]))
    if not speeds:
        speeds = [1.0]
    speed = min(speeds)
    armor_v = max(float(e["armor"]) for e in elems)
    defense = sum(float(e["defense"]) for e in elems)
    manpower = sum(int(e["manpower"]) for e in elems)
    return {
        "ok": True,
        "ids": ids,
        "mobility": mob_id,
        "armor_element": arm_id,
        "speed": round(speed, 3),
        "armor": round(armor_v, 3),
        "defense": round(defense, 3),
        "manpower": manpower,
        "mounted": mounted,
        "kind": "armor" if arm_id else ("motor" if mounted else "infantry"),
    }


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
    return {
        "role": str(role),
        "severity": sev,
        "strength_drain": drain,
        "manpower_lost": men,
        "plain": format_combat_loss_plain({}, men),
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

        def _ok(name: str, cond: bool) -> None:
            wiring[name] = cond
            (passes if cond else fails).append(name)

        _ok("compose_api", "func compose_unit" in power or "func composition_stats" in power)
        _ok("speed_min", "func template_speed" in power)
        _ok("popup_mobility", "_mobility_option" in pop and "Half-track" in pop)
        _ok("attr_men", "manpower_lost" in attr and "men" in attr)
        _ok("both_sides", "att_fids" in bm and "def_fids" in bm and "apply_daily_to_formation" in bm)
        _ok("march_uses_speed", "template_speed" in mv)
        _ok("card_speed_armor", "Speed" in strip or "Armor" in strip)
        _ok("save_comp", "mobility" in lm or "composition" in lm)
        _ok("on_official_quick", "test_unit_composition_combat_product" in gates)
        _ok("harness_comp", "compose" in harness or "manpower_lost" in harness or "Half-track" in harness)

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
        "policy": "infantry_plus_vehicles_min_speed_armor_both_side_losses",
    }


def unit_composition_combat_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_unit_composition_combat_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
