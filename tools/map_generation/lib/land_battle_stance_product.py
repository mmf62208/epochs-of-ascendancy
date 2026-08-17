"""Player battle stance — Press / Hold / Withdraw. Agency, not HOI tactics dice.

Press hits harder and costs more. Hold waits (less loss, slower break).
days_to_break == 1 is the one-more-turn hook.
River/fort is a choice: Press pays extra, Hold waits for a better moment.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
BM_GD = ROOT / "scripts" / "combat" / "BattleManager.gd"
REN_GD = ROOT / "scripts" / "map" / "MapRenderer.gd"

PRESS_ATT_POWER = 1.25
HOLD_ATT_POWER = 0.85
PRESS_ATT_ORG = 0.04
HOLD_ATT_ORG = -0.02  # less drain (recover a sliver)
PRESS_EQUIP = 1.35
FORT_PRESS_ORG = 0.03
ORG_BREAK = 0.22


def stance_power_mult(stance: str) -> float:
    s = str(stance or "press").strip().lower()
    if s == "hold":
        return HOLD_ATT_POWER
    if s == "withdraw":
        return 0.0
    return PRESS_ATT_POWER


def stance_org_delta(stance: str, *, ground_hard: bool = False) -> float:
    s = str(stance or "press").strip().lower()
    if s == "hold":
        return HOLD_ATT_ORG
    extra = FORT_PRESS_ORG if ground_hard else 0.0
    return PRESS_ATT_ORG + extra


def days_to_break(def_org: float, daily_def_drain: float) -> int:
    org = float(def_org)
    drain = max(0.01, float(daily_def_drain))
    if org < ORG_BREAK:
        return 0
    n = 0
    while org >= ORG_BREAK and n < 12:
        org -= drain
        n += 1
    return n


def next_hook(*, days_left: int, march_eta: int, ground_hard: bool, stance: str) -> str:
    if days_left == 1 and str(stance) != "hold":
        return "They break tomorrow — Press, or Hold if you need the next unit"
    if days_left == 1 and str(stance) == "hold":
        return "They are one day from breaking — Press to finish, or Hold to wait"
    if march_eta == 1:
        return "Reinforcement arrives tomorrow — Hold to let them join"
    if ground_hard and str(stance) == "press":
        return "River/fort — Press costs extra org, or Hold a day"
    if days_left <= 0:
        return "Front collapsing now"
    return "Unpause to fight · Press or Hold"


def build_land_battle_stance_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    if stance_power_mult("press") > stance_power_mult("hold"):
        passes.append("press_hits_harder")
    else:
        fails.append("press_hits_harder")
    if stance_org_delta("press") > 0 and stance_org_delta("hold") < 0:
        passes.append("hold_saves_org")
    else:
        fails.append("hold_saves_org")
    if stance_org_delta("press", ground_hard=True) > stance_org_delta("press", ground_hard=False):
        passes.append("fort_costs_press")
    else:
        fails.append("fort_costs_press")
    dtb = days_to_break(0.40, 0.20)
    if dtb == 1:
        passes.append("one_day_to_break")
    else:
        fails.append("one_day_to_break")
    hook = next_hook(days_left=1, march_eta=3, ground_hard=False, stance="press")
    if "tomorrow" in hook.lower():
        passes.append("tomorrow_hook")
    else:
        fails.append("tomorrow_hook")

    bm = BM_GD.read_text(encoding="utf-8") if BM_GD.is_file() else ""
    ren = REN_GD.read_text(encoding="utf-8") if REN_GD.is_file() else ""
    if "func set_land_battle_stance" in bm and "att_stance" in bm:
        passes.append("bm_stance_api")
    else:
        fails.append("bm_stance_api")
    if "func land_battle_next_hook" in bm or "func _land_battle_next_hook" in bm:
        passes.append("bm_next_hook")
    else:
        fails.append("bm_next_hook")
    if "Press" in ren and "Hold" in ren and "set_land_battle_stance" in ren:
        passes.append("card_press_hold")
    else:
        fails.append("card_press_hold")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "summary": "land_battle_stance · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "press_hold_withdraw_tomorrow_hook",
    }


def land_battle_stance_integrity() -> Dict[str, Any]:
    p = build_land_battle_stance_product()
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
