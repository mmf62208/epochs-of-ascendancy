"""Budgeted AI land-battle initiation — start_land_battle, never one-tick resolve.

Interactive 20–60d must not be player-only war. AI majors open at most one
multi-day fight per day on a live border, ranked by personality aggression
and a small vs-player bonus. Full simulate_daily_ai_combat stays off in F5
(OOM history).
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence

ROOT = Path(__file__).resolve().parents[3]
AI_GD = ROOT / "scripts" / "combat" / "LandBattleAi.gd"
BM_GD = ROOT / "scripts" / "combat" / "BattleManager.gd"
TM_GD = ROOT / "scripts" / "autoload" / "TimeManager.gd"

HARD_MAX_STARTS_PER_DAY = 1
HARD_MAX_OPEN_PER_TAG = 2
MIN_AGGRESSION_TO_START = 0.50
MIN_AGGRESSION_VS_PLAYER = 0.40
SCAN_TAGS_PER_DAY = 2

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


def score_opportunity(
    opp: Mapping[str, Any],
    *,
    player_tag: str = "",
) -> float:
    tag = _norm_tag(opp.get("tag") or opp.get("att_tag"))
    foe = _norm_tag(opp.get("defender_tag") or opp.get("def_tag"))
    player = _norm_tag(player_tag)
    score = personality_aggression(tag) * 10.0
    if foe and foe in PREFERRED_FOES.get(tag, ()):
        score += 2.5
    if player and foe == player:
        score += 4.0
    if bool(opp.get("has_formation", False)):
        score += 3.0
    dfn = float(opp.get("defender_power", 80.0) or 80.0)
    if dfn <= 60.0:
        score += 1.5
    elif dfn <= 75.0:
        score += 0.8
    return score


def should_initiate(
    opp: Mapping[str, Any],
    *,
    player_tag: str = "",
    open_for_tag: int = 0,
    max_open: int = HARD_MAX_OPEN_PER_TAG,
) -> bool:
    if int(open_for_tag) >= int(max_open):
        return False
    if not bool(opp.get("has_formation", False)):
        return False
    tag = _norm_tag(opp.get("tag") or opp.get("att_tag"))
    foe = _norm_tag(opp.get("defender_tag") or opp.get("def_tag"))
    player = _norm_tag(player_tag)
    if tag and tag == player:
        return False
    agr = personality_aggression(tag)
    vs_player = bool(player) and foe == player
    if vs_player:
        if agr < MIN_AGGRESSION_VS_PLAYER:
            return False
        return float(opp.get("score", 0.0)) >= 6.0
    if agr < MIN_AGGRESSION_TO_START:
        return False
    return float(opp.get("score", 0.0)) >= 7.0


def _hex_busy(from_id: int, to_id: int, open_hexes: Sequence[int]) -> bool:
    busy = {int(x) for x in (open_hexes or []) if int(x) > 0}
    return int(from_id) in busy or int(to_id) in busy


def rank_ai_battle_starts(
    opportunities: Sequence[Mapping[str, Any]],
    *,
    player_tag: str = "GER",
    day_index: int = 0,
    open_hexes: Optional[Sequence[int]] = None,
    open_per_tag: Optional[Mapping[str, int]] = None,
    max_starts: int = HARD_MAX_STARTS_PER_DAY,
) -> Dict[str, Any]:
    """Pick 0–1 (hard 2) start_land_battle rows. Never execute_province_assault."""
    player = _norm_tag(player_tag) or "GER"
    cap = max(1, min(2, int(max_starts)))
    hexes = list(open_hexes or [])
    counts: Dict[str, int] = {
        _norm_tag(k): int(v) for k, v in dict(open_per_tag or {}).items()
    }
    scored: List[Dict[str, Any]] = []
    for raw in opportunities or []:
        if not isinstance(raw, Mapping):
            continue
        tag = _norm_tag(raw.get("tag") or raw.get("att_tag"))
        if not tag or tag == player:
            continue
        to_id = int(raw.get("to_id") or raw.get("province_id") or 0)
        from_id = int(raw.get("from_id") or raw.get("from_province_id") or 0)
        if to_id <= 0 or from_id <= 0:
            continue
        if _hex_busy(from_id, to_id, hexes):
            continue
        row = {
            "tag": tag,
            "from_id": from_id,
            "to_id": to_id,
            "defender_tag": _norm_tag(raw.get("defender_tag") or raw.get("def_tag")),
            "formation_id": str(raw.get("formation_id") or raw.get("att_fid") or ""),
            "has_formation": bool(raw.get("has_formation", False))
            or bool(str(raw.get("formation_id") or raw.get("att_fid") or "").strip()),
            "defender_power": float(raw.get("defender_power", 80.0) or 80.0),
            "live_api": "start_land_battle",
        }
        row["score"] = score_opportunity(row, player_tag=player)
        if not should_initiate(
            row,
            player_tag=player,
            open_for_tag=int(counts.get(tag, 0)),
        ):
            continue
        scored.append(row)
    scored.sort(key=lambda r: (-float(r["score"]), r["tag"], int(r["to_id"])))
    # Near-tie rotate so FRA/POL take turns vs a GER player over a campaign.
    if len(scored) > 1:
        top = float(scored[0]["score"])
        ties = [r for r in scored if top - float(r["score"]) <= 2.0]
        if len(ties) > 1:
            start = int(day_index) % len(ties)
            scored = ties[start:] + ties[:start] + [
                r for r in scored if top - float(r["score"]) > 2.0
            ]
    picks = scored[:cap]
    return {
        "ok": True,
        "picks": picks,
        "started_n": len(picks),
        "eligible_n": len(scored),
        "player_tag": player,
        "day_index": int(day_index),
        "max_starts": cap,
        "live_api": "start_land_battle",
        "never_instant": True,
    }


def plan_ai_land_battle_day(
    opportunities: Sequence[Mapping[str, Any]],
    *,
    player_tag: str = "GER",
    day_index: int = 0,
    open_hexes: Optional[Sequence[int]] = None,
    open_per_tag: Optional[Mapping[str, int]] = None,
) -> Dict[str, Any]:
    return rank_ai_battle_starts(
        opportunities,
        player_tag=player_tag,
        day_index=day_index,
        open_hexes=open_hexes,
        open_per_tag=open_per_tag,
        max_starts=HARD_MAX_STARTS_PER_DAY,
    )


def build_land_battle_ai_init_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []

    # GER AI vs FRA Maginot while player is USA — must start.
    ger = plan_ai_land_battle_day(
        [
            {
                "tag": "GER",
                "from_id": 710173,
                "to_id": 710739,
                "defender_tag": "FRA",
                "formation_id": "ger_1",
                "has_formation": True,
                "defender_power": 70.0,
            }
        ],
        player_tag="USA",
        day_index=0,
    )
    if ger.get("started_n") == 1 and ger["picks"][0]["to_id"] == 710739:
        passes.append("ger_opens_maginot")
    else:
        fails.append("ger_opens_maginot")
    if ger.get("live_api") == "start_land_battle" and ger.get("never_instant"):
        passes.append("uses_start_not_resolve")
    else:
        fails.append("uses_start_not_resolve")

    # Player GER: FRA still contests (vs-player floor 0.40).
    fra = plan_ai_land_battle_day(
        [
            {
                "tag": "FRA",
                "from_id": 710739,
                "to_id": 710173,
                "defender_tag": "GER",
                "formation_id": "fra_1",
                "has_formation": True,
                "defender_power": 80.0,
            }
        ],
        player_tag="GER",
        day_index=0,
    )
    if fra.get("started_n") == 1 and fra["picks"][0]["tag"] == "FRA":
        passes.append("fra_contests_ger_player")
    else:
        fails.append("fra_contests_ger_player")

    # Never start for the human tag.
    self_hit = plan_ai_land_battle_day(
        [
            {
                "tag": "GER",
                "from_id": 710173,
                "to_id": 710739,
                "defender_tag": "FRA",
                "has_formation": True,
                "defender_power": 70.0,
            }
        ],
        player_tag="GER",
    )
    if self_hit.get("started_n") == 0:
        passes.append("skips_player_tag")
    else:
        fails.append("skips_player_tag")

    # Busy hex + already 2 open fights → skip.
    busy = plan_ai_land_battle_day(
        [
            {
                "tag": "GER",
                "from_id": 710173,
                "to_id": 710739,
                "defender_tag": "FRA",
                "has_formation": True,
                "defender_power": 70.0,
            }
        ],
        player_tag="USA",
        open_hexes=[710739],
    )
    if busy.get("started_n") == 0:
        passes.append("skips_open_hex")
    else:
        fails.append("skips_open_hex")
    capped = plan_ai_land_battle_day(
        [
            {
                "tag": "GER",
                "from_id": 710173,
                "to_id": 710739,
                "defender_tag": "FRA",
                "has_formation": True,
                "defender_power": 70.0,
            }
        ],
        player_tag="USA",
        open_per_tag={"GER": 2},
    )
    if capped.get("started_n") == 0:
        passes.append("caps_open_per_tag")
    else:
        fails.append("caps_open_per_tag")

    # No formation → skip.
    empty = plan_ai_land_battle_day(
        [
            {
                "tag": "GER",
                "from_id": 710173,
                "to_id": 710739,
                "defender_tag": "FRA",
                "has_formation": False,
                "defender_power": 70.0,
            }
        ],
        player_tag="USA",
    )
    if empty.get("started_n") == 0:
        passes.append("needs_formation")
    else:
        fails.append("needs_formation")

    # Hard budget 1 start even with two legal fronts.
    two = plan_ai_land_battle_day(
        [
            {
                "tag": "GER",
                "from_id": 710173,
                "to_id": 710739,
                "defender_tag": "FRA",
                "has_formation": True,
                "defender_power": 70.0,
            },
            {
                "tag": "JAP",
                "from_id": 900010,
                "to_id": 900011,
                "defender_tag": "CHI",
                "has_formation": True,
                "defender_power": 55.0,
            },
        ],
        player_tag="USA",
        day_index=0,
    )
    if two.get("started_n") == 1 and two.get("max_starts") == 1:
        passes.append("day_budget_one")
    else:
        fails.append("day_budget_one")

    ai = AI_GD.read_text(encoding="utf-8") if AI_GD.is_file() else ""
    bm = BM_GD.read_text(encoding="utf-8") if BM_GD.is_file() else ""
    tm = TM_GD.read_text(encoding="utf-8") if TM_GD.is_file() else ""
    if "func plan_day" in ai and "func should_initiate" in ai:
        passes.append("ai_gd_api")
    else:
        fails.append("ai_gd_api")
    if "func try_ai_start_land_battles" in bm:
        passes.append("bm_try_ai")
    else:
        fails.append("bm_try_ai")
    try_body = extract_gd_func_body(bm, "try_ai_start_land_battles")
    if try_body and "start_land_battle" in try_body:
        passes.append("bm_calls_start")
    else:
        fails.append("bm_calls_start")
    if try_body and "execute_province_assault" not in try_body:
        passes.append("bm_no_instant_resolve")
    else:
        fails.append("bm_no_instant_resolve")
    flush = extract_gd_func_body(tm, "_flush_sim_events")
    if flush and "_maybe_run_ai_land_battle_starts" in flush:
        passes.append("tm_interactive_hook")
    else:
        fails.append("tm_interactive_hook")
    if "func _maybe_run_ai_land_battle_starts" in tm:
        passes.append("tm_helper")
    else:
        fails.append("tm_helper")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "summary": "land_battle_ai_init · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "budgeted_start_land_battle_never_instant",
        "killswitch": "EOA_AI_LAND_BATTLES=0",
    }


def land_battle_ai_init_integrity() -> Dict[str, Any]:
    p = build_land_battle_ai_init_product()
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
        "killswitch": p.get("killswitch"),
    }
