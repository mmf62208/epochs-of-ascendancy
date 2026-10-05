"""After-action line + next-hex offer (one more fight, not a HOI AAR dump)."""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
AAR_GD = ROOT / "scripts" / "combat" / "LandBattleAar.gd"
BM_GD = ROOT / "scripts" / "combat" / "BattleManager.gd"
HOOK_GD = ROOT / "scripts" / "ui" / "PlayNextHook.gd"
REN_GD = ROOT / "scripts" / "map" / "MapRenderer.gd"


def format_line(
    winner: str,
    place: str,
    days: int,
    loss_plain: str = "",
    next_place: str = "",
) -> str:
    w = str(winner or "").strip().lower()
    name = (place or "the hex").strip()
    day_n = max(0, int(days))
    day_s = "%d day%s" % (day_n, "s" if day_n != 1 else "")
    loss = (loss_plain or "").strip()
    if w == "attacker":
        s = "Took %s · %s" % (name, day_s)
        if loss and loss != "no stock to lose":
            s += " · %s" % loss
        if (next_place or "").strip():
            s += " — Press %s next?" % next_place.strip()
        else:
            s += " — Hold and recover?"
        return s
    s2 = "Held at %s · %s" % (name, day_s)
    if loss and loss != "no stock to lose":
        s2 += " · %s" % loss
    s2 += " — Recover or try again?"
    return s2


def build_land_battle_aar_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    win = format_line("attacker", "Bas-Rhin", 3, "rifles −14", "Haguenau")
    if "Took Bas-Rhin" in win and "3 days" in win and "Press Haguenau" in win:
        passes.append("win_offers_next")
    else:
        fails.append("win_offers_next")
    hold = format_line("defender", "Bas-Rhin", 2, "")
    if "Held" in hold and "try again" in hold:
        passes.append("hold_offers_retry")
    else:
        fails.append("hold_offers_retry")
    aar = AAR_GD.read_text(encoding="utf-8") if AAR_GD.is_file() else ""
    bm = BM_GD.read_text(encoding="utf-8") if BM_GD.is_file() else ""
    hook = HOOK_GD.read_text(encoding="utf-8") if HOOK_GD.is_file() else ""
    ren = REN_GD.read_text(encoding="utf-8") if REN_GD.is_file() else ""
    if "func format_line" in aar and "func pick_next_enemy_hex" in aar:
        passes.append("aar_api")
    else:
        fails.append("aar_api")
    if "_last_land_aar" in bm or "last_land_aar" in bm:
        passes.append("bm_stores_aar")
    else:
        fails.append("bm_stores_aar")
    if "next_hex" in hook or "peek_last_land_aar" in hook:
        passes.append("hook_reads_aar")
    else:
        fails.append("hook_reads_aar")
    # COMBAT-1: toast/card after the existing tick, not only while a fight
    # is still open (day_emit used to skip Took/Held when open_n==0).
    if (
        "refresh_after_land_battle_day" in ren
        and "_surface_last_land_aar_toast" in ren
        and "_notify_land_battle_day_surface" in bm
    ):
        passes.append("aar_toast_after_tick")
    else:
        fails.append("aar_toast_after_tick")
    if "get_divisions_at_province" in ren and "_province_has_defending_units" in ren:
        passes.append("prefer_defended_neighbor")
    else:
        fails.append("prefer_defended_neighbor")
    ok = len(fails) == 0
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "summary": "land_battle_aar · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "win_offers_next_hex_one_line",
    }
