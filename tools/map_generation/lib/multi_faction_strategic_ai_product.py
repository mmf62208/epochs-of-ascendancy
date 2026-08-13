"""Multi-faction strategic AI product (deferred key item — first vertical).

Major-power AI board: per-faction domain priorities (combat/fleet/industry/HH/agent),
rank urgency across GER/FRA/ENG/USA/SOV/ITA/JAP, recommend scan → rank → execute.
Composes theater_command + domain products — not a full campaign AI, not multiplayer.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from campaign_execution import execution_integrity_gate  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore

try:
    from theater_command_product import build_theater_command_product  # type: ignore
except Exception:  # pragma: no cover
    def build_theater_command_product(province_id: int = 1, **_k):  # type: ignore
        return {
            "score": 0.55,
            "empty": False,
            "top_domain": "combat",
            "domain_count": 5,
            "domains": [
                {"domain": "combat", "score": 0.6, "leaf": "apply_assault"},
                {"domain": "fleet", "score": 0.55, "leaf": "apply_station"},
            ],
            "summary": "theater stub",
        }


MAJOR_TAGS = ("GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP")

# Faction doctrine weights (sum need not be 1 — used for re-rank of domain scores)
FACTION_DOCTRINE: Dict[str, Dict[str, float]] = {
    "GER": {"combat": 1.15, "industry": 1.1, "fleet": 0.85, "agent": 0.95, "hh": 0.9},
    "SOV": {"combat": 1.12, "industry": 1.08, "fleet": 0.75, "agent": 1.0, "hh": 0.95},
    "USA": {"combat": 1.0, "industry": 1.15, "fleet": 1.12, "agent": 0.9, "hh": 0.85},
    "ENG": {"combat": 0.95, "industry": 1.0, "fleet": 1.18, "agent": 0.95, "hh": 1.0},
    "FRA": {"combat": 1.05, "industry": 0.95, "fleet": 0.9, "agent": 0.9, "hh": 0.95},
    "ITA": {"combat": 1.0, "industry": 0.9, "fleet": 1.05, "agent": 0.95, "hh": 1.05},
    "JAP": {"combat": 1.05, "industry": 1.0, "fleet": 1.15, "agent": 1.05, "hh": 0.9},
}

DOMAIN_LEAF = {
    "combat": "apply_assault",
    "fleet": "apply_station",
    "industry": "apply_production",
    "hh": "apply_hh_commit",
    "agent": "apply_agent_dispatch",
}

PRODUCT_STEPS = ("scan_factions", "rank_priorities", "execute_top")

_STEP_META = {
    "scan_factions": {
        "action_id": "strategic_ai_scan",
        "leaf": "apply_focus",
        "label": "Step 0 — scan major factions",
    },
    "rank_priorities": {
        "action_id": "strategic_ai_rank",
        "leaf": "apply_station",
        "label": "Step 1 — rank multi-faction priorities",
    },
    "execute_top": {
        "action_id": "strategic_ai_execute",
        "leaf": "apply_assault",
        "label": "Step 2 — execute top faction AI action",
    },
}


def _norm(v: float) -> float:
    try:
        x = float(v)
    except (TypeError, ValueError):
        return 0.5
    if x > 2.0:
        x = x / 100.0
    return max(0.0, min(1.0, x))


def _floor(score: float, lo: float = 0.35) -> float:
    s = _norm(score)
    return s if s >= lo else max(lo, min(1.0, s + 0.2))


def faction_doctrine(tag: str) -> Dict[str, float]:
    t = str(tag or "").strip().upper()
    return dict(FACTION_DOCTRINE.get(t, {"combat": 1.0, "fleet": 1.0, "industry": 1.0, "hh": 1.0, "agent": 1.0}))


def plan_faction_ai(
    tag: str,
    *,
    province_id: int = 1,
    theater: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    """Build one faction's strategic AI plan from theater command + doctrine."""
    t = str(tag).strip().upper() or "GER"
    th = dict(theater) if isinstance(theater, Mapping) else build_theater_command_product(
        max(1, int(province_id)),
        fuel_level=0.55 + (hash(t) % 30) / 100.0,
        tank_progress=0.12 + (hash(t[::-1]) % 25) / 100.0,
        factories=12 + (hash(t) % 8),
    )
    doctrine = faction_doctrine(t)
    domains_in = list(th.get("domains") or [])
    ranked: List[Dict[str, Any]] = []
    for d in domains_in:
        if not isinstance(d, Mapping):
            continue
        dom = str(d.get("domain", "combat"))
        raw = _norm(float(d.get("score", 0.5) or 0.5))
        w = float(doctrine.get(dom, 1.0))
        sc = _floor(raw * w)
        ranked.append(
            {
                "domain": dom,
                "score": sc,
                "raw_score": raw,
                "weight": w,
                "leaf": str(d.get("leaf", DOMAIN_LEAF.get(dom, "apply_station"))),
                "summary": str(d.get("summary", ""))[:80],
            }
        )
    if not ranked:
        # Fallback domains from doctrine only
        for dom, w in doctrine.items():
            ranked.append(
                {
                    "domain": dom,
                    "score": _floor(0.5 * w),
                    "raw_score": 0.5,
                    "weight": w,
                    "leaf": DOMAIN_LEAF.get(dom, "apply_station"),
                    "summary": "",
                }
            )
    ranked.sort(key=lambda r: (-float(r["score"]), str(r["domain"])))
    top = ranked[0]
    urgency = _floor(
        0.55 * float(top["score"])
        + 0.25 * _norm(float(th.get("score", 0.55)))
        + 0.2 * min(1.0, len(ranked) / 5.0)
    )
    label = "AI %s · top %s · urgency %.2f · domains %d" % (
        t,
        top.get("domain"),
        urgency,
        len(ranked),
    )
    return {
        "tag": t,
        "top_domain": str(top.get("domain")),
        "top_leaf": str(top.get("leaf")),
        "top_score": float(top.get("score")),
        "urgency": urgency,
        "domains": ranked,
        "theater_score": _norm(float(th.get("score", 0.55))),
        "summary": label,
        "plain": label,
        "empty": False,
    }


