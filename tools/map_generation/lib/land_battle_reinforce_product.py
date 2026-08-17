"""Land battle reinforce + combat width SOT.

Marching a second unit onto a live front must change engaged power and ETA.
Overflow past combat width is penalized (HOI stacking).
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Sequence

ROOT = Path(__file__).resolve().parents[3]
BM_GD = ROOT / "scripts" / "combat" / "BattleManager.gd"
FM_GD = ROOT / "scripts" / "formations" / "FormationMovement.gd"
LCP_GD = ROOT / "scripts" / "combat" / "LandCombatPower.gd"

BASE_COMBAT_WIDTH = 10.0
OVERWIDTH_FACTOR = 0.35
INFANTRY_WIDTH = 2.0
ARMOR_WIDTH = 3.0

TERRAIN_WIDTH = {
    "plains": 1.0,
    "hills": 0.85,
    "forest": 0.75,
    "jungle": 0.55,
    "mountain": 0.45,
    "urban": 0.65,
    "marsh": 0.60,
    "desert": 0.90,
    "arctic": 0.50,
}

INFRA_WIDTH = {0: 0.6, 1: 0.8, 2: 1.0, 3: 1.2, 4: 1.4, 5: 1.6}


def combat_width_for_terrain(terrain: str, infra_level: int = 2) -> float:
    terr = str(terrain or "plains").strip().lower() or "plains"
    if terr in ("mountains", "alpine"):
        terr = "mountain"
    tmod = float(TERRAIN_WIDTH.get(terr, 1.0))
    il = max(0, min(5, int(infra_level)))
    imod = float(INFRA_WIDTH.get(il, 1.0))
    return float(BASE_COMBAT_WIDTH * tmod * imod)


def unit_width(kind: str) -> float:
    k = str(kind or "infantry").strip().lower()
    if any(tok in k for tok in ("armor", "armour", "panzer", "tank")):
        return ARMOR_WIDTH
    return INFANTRY_WIDTH


def engaged_power(
    powers: Sequence[float],
    widths: Sequence[float],
    combat_width: float,
) -> float:
    """Highest-power units fill width first; overflow at OVERWIDTH_FACTOR."""
    rows: List[tuple] = []
    for i, p in enumerate(powers):
        w = float(widths[i]) if i < len(widths) else INFANTRY_WIDTH
        rows.append((float(p), max(0.1, w)))
    rows.sort(key=lambda r: r[0], reverse=True)
    remaining = max(0.1, float(combat_width))
    total = 0.0
    for power, width in rows:
        if remaining <= 1e-9:
            total += power * OVERWIDTH_FACTOR
            continue
        if width <= remaining:
            total += power
            remaining -= width
        else:
            frac = remaining / width
            total += power * frac + power * (1.0 - frac) * OVERWIDTH_FACTOR
            remaining = 0.0
    return float(total)


def reinforce_legal(
    *,
    unit_tag: str,
    att_tag: str,
    def_tag: str,
    pid: int,
    from_id: int,
    to_id: int,
    already_in: bool,
) -> str:
    """Return side 'attacker'/'defender' or '' if illegal."""
    if already_in:
        return ""
    tag = str(unit_tag or "").strip().upper()
    att = str(att_tag or "").strip().upper()
    dfn = str(def_tag or "").strip().upper()
    if tag and tag == att and int(pid) == int(from_id):
        return "attacker"
    if tag and tag == dfn and int(pid) == int(to_id):
        return "defender"
    if tag and tag == att and int(pid) == int(to_id):
        return "attacker"
    return ""


def build_land_battle_reinforce_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []

    plains_w = combat_width_for_terrain("plains", 2)
    mtn_w = combat_width_for_terrain("mountain", 2)
    if plains_w > mtn_w and plains_w == 10.0:
        passes.append("width_plains_gt_mountain")
    else:
        fails.append("width_plains_gt_mountain")

    if unit_width("armor") > unit_width("infantry"):
        passes.append("armor_wider_than_infantry")
    else:
        fails.append("armor_wider_than_infantry")

    one = engaged_power([100.0], [2.0], plains_w)
    two = engaged_power([100.0, 100.0], [2.0, 2.0], plains_w)
    if two > one * 1.5:
        passes.append("second_infantry_boosts_power")
    else:
        fails.append("second_infantry_boosts_power")

    six_inf = [100.0] * 6
    six_w = [2.0] * 6
    capped = engaged_power(six_inf, six_w, plains_w)
    uncapped = 600.0
    if capped < uncapped * 0.92:
        passes.append("overwidth_penalty")
    else:
        fails.append("overwidth_penalty")

    if reinforce_legal(
        unit_tag="GER", att_tag="GER", def_tag="FRA",
        pid=1, from_id=1, to_id=2, already_in=False,
    ) == "attacker":
        passes.append("reinforce_from_hex")
    else:
        fails.append("reinforce_from_hex")
    if reinforce_legal(
        unit_tag="GER", att_tag="GER", def_tag="FRA",
        pid=1, from_id=1, to_id=2, already_in=True,
    ) == "":
        passes.append("no_double_join")
    else:
        fails.append("no_double_join")

    bm = BM_GD.read_text(encoding="utf-8") if BM_GD.is_file() else ""
    fm = FM_GD.read_text(encoding="utf-8") if FM_GD.is_file() else ""
    lcp = LCP_GD.read_text(encoding="utf-8") if LCP_GD.is_file() else ""
    if "func try_reinforce_land_battle" in bm and "att_fids" in bm:
        passes.append("bm_reinforce_api")
    else:
        fails.append("bm_reinforce_api")
    if "try_reinforce_land_battle" in fm:
        passes.append("march_hop_feeds_battle")
    else:
        fails.append("march_hop_feeds_battle")
    if "func engaged_power" in lcp and "func unit_width" in lcp:
        passes.append("lcp_width_helpers")
    else:
        fails.append("lcp_width_helpers")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "summary": "land_battle_reinforce · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "feed_front_width_cap_overwidth_0.35",
        "fixtures": {
            "plains_width": plains_w,
            "mountain_width": mtn_w,
            "one_vs_two": {"one": one, "two": two},
            "six_inf_engaged": capped,
        },
    }


def land_battle_reinforce_integrity() -> Dict[str, Any]:
    p = build_land_battle_reinforce_product()
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
