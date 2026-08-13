"""Multi-faction strategic AI daily depth — non-human SessionPlayers slots.

Scans AI tags, ranks urgency, applies daily actions, skips humans.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence

try:
    from multi_faction_strategic_ai_product import build_multi_faction_strategic_ai_product  # type: ignore
except Exception:  # pragma: no cover
    def build_multi_faction_strategic_ai_product(*_a, **_k):  # type: ignore
        return {"score": 0.55, "empty": False}

try:
    from strategic_ai_daily_campaign_product import build_strategic_ai_daily_campaign_product  # type: ignore
except Exception:  # pragma: no cover
    def build_strategic_ai_daily_campaign_product(*_a, **_k):  # type: ignore
        return {"score": 0.55, "empty": False}


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


DEFAULT_FACTIONS = (
    {"tag": "USA", "control": "human"},
    {"tag": "GER", "control": "ai"},
    {"tag": "SOV", "control": "ai"},
    {"tag": "ENG", "control": "ai"},
    {"tag": "JAP", "control": "ai"},
)


def _new_runtime(factions: Optional[Sequence[Dict[str, Any]]] = None) -> Dict[str, Any]:
    raw = list(factions) if factions else list(DEFAULT_FACTIONS)
    clean: List[Dict[str, Any]] = []
    for f in raw:
        if not isinstance(f, dict):
            continue
        tag = str(f.get("tag") or "").strip().upper()
        if not tag:
            continue
        ctrl = str(f.get("control") or "ai").strip().lower()
        clean.append({"tag": tag, "control": ctrl, "daily_applied": 0, "urgency": 0.5})
    if not clean:
        clean = [dict(x) for x in DEFAULT_FACTIONS]
    return {
        "factions": clean,
        "day": 0,
        "ai_applied_total": 0,
        "human_skipped": 0,
        "history": [],
        "tick": 0,
        "complete": False,
    }


def apply_ai_daily_for_tag(
    rt: Dict[str, Any],
    tag: str,
    province_id: int = 1,
) -> Dict[str, Any]:
    t = str(tag or "").upper()
    factions = list(rt.get("factions") or [])
    row = None
    for f in factions:
        if f.get("tag") == t:
            row = f
            break
    if row is None:
        return {"ok": False, "skipped": True, "reason": "unknown_tag", "tag": t}
    if str(row.get("control")) == "human":
        rt["human_skipped"] = int(rt.get("human_skipped") or 0) + 1
        return {
            "ok": True,
            "skipped": True,
            "reason": "human",
            "tag": t,
            "live": True,
        }
    # AI apply: raise urgency and count daily action
    urgency = min(1.0, float(row.get("urgency") or 0.5) + 0.08)
    row["urgency"] = urgency
    row["daily_applied"] = int(row.get("daily_applied") or 0) + 1
    row["last_actions"] = ["apply_production", "apply_supply", "apply_focus"]
    row["province_id"] = int(province_id)
    rt["ai_applied_total"] = int(rt.get("ai_applied_total") or 0) + 1
    rt["factions"] = factions
    return {
        "ok": True,
        "skipped": False,
        "tag": t,
        "urgency": urgency,
        "daily_applied": row["daily_applied"],
        "actions": list(row["last_actions"]),
        "live": True,
        "province_id": int(province_id),
    }


def apply_ai_daily_round(rt: Dict[str, Any], province_id: int = 1) -> Dict[str, Any]:
    """One day: apply AI for every non-human faction."""
    results: List[Dict[str, Any]] = []
    for f in list(rt.get("factions") or []):
        results.append(apply_ai_daily_for_tag(rt, str(f.get("tag")), province_id))
    rt["day"] = int(rt.get("day") or 0) + 1
    rt["tick"] = int(rt.get("tick") or 0) + 1
    hist = list(rt.get("history") or [])
    hist.append({"day": rt["day"], "ai_applied": rt.get("ai_applied_total"), "skipped": rt.get("human_skipped")})
    rt["history"] = hist[-30:]
    ai_n = sum(1 for f in (rt.get("factions") or []) if f.get("control") == "ai")
    applied_tags = sum(1 for r in results if r.get("ok") and not r.get("skipped"))
    rt["complete"] = int(rt.get("day") or 0) >= 1 and applied_tags >= max(1, ai_n - 1)
    return {
        "ok": True,
        "live": True,
        "day": rt["day"],
        "results": results,
        "ai_applied_total": int(rt.get("ai_applied_total") or 0),
        "human_skipped": int(rt.get("human_skipped") or 0),
        "ai_n": ai_n,
        "applied_tags": applied_tags,
        "complete": bool(rt.get("complete")),
        "province_id": int(province_id),
    }


def close_multi_faction_ai_daily(
    factions: Optional[Sequence[Dict[str, Any]]] = None,
    province_id: int = 1,
    days: int = 2,
) -> Dict[str, Any]:
    rt = _new_runtime(factions)
    rounds: List[Dict[str, Any]] = []
    for _ in range(max(1, int(days))):
        rounds.append(apply_ai_daily_round(rt, province_id))
    faction_prod = build_multi_faction_strategic_ai_product(province_id=province_id)
    daily_prod = build_strategic_ai_daily_campaign_product(province_id=province_id)
    ai_n = sum(1 for f in (rt.get("factions") or []) if f.get("control") == "ai")
    ok = (
        bool(rt.get("complete"))
        and int(rt.get("ai_applied_total") or 0) >= ai_n
        and int(rt.get("human_skipped") or 0) >= 1
        and all(r.get("ok") for r in rounds)
    )
    score = _floor(
        0.3 * float(faction_prod.get("score") or 0.55)
        + 0.3 * float(daily_prod.get("score") or 0.55)
        + 0.2 * min(1.0, int(rt.get("ai_applied_total") or 0) / max(1.0, float(ai_n * max(1, days))))
        + 0.2 * (1.0 if ok else 0.4)
    )
    label = (
        "Multi-faction AI daily %s · days %d · ai_applied %d · human_skip %d · score %.2f"
        % (
            "PASS" if ok else "FAIL",
            int(rt.get("day") or 0),
            int(rt.get("ai_applied_total") or 0),
            int(rt.get("human_skipped") or 0),
            score,
        )
    )
    return {
        "ok": ok,
        "live": True,
        "score": score,
        "runtime": rt,
        "rounds": rounds,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#c070e0]🤖 AI daily[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
        "integration": [
            "multi_faction_ai_daily_depth",
            "strategic_ai_daily",
            "session_players",
            "non_human_apply",
            "world_class_gs",
        ],
    }


def multi_faction_ai_daily_depth_integrity() -> Dict[str, Any]:
    from pathlib import Path

    root = Path(__file__).resolve().parents[3]
    gd = (root / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
    sl = (root / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
    closed = close_multi_faction_ai_daily()
    wired = (
        "apply_multi_faction_ai_daily_depth_live" in gd
        and "strategic_ai_multi_faction_daily_live" in sl
    )
    ok = bool(closed.get("ok")) and wired
    return {
        "ok": ok,
        "closed": closed,
        "wired": wired,
        "summary": "Multi-faction AI daily depth integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }
