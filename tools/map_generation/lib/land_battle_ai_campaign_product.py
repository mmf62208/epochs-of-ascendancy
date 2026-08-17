"""Budgeted AI own-land march + one follow-on start after an attacker win.

L1 start_land_battle already opens a single adjacent fight. A 20–60d campaign
needs the spare rear division to walk to a live border, then (on win) press
the next enemy hex — same as player AAR NEXT, budgeted 1 follow-on.

Never execute_province_assault from the AI initiator. Killswitch:
EOA_AI_LAND_BATTLES=0 (same as land_battle_ai_init).
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence, Union

ROOT = Path(__file__).resolve().parents[3]
AI_GD = ROOT / "scripts" / "combat" / "LandBattleAi.gd"
BM_GD = ROOT / "scripts" / "combat" / "BattleManager.gd"
FM_GD = ROOT / "scripts" / "formations" / "FormationMovement.gd"

HARD_MAX_MARCHES_PER_DAY = 1
HARD_MAX_FOLLOW_ON = 1
HARD_MAX_STARTS_PER_DAY = 1

PERSONALITY_AGGRESSION: Dict[str, float] = {
    "GER": 0.88,
    "SOV": 0.70,
    "USA": 0.55,
    "ENG": 0.50,
    "FRA": 0.45,
    "ITA": 0.60,
    "JAP": 0.75,
    "POL": 0.52,
}

PREFERRED_FOES: Dict[str, tuple] = {
    "GER": ("FRA", "POL", "SOV"),
    "FRA": ("GER", "ITA"),
    "SOV": ("POL", "GER"),
    "JAP": ("CHI", "SOV"),
    "USA": ("JAP",),
    "ITA": ("FRA",),
    "ENG": ("GER",),
    "POL": ("GER", "SOV"),
}

# Maginot staging hex — dest of a spare GER rear march.
GER_FRONT_STAGING = 710173
GER_FRONT_ENEMY = 710739


def extract_gd_func_body(src: str, func_name: str) -> str:
    needle = "func %s" % func_name
    i = src.find(needle)
    if i < 0:
        return ""
    lines = src[i:].splitlines()
    out = [lines[0]]
    for line in lines[1:]:
        if line.startswith("func ") or line.startswith("static func "):
            break
        out.append(line)
    return "\n".join(out)


def _norm_tag(tag: Any) -> str:
    return str(tag or "").strip().upper()


def personality_aggression(tag: str) -> float:
    t = _norm_tag(tag)
    if t in PERSONALITY_AGGRESSION:
        return float(PERSONALITY_AGGRESSION[t])
    return 0.5


def _dest_id(opp: Mapping[str, Any]) -> int:
    """March dest = from_id of a live border target (staging hex)."""
    for key in ("dest_id", "border_from_id", "staging_id"):
        raw = opp.get(key)
        if raw is not None and int(raw or 0) > 0:
            return int(raw)
    return 0


def _score_one_march(opp: Mapping[str, Any], *, player_tag: str = "") -> float:
    tag = _norm_tag(opp.get("tag") or opp.get("att_tag"))
    foe = _norm_tag(opp.get("defender_tag") or opp.get("def_tag"))
    player = _norm_tag(player_tag)
    score = personality_aggression(tag) * 10.0
    if foe and foe in PREFERRED_FOES.get(tag, ()):
        score += 2.5
    if player and foe == player:
        score += 4.0
    if bool(opp.get("at_rear") or opp.get("at_capital")):
        score += 2.0
    if bool(opp.get("has_own_path", False)):
        score += 3.0
    dest_own = opp.get("dest_is_own_land")
    if dest_own is None or bool(dest_own):
        score += 1.0
    dest = _dest_id(opp)
    if dest == GER_FRONT_STAGING:
        score += 0.5
    return score


def score_march_to_front(
    opps: Union[Mapping[str, Any], Sequence[Mapping[str, Any]]],
    *,
    player_tag: str = "",
) -> Any:
    """Score spare rear unit(s) marching to dest=from_id of a live border.

    Single mapping → float. Sequence → ranked rows (dest_id filled).
    Own-land path is implied by has_own_path.
    """
    if isinstance(opps, Mapping):
        return _score_one_march(opps, player_tag=player_tag)
    ranked: List[Dict[str, Any]] = []
    for raw in opps or []:
        if not isinstance(raw, Mapping):
            continue
        row = dict(raw)
        dest = _dest_id(row)
        if dest > 0:
            row["dest_id"] = dest
        row["score"] = _score_one_march(row, player_tag=player_tag)
        ranked.append(row)
    ranked.sort(
        key=lambda r: (
            -float(r.get("score", 0.0)),
            str(r.get("tag", "")),
            int(r.get("dest_id") or 0),
        )
    )
    return ranked


def should_enqueue_march(
    opp: Mapping[str, Any],
    *,
    player_tag: str = "",
    marches_today: int = 0,
    max_marches: int = HARD_MAX_MARCHES_PER_DAY,
) -> bool:
    """Not already marching, not in combat, dest is own land, 1/day, never player."""
    if int(marches_today) >= int(max_marches):
        return False
    tag = _norm_tag(opp.get("tag") or opp.get("att_tag"))
    player = _norm_tag(player_tag)
    if tag and player and tag == player:
        return False
    if bool(opp.get("already_marching") or opp.get("is_marching")):
        return False
    if bool(opp.get("in_combat") or opp.get("is_in_combat")):
        return False
    dest_own = opp.get("dest_is_own_land")
    if dest_own is not None and not bool(dest_own):
        return False
    if _dest_id(opp) <= 0:
        return False
    if not bool(opp.get("has_own_path", False)):
        return False
    fid = str(opp.get("formation_id") or opp.get("fid") or "").strip()
    if not fid:
        return False
    return True


def should_follow_on(
    aar: Mapping[str, Any],
    *,
    player_tag: str = "",
    open_hexes: Optional[Sequence[int]] = None,
    follow_ons_today: int = 0,
    max_follow_on: int = HARD_MAX_FOLLOW_ON,
    expected_fid: str = "",
) -> bool:
    """Winner==attacker, next_pid>0, same fid, not already open, 1 follow-on."""
    if not isinstance(aar, Mapping) or not aar:
        return False
    if int(follow_ons_today) >= int(max_follow_on):
        return False
    winner = str(aar.get("winner") or "").strip().lower()
    if winner != "attacker":
        return False
    next_pid = int(aar.get("next_pid") or 0)
    if next_pid <= 0:
        return False
    fid = str(aar.get("fid") or aar.get("formation_id") or aar.get("att_fid") or "").strip()
    if not fid:
        return False
    want = str(expected_fid or "").strip()
    if want and want != fid:
        return False
    tag = _norm_tag(aar.get("tag") or aar.get("att_tag"))
    player = _norm_tag(player_tag)
    if tag and player and tag == player:
        return False
    busy = {int(x) for x in (open_hexes or []) if int(x) > 0}
    if next_pid in busy:
        return False
    return True


def plan_marches(
    opportunities: Sequence[Mapping[str, Any]],
    *,
    player_tag: str = "GER",
    day_index: int = 0,
    marching_fids: Optional[Sequence[str]] = None,
    combat_fids: Optional[Sequence[str]] = None,
    max_marches: int = HARD_MAX_MARCHES_PER_DAY,
) -> Dict[str, Any]:
    """Pick 0–1 enqueue_own_land_march rows. Never start_land_battle here."""
    player = _norm_tag(player_tag) or "GER"
    cap = max(0, min(HARD_MAX_MARCHES_PER_DAY, int(max_marches)))
    marching = {str(x).strip() for x in (marching_fids or []) if str(x).strip()}
    combat = {str(x).strip() for x in (combat_fids or []) if str(x).strip()}
    scored: List[Dict[str, Any]] = []
    for raw in opportunities or []:
        if not isinstance(raw, Mapping):
            continue
        tag = _norm_tag(raw.get("tag") or raw.get("att_tag"))
        if not tag or tag == player:
            continue
        dest = _dest_id(raw)
        station = int(raw.get("from_id") or raw.get("station_id") or 0)
        fid = str(raw.get("formation_id") or raw.get("fid") or "").strip()
        if dest <= 0 or not fid:
            continue
        if fid in marching or fid in combat:
            continue
        row = {
            "tag": tag,
            "from_id": station,
            "dest_id": dest,
            "to_id": int(raw.get("to_id") or raw.get("province_id") or 0),
            "defender_tag": _norm_tag(raw.get("defender_tag") or raw.get("def_tag")),
            "formation_id": fid,
            "has_own_path": bool(raw.get("has_own_path", False)),
            "at_rear": bool(raw.get("at_rear") or raw.get("at_capital")),
            "at_capital": bool(raw.get("at_capital", False)),
            "dest_is_own_land": (
                True
                if raw.get("dest_is_own_land") is None
                else bool(raw.get("dest_is_own_land"))
            ),
            "already_marching": bool(raw.get("already_marching") or raw.get("is_marching")),
            "in_combat": bool(raw.get("in_combat") or raw.get("is_in_combat")),
            "live_api": "enqueue_own_land_march",
        }
        row["score"] = _score_one_march(row, player_tag=player)
        if not should_enqueue_march(row, player_tag=player, marches_today=0, max_marches=cap):
            continue
        scored.append(row)
    scored.sort(
        key=lambda r: (-float(r["score"]), r["tag"], int(r["dest_id"]))
    )
    picks = scored[:cap]
    return {
        "ok": True,
        "picks": picks,
        "marched_n": len(picks),
        "eligible_n": len(scored),
        "player_tag": player,
        "day_index": int(day_index),
        "max_marches": cap,
        "live_api": "enqueue_own_land_march",
        "never_instant": True,
    }


def plan_follow_on(
    aar: Mapping[str, Any],
    *,
    player_tag: str = "",
    open_hexes: Optional[Sequence[int]] = None,
    max_follow_on: int = HARD_MAX_FOLLOW_ON,
) -> Dict[str, Any]:
    """0–1 start_land_battle on the AAR next hex. Never execute_province_assault."""
    cap = max(0, min(HARD_MAX_FOLLOW_ON, int(max_follow_on)))
    empty = {
        "ok": True,
        "picks": [],
        "started_n": 0,
        "player_tag": _norm_tag(player_tag),
        "max_follow_on": cap,
        "live_api": "start_land_battle",
        "never_instant": True,
    }
    if cap <= 0 or not should_follow_on(
        aar,
        player_tag=player_tag,
        open_hexes=open_hexes,
        follow_ons_today=0,
        max_follow_on=cap,
    ):
        return empty
    fid = str(aar.get("fid") or aar.get("formation_id") or aar.get("att_fid") or "").strip()
    pick = {
        "tag": _norm_tag(aar.get("tag") or aar.get("att_tag")),
        "to_id": int(aar.get("next_pid") or 0),
        "from_id": int(aar.get("from_id") or aar.get("stage") or 0),
        "formation_id": fid,
        "live_api": "start_land_battle",
    }
    return {
        "ok": True,
        "picks": [pick],
        "started_n": 1,
        "player_tag": _norm_tag(player_tag),
        "max_follow_on": cap,
        "live_api": "start_land_battle",
        "never_instant": True,
    }


def ger_rear_march_opp() -> Dict[str, Any]:
    return {
        "tag": "GER",
        "from_id": 710001,
        "dest_id": GER_FRONT_STAGING,
        "to_id": GER_FRONT_ENEMY,
        "defender_tag": "FRA",
        "formation_id": "ger_rear_1",
        "has_own_path": True,
        "at_rear": True,
        "at_capital": True,
        "dest_is_own_land": True,
        "already_marching": False,
        "in_combat": False,
    }


def build_land_battle_ai_campaign_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []

    ger = plan_marches([ger_rear_march_opp()], player_tag="USA", day_index=0)
    if (
        ger.get("marched_n") == 1
        and ger["picks"]
        and int(ger["picks"][0].get("dest_id") or 0) == GER_FRONT_STAGING
        and ger.get("live_api") == "enqueue_own_land_march"
    ):
        passes.append("ger_rear_marches_710173")
    else:
        fails.append("ger_rear_marches_710173")

    scored = score_march_to_front([ger_rear_march_opp()], player_tag="USA")
    if (
        isinstance(scored, list)
        and scored
        and int(scored[0].get("dest_id") or 0) == GER_FRONT_STAGING
        and float(scored[0].get("score") or 0.0) > 0.0
    ):
        passes.append("score_march_dest_710173")
    else:
        fails.append("score_march_dest_710173")

    player = plan_marches([ger_rear_march_opp()], player_tag="GER", day_index=0)
    if int(player.get("marched_n") or 0) == 0:
        passes.append("player_tag_never_marched")
    else:
        fails.append("player_tag_never_marched")

    busy = dict(ger_rear_march_opp())
    busy["already_marching"] = True
    if not should_enqueue_march(busy, player_tag="USA"):
        passes.append("skip_already_marching")
    else:
        fails.append("skip_already_marching")
    fight = dict(ger_rear_march_opp())
    fight["in_combat"] = True
    if not should_enqueue_march(fight, player_tag="USA"):
        passes.append("skip_in_combat")
    else:
        fails.append("skip_in_combat")
    foreign = dict(ger_rear_march_opp())
    foreign["dest_is_own_land"] = False
    if not should_enqueue_march(foreign, player_tag="USA"):
        passes.append("skip_foreign_dest")
    else:
        fails.append("skip_foreign_dest")
    if not should_enqueue_march(ger_rear_march_opp(), player_tag="USA", marches_today=1):
        passes.append("march_budget_one")
    else:
        fails.append("march_budget_one")

    win_aar = {
        "winner": "attacker",
        "next_pid": 710740,
        "fid": "ger_1",
        "tag": "GER",
        "from_id": GER_FRONT_ENEMY,
    }
    follow = plan_follow_on(win_aar, player_tag="USA")
    if (
        follow.get("started_n") == 1
        and follow["picks"]
        and int(follow["picks"][0].get("to_id") or 0) == 710740
        and follow["picks"][0].get("formation_id") == "ger_1"
        and follow.get("live_api") == "start_land_battle"
    ):
        passes.append("follow_on_after_win")
    else:
        fails.append("follow_on_after_win")
    if should_follow_on(win_aar, player_tag="USA", expected_fid="ger_1"):
        passes.append("same_fid_follow_on")
    else:
        fails.append("same_fid_follow_on")

    hold_aar = {
        "winner": "defender",
        "next_pid": 710740,
        "fid": "ger_1",
        "tag": "GER",
        "from_id": GER_FRONT_STAGING,
    }
    if not should_follow_on(hold_aar, player_tag="USA") and int(
        plan_follow_on(hold_aar, player_tag="USA").get("started_n") or 0
    ) == 0:
        passes.append("no_follow_on_defender_win")
    else:
        fails.append("no_follow_on_defender_win")

    open_hex = plan_follow_on(win_aar, player_tag="USA", open_hexes=[710740])
    if int(open_hex.get("started_n") or 0) == 0:
        passes.append("no_follow_on_already_open")
    else:
        fails.append("no_follow_on_already_open")

    ai = AI_GD.read_text(encoding="utf-8") if AI_GD.is_file() else ""
    bm = BM_GD.read_text(encoding="utf-8") if BM_GD.is_file() else ""
    fm = FM_GD.read_text(encoding="utf-8") if FM_GD.is_file() else ""
    if "func plan_marches" in ai and "func plan_follow_on" in ai:
        passes.append("ai_gd_campaign_api")
    else:
        fails.append("ai_gd_campaign_api")
    march_body = extract_gd_func_body(ai, "plan_marches")
    follow_plan = extract_gd_func_body(ai, "plan_follow_on")
    if march_body and "enqueue_own_land_march" in march_body:
        passes.append("ai_gd_march_api")
    else:
        fails.append("ai_gd_march_api")
    if (
        follow_plan
        and "start_land_battle" in follow_plan
        and "execute_province_assault" not in march_body
        and "execute_province_assault" not in follow_plan
    ):
        passes.append("ai_gd_start_not_execute")
    else:
        fails.append("ai_gd_start_not_execute")
    if "func try_ai_start_land_battles" in bm:
        passes.append("bm_try_ai")
    else:
        fails.append("bm_try_ai")
    try_body = extract_gd_func_body(bm, "try_ai_start_land_battles")
    if try_body and "enqueue_own_land_march" in try_body:
        passes.append("bm_calls_enqueue_march")
    else:
        fails.append("bm_calls_enqueue_march")
    if try_body and "start_land_battle" in try_body:
        passes.append("bm_calls_start")
    else:
        fails.append("bm_calls_start")
    if try_body and "execute_province_assault" not in try_body:
        passes.append("bm_no_instant_resolve")
    else:
        fails.append("bm_no_instant_resolve")
    follow_body = extract_gd_func_body(bm, "try_ai_follow_on_after_win")
    if follow_body and "start_land_battle" in follow_body:
        passes.append("bm_follow_on_start")
    else:
        fails.append("bm_follow_on_start")
    if follow_body and "execute_province_assault" not in follow_body:
        passes.append("bm_follow_on_no_execute")
    else:
        fails.append("bm_follow_on_no_execute")
    if "func list_marches" in fm:
        passes.append("fm_list_marches")
    else:
        fails.append("fm_list_marches")
    if "EOA_AI_LAND_BATTLES" in try_body:
        passes.append("bm_killswitch")
    else:
        fails.append("bm_killswitch")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "summary": "land_battle_ai_campaign · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "spare_march_to_front_plus_one_follow_on_start",
        "killswitch": "EOA_AI_LAND_BATTLES=0",
        "max_marches_per_day": HARD_MAX_MARCHES_PER_DAY,
        "max_follow_on": HARD_MAX_FOLLOW_ON,
        "max_starts_per_day": HARD_MAX_STARTS_PER_DAY,
    }


def land_battle_ai_campaign_integrity() -> Dict[str, Any]:
    p = build_land_battle_ai_campaign_product()
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
        "killswitch": p.get("killswitch"),
        "policy": p.get("policy"),
    }
