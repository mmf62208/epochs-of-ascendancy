"""Budgeted AI infrastructure invest — start + daily days_remaining tick + save.

Interactive 20–60d must show invest → progress → complete for player and AI.
AI majors start at most one new provincial infra project per day, skip the
player tag, and prefer low-infra owned land near the capital or a live
border. Inputs are fixtures (not GIS). Personality ranks GER/SOV first but
does not drop FRA — infra is economy.

Live dual: InfrastructureDevelopmentManager.try_ai_start_infra_project +
tick_active_projects. TimeManager _maybe_run_ai_infra_invest on F5 day flush.
Killswitch: EOA_AI_INFRA=0 (also skipped when interactive multi-AI is off).
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
IDM_GD = ROOT / "scripts" / "map" / "InfrastructureDevelopmentManager.gd"
TM_GD = ROOT / "scripts" / "autoload" / "TimeManager.gd"
SL_GD = ROOT / "scripts" / "autoload" / "SaveLoadManager.gd"

HARD_MAX_STARTS_PER_DAY = 1
DEFAULT_PROJECT_DAYS = 14
INFRA_LEVEL_MIN = 0
INFRA_LEVEL_MAX = 22
DEFAULT_PLAYER_TAG = "GER"
DEFAULT_MAJOR_TAGS = ("GER", "SOV", "JAP", "FRA", "ITA", "USA", "ENG", "POL")

# Aggression mirrors faction_personality_ai_product. Infra uses a floor so
# low-aggression FRA still invests (economy, not just war).
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
PERSONALITY_INDUSTRY: Dict[str, float] = {
    "GER": 0.80,
    "SOV": 0.85,
    "USA": 0.95,
    "ENG": 0.70,
    "FRA": 0.65,
    "ITA": 0.55,
    "JAP": 0.70,
    "POL": 0.50,
}

SAVE_KEYS: Tuple[str, ...] = ("pid", "tag", "kind", "days_remaining")


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


def personality_invest_weight(tag: str) -> float:
    """Infra is economy: max(aggression, industry) with a floor so FRA invests."""
    t = _norm_tag(tag)
    agr = personality_aggression(t)
    industry = float(PERSONALITY_INDUSTRY.get(t, 0.60))
    return max(agr, industry, 0.55)


def should_ai_invest(tag: str, player_tag: str = DEFAULT_PLAYER_TAG) -> bool:
    t = _norm_tag(tag)
    player = _norm_tag(player_tag)
    if not t or t == player:
        return False
    return personality_invest_weight(t) >= 0.55


def _as_int(raw: Any, default: int = 0) -> int:
    try:
        return int(raw)
    except (TypeError, ValueError):
        return int(default)


def _province_pid(raw: Mapping[str, Any], fallback: Any = 0) -> int:
    return _as_int(raw.get("pid") or raw.get("province_id") or fallback, 0)


def _province_tag(raw: Mapping[str, Any]) -> str:
    return _norm_tag(raw.get("tag") or raw.get("owner") or raw.get("owner_tag"))


def score_infra_candidate(
    prov: Mapping[str, Any],
    *,
    player_tag: str = DEFAULT_PLAYER_TAG,
) -> float:
    tag = _province_tag(prov)
    if not tag or tag == _norm_tag(player_tag):
        return -1.0
    infra = _as_int(prov.get("infra") or prov.get("infrastructure") or prov.get("level"), 4)
    score = float(12 - infra) * 2.0
    if bool(prov.get("near_capital", False)):
        score += 8.0
    if bool(prov.get("on_live_border", False) or prov.get("live_border", False)):
        score += 7.0
    score += personality_invest_weight(tag) * 4.0
    return score


def rank_ai_infra_starts(
    provinces: Sequence[Mapping[str, Any]],
    *,
    player_tag: str = DEFAULT_PLAYER_TAG,
    day_index: int = 0,
    active_pids: Optional[Sequence[int]] = None,
    max_starts: int = HARD_MAX_STARTS_PER_DAY,
    tags: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Pick 0–1 new AI infra project (low-infra owned near capital or live border)."""
    player = _norm_tag(player_tag) or DEFAULT_PLAYER_TAG
    cap = max(1, min(1, int(max_starts)))
    busy = {int(x) for x in (active_pids or []) if int(x) > 0}
    allow_tags = None
    if tags is not None:
        allow_tags = {_norm_tag(t) for t in tags if _norm_tag(t)}

    scored: List[Dict[str, Any]] = []
    for raw in provinces or []:
        if not isinstance(raw, Mapping):
            continue
        tag = _province_tag(raw)
        if not tag or tag == player:
            continue
        if allow_tags is not None and tag not in allow_tags:
            continue
        if not should_ai_invest(tag, player):
            continue
        pid = _province_pid(raw)
        if pid <= 0 or pid in busy:
            continue
        if bool(raw.get("is_sea", False)):
            continue
        infra = _as_int(raw.get("infra") or raw.get("infrastructure") or raw.get("level"), 4)
        if infra >= INFRA_LEVEL_MAX:
            continue
        row = {
            "tag": tag,
            "pid": pid,
            "province_id": pid,
            "kind": "infrastructure",
            "axis": "infrastructure",
            "infra": infra,
            "near_capital": bool(raw.get("near_capital", False)),
            "on_live_border": bool(
                raw.get("on_live_border", False) or raw.get("live_border", False)
            ),
            "days_remaining": int(raw.get("days_remaining") or DEFAULT_PROJECT_DAYS),
            "live_api": "try_start_infrastructure_investment",
        }
        row["score"] = score_infra_candidate(row, player_tag=player)
        if row["score"] < 0.0:
            continue
        scored.append(row)

    scored.sort(key=lambda r: (-float(r["score"]), r["tag"], int(r["pid"])))
    # Near-tie rotate so FRA/ENG still take a day vs always-GER.
    if len(scored) > 1:
        top = float(scored[0]["score"])
        ties = [r for r in scored if top - float(r["score"]) <= 4.0]
        if len(ties) > 1:
            start = int(day_index) % len(ties)
            scored = ties[start:] + ties[:start] + [
                r for r in scored if top - float(r["score"]) > 4.0
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
        "live_api": "try_start_infrastructure_investment",
    }


