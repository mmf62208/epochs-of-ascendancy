"""Interactive multi-AI day — budgeted non-player major actions for F5 light sim.

Plans an ordered apply queue for one game day so graphical play feels alive over
multi-day advances WITHOUT full daily AI combat cascade (OOM risk on dense boards).

Live path: GameData.apply_interactive_multi_ai_day_live + TimeManager day flush
when is_interactive_light_sim. Headless year multi-AI path is separate and intact.

Budget defaults (hard caps):
  max_production applies: 3 (clamp 1–4)
  max soft theater ticks: 1
  day_budget total items: 4

Killswitch (runtime): EOA_INTERACTIVE_MULTI_AI=0
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence

ROOT = Path(__file__).resolve().parents[3]

DEFAULT_MAJOR_TAGS = ("GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP", "POL")
DEFAULT_PLAYER_TAG = "USA"
DEFAULT_MAX_PRODUCTION = 3
DEFAULT_MAX_SOFT_TICKS = 1
DEFAULT_DAY_BUDGET = 4
HARD_MAX_PRODUCTION = 4

# Soft personality aggression weights (mirrors faction_personality_ai_product traits).
# Used to bias which non-player majors get the daily production budget first.
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


def _norm_tag(tag: Any) -> str:
    return str(tag or "").strip().upper()


def personality_aggression(tag: str) -> float:
    t = _norm_tag(tag)
    if t in PERSONALITY_AGGRESSION:
        return float(PERSONALITY_AGGRESSION[t])
    return 0.5


def non_player_majors(
    major_tags: Optional[Sequence[str]] = None,
    player_tag: str = DEFAULT_PLAYER_TAG,
) -> List[str]:
    """Ordered major tags excluding the human/player tag."""
    majors = [_norm_tag(t) for t in (major_tags or DEFAULT_MAJOR_TAGS) if _norm_tag(t)]
    if not majors:
        majors = list(DEFAULT_MAJOR_TAGS)
    player = _norm_tag(player_tag) or DEFAULT_PLAYER_TAG
    seen: Dict[str, bool] = {}
    out: List[str] = []
    for t in majors:
        if t == player or t in seen:
            continue
        seen[t] = True
        out.append(t)
    return out


def round_robin_order(candidates: Sequence[str], day_index: int = 0) -> List[str]:
    """Rotate candidates so successive days cover different majors first."""
    tags = [t for t in candidates if t]
    if not tags:
        return []
    n = len(tags)
    start = int(day_index) % n
    return list(tags[start:]) + list(tags[:start])


def personality_rank_order(
    candidates: Sequence[str],
    day_index: int = 0,
    *,
    use_personality: bool = True,
) -> List[str]:
    """Order non-player majors: personality aggression desc, then RR rotate for fairness.

    Day index rotates the top of the aggression-sorted list so lower-aggression
    majors still get production slots over multi-day runs (not pure always-GER).
    """
    tags = [t for t in candidates if t]
    if not tags:
        return []
    if not use_personality:
        return round_robin_order(tags, day_index)
    # Stable sort: higher aggression first; tag for ties
    ranked = sorted(
        tags,
        key=lambda t: (-personality_aggression(t), t),
    )
    # RR rotate among ranked so day 0 = most aggressive, day 1 shifts window
    return round_robin_order(ranked, day_index)


def build_interactive_multi_ai_day_queue(
    major_tags: Optional[Sequence[str]] = None,
    player_tag: str = DEFAULT_PLAYER_TAG,
    *,
    day_index: int = 0,
    max_production: int = DEFAULT_MAX_PRODUCTION,
    max_soft_ticks: int = DEFAULT_MAX_SOFT_TICKS,
    day_budget: int = DEFAULT_DAY_BUDGET,
    use_personality: bool = True,
) -> Dict[str, Any]:
    """Build ordered apply queue of production / soft tick for non-player majors.

    Returns integrity_ok when queue is valid under the hard budget (empty queue
    is ok only when there are no non-player majors).
    """
    player = _norm_tag(player_tag) or DEFAULT_PLAYER_TAG
    candidates = non_player_majors(major_tags, player)
    ordered = personality_rank_order(
        candidates, day_index, use_personality=bool(use_personality)
    )

    prod_cap = max(1, min(HARD_MAX_PRODUCTION, int(max_production)))
    soft_cap = max(0, min(1, int(max_soft_ticks)))
    budget = max(1, min(HARD_MAX_PRODUCTION + 1, int(day_budget)))

    queue: List[Dict[str, Any]] = []
    prod_tags: List[str] = []

    for tag in ordered:
        if len(queue) >= budget or len(prod_tags) >= prod_cap:
            break
        queue.append(
            {
                "tag": tag,
                "action": "apply_production_for_tag",
                "live_api": "apply_production_for_tag",
                "kind": "production",
                "aggression": personality_aggression(tag),
                "scoped_tag": tag,
            }
        )
        prod_tags.append(tag)

    soft_n = 0
    soft_tag = ""
    if soft_cap > 0 and len(queue) < budget and ordered:
        # Prefer a major not already production-applied this day.
        pick = ""
        for tag in ordered:
            if tag not in prod_tags:
                pick = tag
                break
        if not pick:
            # All majors already in production batch — soft on first RR major.
            pick = ordered[0]
        queue.append(
            {
                "tag": pick,
                "action": "apply_supply",
                "live_api": "apply_supply",
                "kind": "soft_theater_tick",
                "scoped_tag": pick,
            }
        )
        soft_n = 1
        soft_tag = pick

    production_n = len(prod_tags)
    integrity_ok = True
    if candidates and production_n < 1:
        integrity_ok = False
    if production_n > HARD_MAX_PRODUCTION:
        integrity_ok = False
    if soft_n > 1:
        integrity_ok = False
    if len(queue) > budget:
        integrity_ok = False
    # Empty board (no non-player majors) is a valid no-op day.
    if not candidates:
        integrity_ok = True

    return {
        "ok": integrity_ok,
        "integrity_ok": integrity_ok,
        "empty": len(queue) == 0,
        "queue": queue,
        "production_n": production_n,
        "soft_n": soft_n,
        "soft_tag": soft_tag,
        "prod_tags": prod_tags,
        "player_tag": player,
        "candidates": candidates,
        "ordered": ordered,
        "use_personality": bool(use_personality),
        "day_index": int(day_index),
        "budget": {
            "max_production": prod_cap,
            "max_soft_ticks": soft_cap,
            "day_budget": budget,
            "hard_max_production": HARD_MAX_PRODUCTION,
        },
        "summary": (
            "Interactive multi-AI day · day=%d · prod=%d · soft=%d · queue=%d · player=%s · personality=%s · %s"
            % (
                int(day_index),
                production_n,
                soft_n,
                len(queue),
                player,
                "on" if use_personality else "off",
                "PASS" if integrity_ok else "FAIL",
            )
        ),
    }


def resolve_tag_scoped_apply_ops(queue: Sequence[Mapping[str, Any]]) -> List[Dict[str, Any]]:
    """Map planned queue items → tag-scoped live ops (never bare player apply_production).

    Production items MUST use live_api apply_production_for_tag with scoped_tag == item tag.
    """
    ops: List[Dict[str, Any]] = []
    for item in queue or []:
        if not isinstance(item, Mapping):
            continue
        tag = _norm_tag(item.get("tag") or item.get("scoped_tag"))
        kind = str(item.get("kind") or "")
        if kind == "production":
            ops.append(
                {
                    "tag": tag,
                    "live_api": "apply_production_for_tag",
                    "kind": "production",
                    "scoped_tag": tag,
                    "args": [tag],
                }
            )
        elif kind == "soft_theater_tick":
            ops.append(
                {
                    "tag": tag,
                    "live_api": "apply_supply",
                    "kind": "soft_theater_tick",
                    "scoped_tag": tag,
                    "args": [],
                }
            )
    return ops


def simulate_tag_stockpile_applies(
    ops: Sequence[Mapping[str, Any]],
    *,
    stockpiles: Optional[Dict[str, int]] = None,
    player_tag: str = DEFAULT_PLAYER_TAG,
) -> Dict[str, Any]:
    """Pure simulation: each production_for_tag op increments THAT tag's stock only.

    Proves planned prod_tags drive per-tag apply — player stock unchanged when not in ops.
    """
    stocks: Dict[str, int] = dict(stockpiles or {})
    player = _norm_tag(player_tag)
    stocks.setdefault(player, 0)
    before = dict(stocks)
    applied: List[Dict[str, Any]] = []
    for op in ops or []:
        if not isinstance(op, Mapping):
            continue
        api = str(op.get("live_api") or "")
        tag = _norm_tag(op.get("scoped_tag") or op.get("tag"))
        if api == "apply_production_for_tag" and tag:
            stocks[tag] = int(stocks.get(tag, 0)) + 1
            applied.append({"tag": tag, "delta": 1, "api": api})
        elif api == "apply_production":
            # Forbidden path: player-only mutation
            stocks[player] = int(stocks.get(player, 0)) + 1
            applied.append({"tag": player, "delta": 1, "api": api, "bug": True})
    deltas = {t: int(stocks.get(t, 0)) - int(before.get(t, 0)) for t in set(list(stocks) + list(before))}
    player_delta = int(deltas.get(player, 0))
    non_player_hits = [
        a for a in applied if a.get("tag") != player and not a.get("bug")
    ]
    ok = (
        all(not a.get("bug") for a in applied)
        and len(non_player_hits) == len(
            [o for o in ops if str(o.get("live_api")) == "apply_production_for_tag"]
        )
    )
    return {
        "ok": ok,
        "stockpiles_before": before,
        "stockpiles_after": stocks,
        "deltas": deltas,
        "player_tag": player,
        "player_delta": player_delta,
        "applied": applied,
        "non_player_hits": len(non_player_hits),
    }


def build_interactive_multi_ai_day_product(
    major_tags: Optional[Sequence[str]] = None,
    player_tag: str = DEFAULT_PLAYER_TAG,
    *,
    day_index: int = 0,
    max_production: int = DEFAULT_MAX_PRODUCTION,
    max_soft_ticks: int = DEFAULT_MAX_SOFT_TICKS,
    day_budget: int = DEFAULT_DAY_BUDGET,
    use_personality: bool = True,
) -> Dict[str, Any]:
    """Full plan product: queue + wiring checks (does not run Godot)."""
    plan = build_interactive_multi_ai_day_queue(
        major_tags,
        player_tag,
        day_index=day_index,
        max_production=max_production,
        max_soft_ticks=max_soft_ticks,
        day_budget=day_budget,
        use_personality=use_personality,
    )
    fails: List[str] = []
    passes: List[str] = []

    if plan.get("integrity_ok"):
        passes.append("queue_integrity")
    else:
        fails.append("queue_integrity_fail")

    if int(plan.get("production_n") or 0) <= HARD_MAX_PRODUCTION:
        passes.append("production_cap_ok")
    else:
        fails.append("production_over_cap")

    if int(plan.get("soft_n") or 0) <= 1:
        passes.append("soft_cap_ok")
    else:
        fails.append("soft_over_cap")

    # Player excluded from production queue
    player = str(plan.get("player_tag") or "")
    for item in plan.get("queue") or []:
        if str(item.get("tag") or "") == player and str(item.get("kind")) == "production":
            fails.append("player_in_production_queue")
            break
    else:
        passes.append("player_excluded")

    # RR advances across days when enough candidates
    cands = list(plan.get("candidates") or [])
    if len(cands) >= 2:
        q0 = build_interactive_multi_ai_day_queue(
            cands + [player],
            player,
            day_index=0,
            max_production=max_production,
            max_soft_ticks=0,
            day_budget=day_budget,
        )
        q1 = build_interactive_multi_ai_day_queue(
            cands + [player],
            player,
            day_index=1,
            max_production=max_production,
            max_soft_ticks=0,
            day_budget=day_budget,
        )
        first0 = (q0.get("prod_tags") or [None])[0]
        first1 = (q1.get("prod_tags") or [None])[0]
        if first0 != first1:
            passes.append("round_robin_rotates")
        else:
            fails.append("round_robin_stale")

    # Tag-scoped ops: production must never be bare apply_production (player path)
    ops = resolve_tag_scoped_apply_ops(plan.get("queue") or [])
    plan["apply_ops"] = ops
    for op in ops:
        if str(op.get("kind")) == "production":
            if str(op.get("live_api")) != "apply_production_for_tag":
                fails.append("prod_op_not_tag_scoped")
            if str(op.get("scoped_tag") or "") != str(op.get("tag") or ""):
                fails.append("prod_op_tag_mismatch")
            if str(op.get("tag") or "") == player:
                fails.append("prod_op_targets_player")
    if "prod_op_not_tag_scoped" not in fails and any(
        str(o.get("kind")) == "production" for o in ops
    ):
        passes.append("tag_scoped_production_ops")

    # Pure stockpile sim: prod_tags each get +1; player unchanged if not in ops
    sim = simulate_tag_stockpile_applies(ops, player_tag=player)
    plan["stockpile_sim"] = sim
    if sim.get("ok") and int(sim.get("player_delta") or 0) == 0:
        passes.append("stockpile_sim_player_untouched")
    else:
        fails.append("stockpile_sim_player_mutated_or_fail")
    for pt in plan.get("prod_tags") or []:
        if int((sim.get("deltas") or {}).get(str(pt), 0)) < 1:
            fails.append("prod_tag_no_stock_delta_%s" % pt)
            break
    else:
        if plan.get("prod_tags"):
            passes.append("prod_tags_drive_stock_deltas")

    # Wiring: GameData live API + TimeManager gate + killswitch string
    gd_path = ROOT / "scripts" / "autoload" / "GameData.gd"
    tm_path = ROOT / "scripts" / "autoload" / "TimeManager.gd"
    pm_path = ROOT / "scripts" / "autoload" / "ProductionManager.gd"
    if gd_path.is_file():
        gd = gd_path.read_text(encoding="utf-8")
        if "func apply_interactive_multi_ai_day_live" in gd:
            passes.append("gamedata_live_api")
        else:
            fails.append("missing_apply_interactive_multi_ai_day_live")
        if "EOA_INTERACTIVE_MULTI_AI" in gd:
            passes.append("gamedata_killswitch")
        else:
            fails.append("missing_gamedata_killswitch")
        if "func apply_production_for_tag" in gd:
            passes.append("gamedata_apply_production_for_tag")
        else:
            fails.append("missing_apply_production_for_tag")
        # Live multi-AI body must call apply_production_for_tag, not bare apply_production
        live_idx = gd.find("func apply_interactive_multi_ai_day_live")
        if live_idx >= 0:
            live_body = gd[live_idx : live_idx + 4500]
            if "apply_production_for_tag" in live_body:
                passes.append("live_calls_tag_scoped_apply")
            else:
                fails.append("live_missing_tag_scoped_apply")
            # Forbidden: player-scoped order-panel production inside multi-AI loop body.
            # Match real calls only (not comments): apply_order_panel_action( then apply_production
            import re as _re

            call_pat = _re.compile(
                r'apply_order_panel_action\s*\(\s*["\']apply_production["\']'
            )
            if call_pat.search(live_body):
                fails.append("live_still_uses_player_apply_production")
            else:
                passes.append("live_no_player_apply_production")
    else:
        fails.append("missing_gamedata")

    if pm_path.is_file():
        pm = pm_path.read_text(encoding="utf-8")
        if "func advance_days_for_country" in pm:
            passes.append("pm_advance_days_for_country")
        else:
            fails.append("missing_pm_advance_days_for_country")


    if tm_path.is_file():
        tm = tm_path.read_text(encoding="utf-8")
        if "apply_interactive_multi_ai_day_live" in tm:
            passes.append("timemanager_day_hook")
        else:
            fails.append("missing_timemanager_day_hook")
        if "_should_run_interactive_multi_ai" in tm:
            passes.append("timemanager_gate")
        else:
            fails.append("missing_timemanager_gate")
        if "EOA_INTERACTIVE_MULTI_AI" in tm:
            passes.append("timemanager_killswitch")
        else:
            fails.append("missing_timemanager_killswitch")
        # Interactive must not re-enable full daily AI combat (OOM history).
        if "_should_run_daily_ai_combat" in tm and "not is_interactive_light_sim" in tm:
            passes.append("daily_ai_combat_still_gated")
        else:
            fails.append("missing_daily_ai_combat_gate")
    else:
        fails.append("missing_timemanager")

    ok = len(fails) == 0 and bool(plan.get("ok"))
    return {
        "ok": ok,
        "empty": bool(plan.get("empty")),
        "status": "PASS" if ok else "FAIL",
        "plan": plan,
        "queue": plan.get("queue") or [],
        "production_n": plan.get("production_n"),
        "soft_n": plan.get("soft_n"),
        "player_tag": player,
        "candidates": cands,
        "day_index": int(day_index),
        "budget": plan.get("budget"),
        "pass": passes,
        "fail": fails,
        "summary": (
            "Interactive multi-AI day product · day=%d · prod=%d · soft=%d · %s"
            % (
                int(day_index),
                int(plan.get("production_n") or 0),
                int(plan.get("soft_n") or 0),
                "PASS" if ok else "FAIL",
            )
        ),
        "killswitch": "EOA_INTERACTIVE_MULTI_AI=0",
        "defaults": {
            "max_production": DEFAULT_MAX_PRODUCTION,
            "max_soft_ticks": DEFAULT_MAX_SOFT_TICKS,
            "day_budget": DEFAULT_DAY_BUDGET,
            "major_tags": list(DEFAULT_MAJOR_TAGS),
        },
        "integration": [
            "interactive_multi_ai_day_product",
            "year_multi_ai_campaign_product",
            "TimeManager.is_interactive_light_sim",
            "GameData.apply_interactive_multi_ai_day_live",
        ],
    }


def interactive_multi_ai_day_integrity(
    major_tags: Optional[Sequence[str]] = None,
    player_tag: str = DEFAULT_PLAYER_TAG,
    *,
    day_index: int = 0,
) -> Dict[str, Any]:
    p = build_interactive_multi_ai_day_product(
        major_tags,
        player_tag,
        day_index=day_index,
    )
    return {
        "ok": bool(p.get("ok")),
        "production_n": p.get("production_n"),
        "soft_n": p.get("soft_n"),
        "fail": p.get("fail") or [],
        "summary": p.get("summary"),
        "empty": bool(p.get("empty")),
        "killswitch": p.get("killswitch"),
    }