def recommend_strategic_ai_step(
    faction_count: int,
    *,
    top_urgency: float = 0.5,
) -> Dict[str, Any]:
    if faction_count <= 0:
        step = "scan_factions"
        reason = "no factions — scan majors"
    elif top_urgency < 0.45:
        step = "rank_priorities"
        reason = "low urgency — re-rank faction priorities"
    else:
        step = "execute_top"
        reason = "execute highest-urgency faction action"
    meta = _STEP_META[step]
    return {
        "step": step,
        "action_id": meta["action_id"],
        "leaf": meta["leaf"],
        "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason),
        "empty": False,
    }


def build_multi_faction_strategic_ai_product(
    tags: Optional[Sequence[str]] = None,
    *,
    province_id: int = 1,
    max_factions: int = 7,
) -> Dict[str, Any]:
    """Multi-faction strategic AI product board for major powers."""
    use_tags = [str(t).strip().upper() for t in (tags or MAJOR_TAGS) if str(t).strip()]
    use_tags = use_tags[: max(1, int(max_factions))]
    if not use_tags:
        use_tags = list(MAJOR_TAGS)

    factions: List[Dict[str, Any]] = []
    for i, tag in enumerate(use_tags):
        pid = max(1, int(province_id) + i)
        plan = plan_faction_ai(tag, province_id=pid)
        factions.append(plan)
    factions.sort(key=lambda f: (-float(f.get("urgency", 0)), str(f.get("tag", ""))))

    top = factions[0] if factions else {
        "tag": "GER",
        "top_domain": "combat",
        "top_leaf": "apply_assault",
        "urgency": 0.45,
        "summary": "empty",
    }
    top_urgency = float(top.get("urgency", 0.45))
    faction_count = len(factions)
    score = _floor(
        0.4 * top_urgency
        + 0.3 * min(1.0, faction_count / 7.0)
        + 0.3
        * (
            sum(float(f.get("urgency", 0.5)) for f in factions) / float(max(1, faction_count))
        )
    )

    rec = recommend_strategic_ai_step(faction_count, top_urgency=top_urgency)

    step_scores = {
        "scan_factions": _floor(0.4 + 0.08 * min(7, faction_count)),
        "rank_priorities": _floor(0.45 + 0.25 * top_urgency),
        "execute_top": _floor(0.5 + 0.3 * top_urgency),
    }
    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    for i, step in enumerate(PRODUCT_STEPS):
        meta = _STEP_META[step]
        recommended = step == str(rec.get("step"))
        sc = step_scores[step]
        leaf = str(meta["leaf"])
        if step == "execute_top":
            leaf = str(top.get("top_leaf", leaf))
        lab = str(meta["label"])
        if recommended:
            lab = "★ " + lab
        lab = "%s · top %s/%s · score %.2f" % (
            lab,
            top.get("tag", "?"),
            top.get("top_domain", "?"),
            sc,
        )
        row = {
            "index": i,
            "step": step,
            "action_id": meta["action_id"],
            "leaf_action": leaf,
            "label": lab,
            "score": sc,
            "enabled": faction_count > 0 or step == "scan_factions",
            "recommended": recommended,
            "province_id": max(1, int(province_id)),
            "faction": top.get("tag", ""),
        }
        day_rows.append(row)
        apply_queue.append(
            {
                "action_id": leaf,
                "province_id": max(1, int(province_id)),
                "score": sc,
                "enabled": bool(row["enabled"]),
                "label": lab,
                "step": step,
                "product_action": meta["action_id"],
                "faction": top.get("tag", ""),
            }
        )

    # Per-faction apply entries (top 3 urgency)
    for f in factions[:3]:
        apply_queue.append(
            {
                "action_id": str(f.get("top_leaf", "apply_station")),
                "province_id": max(1, int(province_id)),
                "score": float(f.get("urgency", 0.5)),
                "enabled": True,
                "label": "AI %s · %s" % (f.get("tag"), f.get("top_domain")),
                "step": "execute_top",
                "product_action": "strategic_ai_faction_%s" % f.get("tag"),
                "faction": f.get("tag"),
            }
        )

    board_lines = [
        "%s · %s · urg %.2f"
        % (f.get("tag"), f.get("top_domain"), float(f.get("urgency", 0)))
        for f in factions
    ]
    actions: List[Dict[str, Any]] = [
        {
            "action_id": "multi_faction_strategic_ai_product",
            "label": "Run multi-faction strategic AI product",
            "enabled": True,
        },
        {
            "action_id": str(rec.get("action_id", "strategic_ai_scan")),
            "label": "Recommended: %s" % rec.get("step", "scan_factions"),
            "enabled": True,
        },
    ]
    for r in day_rows:
        actions.append(
            {
                "action_id": r["action_id"],
                "label": r["label"],
                "enabled": bool(r["enabled"]),
                "step": r["step"],
            }
        )

    label = (
        "Multi-faction strategic AI · majors %d · top %s/%s · urg %.2f · score %.2f"
        % (
            faction_count,
            top.get("tag", "—"),
            top.get("top_domain", "—"),
            top_urgency,
            score,
        )
    )
    plain_lines = [label, str(rec.get("summary", ""))] + board_lines
    for r in day_rows:
        plain_lines.append(str(r.get("label", "")))

    return {
        "factions": factions,
        "faction_count": faction_count,
        "tags": use_tags,
        "top_faction": str(top.get("tag", "")),
        "top_domain": str(top.get("top_domain", "")),
        "top_leaf": str(top.get("top_leaf", "")),
        "top_urgency": top_urgency,
        "board_lines": board_lines,
        "recommendation": rec,
        "day_rows": day_rows,
        "apply_queue": apply_queue,
        "actions": actions,
        "score": score,
        "ai_score": score,
        "province_id": max(1, int(province_id)),
        "apply_ready": faction_count > 0,
        "summary": label,
        "plain": "\n".join(ln for ln in plain_lines if ln),
        "bbcode": "[color=#6eb5ff]♟ Multi-faction strategic AI[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": faction_count <= 0,
        "integration": [
            "multi_faction_strategic_ai_product",
            "strategic_ai_scan",
            "strategic_ai_rank",
            "strategic_ai_execute",
            "major_9",
            "strategic_ai",
        ],
    }