def plan_ai_infra_invest_day(
    provinces: Sequence[Mapping[str, Any]],
    *,
    player_tag: str = DEFAULT_PLAYER_TAG,
    day_index: int = 0,
    active_pids: Optional[Sequence[int]] = None,
    tags: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    return rank_ai_infra_starts(
        provinces,
        player_tag=player_tag,
        day_index=day_index,
        active_pids=active_pids,
        max_starts=HARD_MAX_STARTS_PER_DAY,
        tags=tags,
    )


def start_project_from_pick(pick: Mapping[str, Any]) -> Dict[str, Any]:
    pid = _province_pid(pick)
    tag = _norm_tag(pick.get("tag") or pick.get("owner_tag"))
    infra = _as_int(pick.get("infra") or pick.get("starting_level"), 1)
    days = max(1, _as_int(pick.get("days_remaining"), DEFAULT_PROJECT_DAYS))
    return {
        "pid": pid,
        "province_id": pid,
        "tag": tag,
        "owner_tag": tag,
        "kind": str(pick.get("kind") or pick.get("axis") or "infrastructure"),
        "axis": str(pick.get("axis") or pick.get("kind") or "infrastructure"),
        "days_remaining": days,
        "starting_level": infra,
        "target_level": min(INFRA_LEVEL_MAX, max(INFRA_LEVEL_MIN, infra + 1)),
        "status": "active",
    }


def tick_active_projects(
    active_projects: Mapping[Any, Any],
    *,
    infra_levels: Optional[Mapping[Any, Any]] = None,
    days: int = 1,
    level_max: int = INFRA_LEVEL_MAX,
) -> Dict[str, Any]:
    """days_remaining -= days; at 0 mark complete and bump infra +1 (clamp)."""
    days_n = max(0, int(days))
    cap = max(INFRA_LEVEL_MIN, int(level_max))
    levels: Dict[int, int] = {}
    for k, v in dict(infra_levels or {}).items():
        pid = _as_int(k, 0)
        if pid > 0:
            levels[pid] = _as_int(v, 0)

    remaining: Dict[int, Dict[str, Any]] = {}
    completed: List[int] = []
    raw_items: List[Tuple[Any, Any]] = []
    if isinstance(active_projects, Mapping):
        raw_items = list(active_projects.items())
    for key, raw in raw_items:
        if not isinstance(raw, Mapping):
            continue
        pid = _province_pid(raw, key)
        if pid <= 0:
            continue
        row = dict(raw)
        tag = _norm_tag(row.get("tag") or row.get("owner_tag"))
        kind = str(row.get("kind") or row.get("axis") or "infrastructure")
        left = _as_int(row.get("days_remaining", row.get("days_left", 0)), 0)
        left = max(0, left - days_n)
        start_lv = _as_int(
            row.get("starting_level", levels.get(pid, row.get("infra", 1))),
            1,
        )
        row.update(
            {
                "pid": pid,
                "province_id": pid,
                "tag": tag,
                "owner_tag": tag,
                "kind": kind,
                "axis": str(row.get("axis") or kind),
                "days_remaining": left,
                "days_left": left,
            }
        )
        if left <= 0:
            cur = _as_int(levels.get(pid, start_lv), start_lv)
            new_lv = min(cap, max(INFRA_LEVEL_MIN, cur + 1))
            levels[pid] = new_lv
            row["status"] = "complete"
            row["infra_level"] = new_lv
            row["target_level"] = new_lv
            completed.append(pid)
        else:
            row["status"] = str(row.get("status") or "active")
            remaining[pid] = row

    return {
        "ok": True,
        "active_projects": remaining,
        "infra_levels": levels,
        "completed": completed,
        "completed_n": len(completed),
        "days": days_n,
    }


def _normalize_project_row(raw: Mapping[str, Any], key: Any = 0) -> Optional[Dict[str, Any]]:
    pid = _province_pid(raw, key)
    if pid <= 0:
        return None
    tag = _norm_tag(raw.get("tag") or raw.get("owner_tag"))
    kind = str(raw.get("kind") or raw.get("axis") or "infrastructure")
    return {
        "pid": pid,
        "province_id": pid,
        "tag": tag,
        "owner_tag": tag,
        "kind": kind,
        "axis": str(raw.get("axis") or kind),
        "days_remaining": max(
            0, _as_int(raw.get("days_remaining", raw.get("days_left", 0)), 0)
        ),
        "status": str(raw.get("status") or "active"),
        "starting_level": _as_int(raw.get("starting_level"), 0),
        "target_level": _as_int(raw.get("target_level"), 0),
    }


def serialize_active_projects(active_projects: Mapping[Any, Any]) -> Dict[str, Any]:
    out: Dict[str, Dict[str, Any]] = {}
    if isinstance(active_projects, Mapping):
        for key, raw in active_projects.items():
            if not isinstance(raw, Mapping):
                continue
            row = _normalize_project_row(raw, key)
            if row is None:
                continue
            out[str(row["pid"])] = row
    return {"version": 1, "active_projects": out}


def apply_active_projects(blob: Any) -> Dict[str, Any]:
    data = blob if isinstance(blob, Mapping) else {}
    raw_map = data.get("active_projects", data) if isinstance(data, Mapping) else {}
    restored: Dict[int, Dict[str, Any]] = {}
    if isinstance(raw_map, Mapping):
        for key, raw in raw_map.items():
            if not isinstance(raw, Mapping):
                continue
            row = _normalize_project_row(raw, key)
            if row is None:
                continue
            restored[int(row["pid"])] = row
    return {
        "ok": True,
        "empty": len(restored) == 0,
        "active_projects": restored,
    }


def roundtrip_active_projects(active_projects: Mapping[Any, Any]) -> Dict[str, Any]:
    blob = serialize_active_projects(active_projects)
    restored = apply_active_projects(blob)
    before = blob.get("active_projects") or {}
    after = {}
    for pid, row in (restored.get("active_projects") or {}).items():
        after[str(pid)] = row
    same_keys = True
    for pid_str, src in before.items():
        dst = after.get(str(pid_str)) or {}
        for key in SAVE_KEYS:
            if src.get(key) != dst.get(key):
                same_keys = False
                break
        if not same_keys:
            break
    if set(before.keys()) != set(after.keys()):
        same_keys = False
    return {
        "ok": same_keys and bool(restored.get("ok")),
        "same_keys": same_keys,
        "blob": blob,
        "restored": restored.get("active_projects") or {},
        "keys": list(SAVE_KEYS),
    }


def _default_fixture_provinces() -> List[Dict[str, Any]]:
    return [
        {
            "pid": 710173,
            "tag": "GER",
            "infra": 2,
            "near_capital": True,
            "on_live_border": False,
        },
        {
            "pid": 710180,
            "tag": "GER",
            "infra": 8,
            "near_capital": False,
            "on_live_border": True,
        },
        {
            "pid": 710739,
            "tag": "FRA",
            "infra": 3,
            "near_capital": True,
            "on_live_border": True,
        },
        {
            "pid": 711000,
            "tag": "SOV",
            "infra": 1,
            "near_capital": True,
            "on_live_border": False,
        },
        {
            "pid": 800001,
            "tag": "USA",
            "infra": 2,
            "near_capital": True,
            "on_live_border": False,
        },
    ]


def build_infra_ai_invest_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    fixtures = _default_fixture_provinces()

    # Among GER land: low-infra capital beats high-infra border.
    ger_only = plan_ai_infra_invest_day(
        [p for p in fixtures if p["tag"] == "GER"],
        player_tag="USA",
        day_index=0,
    )
    if (
        ger_only.get("started_n") == 1
        and ger_only["picks"][0]["tag"] == "GER"
        and ger_only["picks"][0]["pid"] == 710173
    ):
        passes.append("prefers_low_infra_near_capital")
    else:
        fails.append("prefers_low_infra_near_capital")

    # Hard budget 1 even with GER + FRA + SOV legal.
    mixed = plan_ai_infra_invest_day(fixtures, player_tag="USA", day_index=0)
    if mixed.get("started_n") == 1 and mixed.get("max_starts") == 1:
        passes.append("day_budget_one")
    else:
        fails.append("day_budget_one")
    if mixed.get("started_n") == 1 and mixed["picks"][0]["tag"] != "USA":
        passes.append("mixed_skips_player")
    else:
        fails.append("mixed_skips_player")

    # Never start for the human tag (FRA/SOV still legal).
    self_hit = plan_ai_infra_invest_day(fixtures, player_tag="GER")
    if (
        self_hit.get("started_n") == 1
        and self_hit["picks"][0]["tag"] != "GER"
    ):
        passes.append("skips_player_tag")
    else:
        fails.append("skips_player_tag")

    # Busy pid skipped.
    busy = plan_ai_infra_invest_day(
        fixtures, player_tag="USA", active_pids=[710173, 710180, 711000]
    )
    if busy.get("started_n") == 1 and busy["picks"][0]["tag"] == "FRA":
        passes.append("skips_busy_prefers_fra")
    else:
        fails.append("skips_busy_prefers_fra")

    # FRA still invests (not dropped by low aggression).
    fra_only = plan_ai_infra_invest_day(
        [p for p in fixtures if p["tag"] == "FRA"],
        player_tag="GER",
    )
    if fra_only.get("started_n") == 1 and fra_only["picks"][0]["tag"] == "FRA":
        passes.append("fra_still_invests")
    else:
        fails.append("fra_still_invests")
    if should_ai_invest("FRA", "GER") and should_ai_invest("GER", "USA"):
        passes.append("personality_ger_and_fra")
    else:
        fails.append("personality_ger_and_fra")
    if personality_invest_weight("GER") >= personality_invest_weight("FRA"):
        passes.append("ger_outranks_or_ties_fra")
    else:
        fails.append("ger_outranks_or_ties_fra")
    if personality_invest_weight("SOV") >= 0.70:
        passes.append("sov_still_invests")
    else:
        fails.append("sov_still_invests")

    # Progress tick: 3 days → complete + infra +1 clamp.
    started = start_project_from_pick(
        {
            "pid": 710173,
            "tag": "GER",
            "infra": 4,
            "days_remaining": 3,
        }
    )
    ticked = tick_active_projects(
        {710173: started},
        infra_levels={710173: 4},
        days=3,
    )
    if (
        ticked.get("completed_n") == 1
        and 710173 in (ticked.get("completed") or [])
        and int((ticked.get("infra_levels") or {}).get(710173, 0)) == 5
        and 710173 not in (ticked.get("active_projects") or {})
    ):
        passes.append("tick_completes_bump")
    else:
        fails.append("tick_completes_bump")

    mid = tick_active_projects({710173: started}, infra_levels={710173: 4}, days=1)
    if (
        mid.get("completed_n") == 0
        and int((mid.get("active_projects") or {}).get(710173, {}).get("days_remaining", -1))
        == 2
    ):
        passes.append("tick_decrements")
    else:
        fails.append("tick_decrements")

    clamped = tick_active_projects(
        {1: start_project_from_pick({"pid": 1, "tag": "GER", "infra": 22, "days_remaining": 1})},
        infra_levels={1: 22},
        days=1,
    )
    if int((clamped.get("infra_levels") or {}).get(1, 0)) == INFRA_LEVEL_MAX:
        passes.append("tick_clamps_level")
    else:
        fails.append("tick_clamps_level")

    rt = roundtrip_active_projects({710173: started})
    if rt.get("ok") and rt.get("same_keys"):
        passes.append("roundtrip_same_keys")
    else:
        fails.append("roundtrip_same_keys")

    idm = IDM_GD.read_text(encoding="utf-8") if IDM_GD.is_file() else ""
    tm = TM_GD.read_text(encoding="utf-8") if TM_GD.is_file() else ""
    sl = SL_GD.read_text(encoding="utf-8") if SL_GD.is_file() else ""

    if "func try_ai_start_infra_project" in idm:
        passes.append("idm_try_ai")
    else:
        fails.append("idm_try_ai")
    try_body = extract_gd_func_body(idm, "try_ai_start_infra_project")
    if try_body and (
        "try_start_infrastructure_investment" in try_body
        or "start_infrastructure_project" in try_body
    ):
        passes.append("idm_reuses_start")
    else:
        fails.append("idm_reuses_start")
    if "func tick_active_projects" in idm:
        passes.append("idm_tick")
    else:
        fails.append("idm_tick")
    tick_body = extract_gd_func_body(idm, "tick_active_projects")
    if tick_body and "days_remaining" in tick_body and "_complete_project" in tick_body:
        passes.append("idm_tick_completes")
    else:
        fails.append("idm_tick_completes")

    save_body = extract_gd_func_body(idm, "to_save_dict")
    if not save_body:
        save_body = extract_gd_func_body(idm, "get_save_data")
    save_ok = (
        "days_remaining" in save_body
        and ("pid" in save_body or "province_id" in save_body)
        and ("tag" in save_body or "owner_tag" in save_body)
        and ("kind" in save_body or "axis" in save_body)
    )
    if save_ok and "days_remaining" in idm and '"kind"' in idm:
        passes.append("idm_save_fields")
    else:
        fails.append("idm_save_fields")

    flush = extract_gd_func_body(tm, "_flush_sim_events")
    if flush and "_maybe_run_ai_infra_invest" in flush:
        passes.append("tm_interactive_hook")
    else:
        fails.append("tm_interactive_hook")
    if "func _maybe_run_ai_infra_invest" in tm:
        passes.append("tm_helper")
    else:
        fails.append("tm_helper")
    helper = extract_gd_func_body(tm, "_maybe_run_ai_infra_invest")
    if helper and "EOA_AI_INFRA" in helper and "_should_run_interactive_multi_ai" in helper:
        passes.append("tm_killswitch")
    else:
        fails.append("tm_killswitch")
    if helper and "try_ai_start_infra_project" in helper:
        passes.append("tm_calls_try_ai")
    else:
        fails.append("tm_calls_try_ai")

    if "InfrastructureDevelopmentManager.get_save_data" in sl:
        passes.append("saveload_still_gathers")
    else:
        fails.append("saveload_still_gathers")
    if "func apply_loaded_data" in idm:
        passes.append("idm_apply")
    else:
        fails.append("idm_apply")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "summary": "infra_ai_invest · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "budgeted_ai_infra_invest_days_remaining",
        "killswitch": "EOA_AI_INFRA=0",
        "save_keys": list(SAVE_KEYS),
        "max_starts": HARD_MAX_STARTS_PER_DAY,
    }


def infra_ai_invest_integrity() -> Dict[str, Any]:
    p = build_infra_ai_invest_product()
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
        "killswitch": p.get("killswitch"),
        "save_keys": list(p.get("save_keys") or SAVE_KEYS),
    }
