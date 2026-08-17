"""Multi-day land battle rules SOT — estimate days, instant empty, daily org tick.

Offline product for the L1 war-loop battle slice. Godot reimplements later.
Synthetic force/terrain only.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
BATTLE_MANAGER = ROOT / "scripts" / "combat" / "BattleManager.gd"
TIME_MANAGER = ROOT / "scripts" / "autoload" / "TimeManager.gd"

ORG_BREAK = 0.22
MIN_BATTLE_DAYS = 2
MAX_BATTLE_DAYS = 6
EVEN_DRAIN = 0.20  # even plains: both lose 0.20 org / tick (first tick stays above break)

# Terrain stretches duration (mountain/urban/fort longer).
TERRAIN_DAYS_ADD: Dict[str, int] = {
    "plains": 0,
    "desert": 0,
    "hills": 1,
    "forest": 1,
    "jungle": 1,
    "marsh": 1,
    "urban": 2,
    "mountain": 2,
    "fort": 2,
}

TERRAIN_STRETCH: Dict[str, float] = {
    "plains": 1.0,
    "desert": 1.0,
    "hills": 1.15,
    "forest": 1.15,
    "jungle": 1.25,
    "marsh": 1.25,
    "urban": 1.45,
    "mountain": 1.50,
    "fort": 1.55,
}

EVEN_POWER = 100.0
ARMOR_ATT_POWER = 150.0


def _terrain_key(terrain: str) -> str:
    key = str(terrain or "plains").strip().lower() or "plains"
    return key


def _ratio_days(att_power: float, def_power: float) -> int:
    """2–6 from force ratio. Even fight → 4; 2:1 → 2; 1:2 → 6."""
    att = max(0.0, float(att_power))
    dfn = max(1e-9, float(def_power))
    ratio = att / dfn
    if ratio >= 2.0:
        return 2
    if ratio >= 1.5:
        return 3
    if ratio >= 1.0:
        return 4
    if ratio >= 0.7:
        return 5
    return 6


def estimate_battle_days(
    *,
    att_power: float,
    def_power: float,
    terrain: str,
    empty_defender: bool,
) -> int:
    """empty_defender → 0. Else 2–6 days from force ratio and terrain."""
    if empty_defender:
        return 0
    key = _terrain_key(terrain)
    days = _ratio_days(att_power, def_power) + int(TERRAIN_DAYS_ADD.get(key, 0))
    return max(MIN_BATTLE_DAYS, min(MAX_BATTLE_DAYS, int(days)))


def should_resolve_instant(*, empty_defender: bool) -> bool:
    return bool(empty_defender)


def daily_tick(
    *,
    att_org: float,
    def_org: float,
    att_power: float,
    def_power: float,
    terrain: str,
) -> Dict[str, Any]:
    """Return {att_org, def_org, resolved, winner}.

    resolved if either org below ~0.22. Even fight does not resolve on first tick.
    """
    att_p = max(0.0, float(att_power))
    def_p = max(0.0, float(def_power))
    total = att_p + def_p
    a_org = max(0.0, float(att_org))
    d_org = max(0.0, float(def_org))
    if total <= 1e-9:
        resolved = a_org < ORG_BREAK or d_org < ORG_BREAK
        winner = ""
        if resolved:
            if a_org > d_org:
                winner = "attacker"
            elif d_org > a_org:
                winner = "defender"
            else:
                winner = "draw"
        return {
            "att_org": a_org,
            "def_org": d_org,
            "resolved": resolved,
            "winner": winner,
        }

    stretch = float(TERRAIN_STRETCH.get(_terrain_key(terrain), 1.0))
    stretch = max(1.0, stretch)
    # Even plains: 2 * EVEN_DRAIN * 0.5 / 1.0 = EVEN_DRAIN.
    att_loss = (2.0 * EVEN_DRAIN) * (def_p / total) / stretch
    def_loss = (2.0 * EVEN_DRAIN) * (att_p / total) / stretch
    a_org = max(0.0, a_org - att_loss)
    d_org = max(0.0, d_org - def_loss)
    resolved = a_org < ORG_BREAK or d_org < ORG_BREAK
    winner = ""
    if resolved:
        if a_org > d_org:
            winner = "attacker"
        elif d_org > a_org:
            winner = "defender"
        else:
            winner = "draw"
    return {
        "att_org": float(a_org),
        "def_org": float(d_org),
        "resolved": bool(resolved),
        "winner": winner,
    }


def _tick_until_resolved(
    *,
    att_org: float = 1.0,
    def_org: float = 1.0,
    att_power: float = EVEN_POWER,
    def_power: float = EVEN_POWER,
    terrain: str = "plains",
    max_ticks: int = 24,
) -> Dict[str, Any]:
    state = {
        "att_org": float(att_org),
        "def_org": float(def_org),
        "resolved": False,
        "winner": "",
    }
    ticks = 0
    for _ in range(max(1, int(max_ticks))):
        state = daily_tick(
            att_org=float(state["att_org"]),
            def_org=float(state["def_org"]),
            att_power=att_power,
            def_power=def_power,
            terrain=terrain,
        )
        ticks += 1
        if state.get("resolved"):
            break
    return {"ticks": ticks, **state}


def build_unit_multi_day_battle_product() -> Dict[str, Any]:
    """Run synthetic multi-day battle fixtures. ok iff all pass."""
    passes: List[str] = []
    fails: List[str] = []

    empty_days = estimate_battle_days(
        att_power=EVEN_POWER,
        def_power=0.0,
        terrain="plains",
        empty_defender=True,
    )
    empty_instant = should_resolve_instant(empty_defender=True)
    if empty_days == 0 and empty_instant:
        passes.append("empty_defender_instant")
    else:
        fails.append("empty_defender_instant")

    even_days = estimate_battle_days(
        att_power=EVEN_POWER,
        def_power=EVEN_POWER,
        terrain="plains",
        empty_defender=False,
    )
    if even_days >= MIN_BATTLE_DAYS:
        passes.append("even_fight_ge_2")
    else:
        fails.append("even_fight_ge_2")

    armor_plains = estimate_battle_days(
        att_power=ARMOR_ATT_POWER,
        def_power=EVEN_POWER,
        terrain="plains",
        empty_defender=False,
    )
    inf_mountain = estimate_battle_days(
        att_power=EVEN_POWER,
        def_power=EVEN_POWER,
        terrain="mountain",
        empty_defender=False,
    )
    if armor_plains < inf_mountain:
        passes.append("armor_plains_faster_than_inf_mountain")
    else:
        fails.append("armor_plains_faster_than_inf_mountain")

    first = daily_tick(
        att_org=1.0,
        def_org=1.0,
        att_power=EVEN_POWER,
        def_power=EVEN_POWER,
        terrain="plains",
    )
    if not first.get("resolved"):
        passes.append("even_first_tick_open")
    else:
        fails.append("even_first_tick_open")

    loop = _tick_until_resolved()
    if loop.get("resolved") and int(loop.get("ticks") or 0) >= 2:
        passes.append("repeated_ticks_resolve")
    else:
        fails.append("repeated_ticks_resolve")

    bm = BATTLE_MANAGER.read_text(encoding="utf-8") if BATTLE_MANAGER.is_file() else ""
    tm = TIME_MANAGER.read_text(encoding="utf-8") if TIME_MANAGER.is_file() else ""
    if (
        "func start_land_battle" in bm
        and "func tick_open_land_battles" in bm
        and "func get_open_land_battles" in bm
    ):
        passes.append("battle_manager_land_battle_api")
    else:
        fails.append("battle_manager_land_battle_api")
    if "_tick_open_land_battles" in tm and "tick_open_land_battles" in tm:
        passes.append("time_manager_land_battle_tick")
    else:
        fails.append("time_manager_land_battle_tick")

    ok = len(fails) == 0
    fixtures: Dict[str, Any] = {
        "empty_defender": {
            "days": empty_days,
            "instant": empty_instant,
        },
        "even_fight_plains": {
            "days": even_days,
            "first_tick_resolved": bool(first.get("resolved")),
            "first_att_org": first.get("att_org"),
            "first_def_org": first.get("def_org"),
        },
        "armor_plains_vs_inf_mountain": {
            "armor_plains_days": armor_plains,
            "inf_mountain_days": inf_mountain,
        },
        "tick_loop": {
            "ticks": loop.get("ticks"),
            "resolved": loop.get("resolved"),
            "winner": loop.get("winner"),
            "att_org": loop.get("att_org"),
            "def_org": loop.get("def_org"),
        },
    }
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "fixtures": fixtures,
        "summary": "unit_multi_day_battle · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "empty_instant_else_2_to_6_days_org_break_0.22",
        "integration": [
            "unit_multi_day_battle_product",
            "combat_phase_estimate",
            "assault_estimate_card",
        ],
    }


def unit_multi_day_battle_integrity() -> Dict[str, Any]:
    p = build_unit_multi_day_battle_product()
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