def execute_strategic_ai_step(
    step: str,
    province_id: int = 1,
    *,
    tags: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    s = str(step or "scan_factions").strip().lower()
    if s.startswith("strategic_ai_"):
        s = s.replace("strategic_ai_", "")
        if s == "scan":
            s = "scan_factions"
        elif s == "rank":
            s = "rank_priorities"
        elif s == "execute":
            s = "execute_top"
    if s not in _STEP_META:
        s = "scan_factions"
    meta = _STEP_META[s]
    product = build_multi_faction_strategic_ai_product(tags, province_id=province_id)
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    q = [
        {
            "action_id": leaf,
            "province_id": max(1, int(province_id)),
            "score": score,
            "enabled": True,
            "label": meta["label"],
            "step": s,
            "product_action": meta["action_id"],
            "faction": product.get("top_faction", ""),
        }
    ]
    label = "Execute strategic AI %s · leaf %s · faction %s · score %.2f" % (
        s,
        leaf,
        product.get("top_faction", "?"),
        score,
    )
    return {
        "step": s,
        "leaf_action": leaf,
        "action_id": meta["action_id"],
        "apply_queue": q,
        "score": score,
        "province_id": max(1, int(province_id)),
        "faction": product.get("top_faction", ""),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6eb5ff]♟ AI %s[/color] [color=#8899aa]%s[/color]" % (s, label),
        "empty": False,
        "ok": True,
        "integration": ["execute_strategic_ai_step", s, leaf],
    }


def multi_faction_strategic_ai_integrity() -> Dict[str, Any]:
    product = build_multi_faction_strategic_ai_product()
    thin = build_multi_faction_strategic_ai_product(["GER", "FRA"])
    steps = [execute_strategic_ai_step(s, 1) for s in PRODUCT_STEPS]
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    tags = [str(f.get("tag")) for f in (product.get("factions") or [])]
    ok = (
        not bool(product.get("empty"))
        and int(product.get("faction_count", 0)) >= 5
        and len(set(tags)) >= 5
        and all(bool(s.get("ok")) for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and float(product.get("score", 0)) >= float(thin.get("score", 0)) * 0.85
    )
    return {
        "ok": ok,
        "faction_count": int(product.get("faction_count", 0)),
        "top_faction": str(product.get("top_faction", "")),
        "top_domain": str(product.get("top_domain", "")),
        "score": float(product.get("score", 0)),
        "gate": gate,
        "summary": "Multi-faction strategic AI integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_multi_faction_strategic_ai_product_loop() -> Dict[str, Any]:
    product = build_multi_faction_strategic_ai_product()
    gate = multi_faction_strategic_ai_integrity()
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 3
    label = (
        "Close multi-faction strategic AI · factions %d · top %s · %s"
        % (
            int(product.get("faction_count", 0)),
            product.get("top_faction", "—"),
            "PASS" if ok else "FAIL",
        )
    )
    return {
        "product": product,
        "gate": gate,
        "score": float(product.get("score", 0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#6eb5ff]✓ Multi-faction strategic AI[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": ok,
    }
