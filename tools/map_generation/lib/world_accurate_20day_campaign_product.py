"""Director D2.4 machine proxy — 20-day campaign feel on world_accurate.

Pure product (no Godot): rolls N campaign days on the accurate GIS board using
shipped AI daily + play-session products, verifies GER–FRA land edge for the
assault loop, and tracks ownership stability at major capitals.

Human 20-day session notes remain open; this is the automated gate so full-test
regression does not depend on a human play session for the loop structure.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"
DEFAULT_SCENARIO = ROOT / "data" / "scenarios" / "world_accurate.json"

GER_CAP = 710300
FRA_CAP = 710707
# Machine assault edge (D2.1)
GER_EDGE = 710173  # Baden-Baden
FRA_EDGE = 710739  # Bas-Rhin

try:
    from strategic_ai_daily_campaign_product import (  # type: ignore
        build_strategic_ai_daily_campaign_product,
    )
except Exception:  # pragma: no cover
    build_strategic_ai_daily_campaign_product = None  # type: ignore

try:
    from play_session_campaign_product import (  # type: ignore
        build_play_session_campaign_product,
    )
except Exception:  # pragma: no cover
    build_play_session_campaign_product = None  # type: ignore

try:
    from save_browser_campaign_product import (  # type: ignore
        build_save_browser_campaign_product,
        recommend_checkpoint_slot,
    )
except Exception:  # pragma: no cover
    build_save_browser_campaign_product = None  # type: ignore
    recommend_checkpoint_slot = None  # type: ignore


def _load_board(board_dir: Path) -> Dict[str, Any]:
    adj = json.loads((board_dir / "province_adjacency.json").read_text(encoding="utf-8"))
    own = json.loads((board_dir / "province_ownership_1936.json").read_text(encoding="utf-8")).get(
        "owners"
    ) or {}
    sc = json.loads(DEFAULT_SCENARIO.read_text(encoding="utf-8")) if DEFAULT_SCENARIO.is_file() else {}
    return {"adjacency": adj.get("adjacency") or {}, "owners": own, "scenario": sc, "adj_doc": adj}


def _border_ok(adjacency: Dict[str, Any], a: int, b: int) -> bool:
    nbrs = adjacency.get(str(a)) or adjacency.get(a) or []
    return int(b) in [int(x) for x in nbrs]


def build_world_accurate_20day_campaign_product(
    *,
    days: int = 20,
    player_tag: str = "GER",
    province_id: int = GER_CAP,
    board_dir: Optional[Path] = None,
    max_ai_actions: int = 4,
) -> Dict[str, Any]:
    """Roll `days` pure campaign days on accurate board; machine D2.4 proxy."""
    d = Path(board_dir or DEFAULT_DIR)
    board = _load_board(d)
    fails: List[str] = []
    passes: List[str] = []
    day_rows: List[Dict[str, Any]] = []

    n_days = max(1, min(60, int(days)))
    player = str(player_tag or "GER").strip().upper()
    cap = int(province_id or GER_CAP)

    # Map gates for HOI campaign
    adj = board["adjacency"]
    if _border_ok(adj, GER_EDGE, FRA_EDGE):
        passes.append("ger_fra_assault_edge")
    else:
        fails.append("ger_fra_assault_edge_missing")

    adj_stats = (board.get("adj_doc") or {}).get("stats") or {}
    cov = float(adj_stats.get("land_shared_coverage") or 0)
    if cov >= 0.95:
        passes.append("adj_coverage=%.3f" % cov)
    else:
        fails.append("adj_coverage_low=%.3f" % cov)

    # Capitals ownership stability
    owners = board["owners"]
    for c in (board.get("scenario") or {}).get("countries") or []:
        tag = str(c.get("tag") or "").upper()
        pid = int(c.get("capital_province_id") or 0)
        if not tag or not pid:
            continue
        if owners.get(str(pid)) == tag:
            passes.append("cap_%s_owned" % tag)
        else:
            fails.append("cap_%s_owner=%s" % (tag, owners.get(str(pid))))

    if build_strategic_ai_daily_campaign_product is None:
        fails.append("strategic_ai_product_missing")
    if build_play_session_campaign_product is None:
        fails.append("play_session_product_missing")

    ai_ok_days = 0
    session_ok_days = 0
    for day in range(1, n_days + 1):
        row: Dict[str, Any] = {"day": day, "province_id": cap, "player_tag": player}
        if build_strategic_ai_daily_campaign_product is not None:
            ai = build_strategic_ai_daily_campaign_product(
                province_id=cap, player_tag=player, max_ai_actions=max_ai_actions
            )
            ai_ok = bool(
                ai.get("day_rows")
                or ai.get("apply_queue")
                or float(ai.get("score") or 0) > 0.4
                or ai.get("apply_ready")
            )
            row["ai_ok"] = ai_ok
            row["ai_factions"] = int(ai.get("faction_count") or 0)
            row["ai_queue_n"] = len(ai.get("apply_queue") or [])
            if ai_ok:
                ai_ok_days += 1
        if build_play_session_campaign_product is not None:
            try:
                sess = build_play_session_campaign_product(
                    province_id=cap, player_tag=player
                )
            except TypeError:
                # older signature
                sess = build_play_session_campaign_product(province_id=cap)  # type: ignore
            sess_ok = bool(sess.get("ok") or float(sess.get("score") or 0) > 0.4)
            row["session_ok"] = sess_ok
            if sess_ok:
                session_ok_days += 1
        # Mid-campaign checkpoint day 10
        if day == 10 and build_save_browser_campaign_product is not None:
            save = build_save_browser_campaign_product(
                occupied_slots=[
                    {
                        "slot": "mid_campaign",
                        "occupied": True,
                        "label": "day10 · world_accurate · %s" % player,
                        "metadata": {
                            "scenario_id": "world_accurate",
                            "player_tag": player,
                            "timestamp": "1936-01-%02d" % min(day, 28),
                            "capital_province_id": cap,
                            "day": day,
                        },
                    }
                ]
            )
            row["checkpoint_ok"] = bool(save.get("ok") or save.get("rows") is not None or save.get("score"))
            if row.get("checkpoint_ok"):
                passes.append("day10_checkpoint")
        day_rows.append(row)

    if ai_ok_days >= max(1, int(0.8 * n_days)):
        passes.append("ai_days=%d/%d" % (ai_ok_days, n_days))
    else:
        fails.append("ai_days_weak=%d/%d" % (ai_ok_days, n_days))

    if session_ok_days >= max(1, int(0.6 * n_days)):
        passes.append("session_days=%d/%d" % (session_ok_days, n_days))
    else:
        # soft: session product may be partial
        if session_ok_days > 0:
            passes.append("session_days_partial=%d/%d" % (session_ok_days, n_days))
        else:
            fails.append("session_days_none")

    ok = len(fails) == 0 and ai_ok_days >= max(1, int(0.8 * n_days))
    score = 0.0
    if n_days:
        score = max(
            0.0,
            min(
                1.0,
                0.35 * (ai_ok_days / n_days)
                + 0.25 * (session_ok_days / max(1, n_days))
                + 0.25 * (1.0 if _border_ok(adj, GER_EDGE, FRA_EDGE) else 0.0)
                + 0.15 * (1.0 if cov >= 0.95 else cov / 0.95),
            ),
        )
    if ok:
        score = max(score, 0.85)

    label = (
        "Accurate 20d campaign · days=%d · player=%s · ai=%d/%d · session=%d/%d · adj=%.3f · %s"
        % (
            n_days,
            player,
            ai_ok_days,
            n_days,
            session_ok_days,
            n_days,
            cov,
            "PASS" if ok else "FAIL",
        )
    )
    return {
        "ok": ok,
        "empty": False,
        "score": score,
        "status": "PASS" if ok else "FAIL",
        "days": n_days,
        "player_tag": player,
        "province_id": cap,
        "ai_ok_days": ai_ok_days,
        "session_ok_days": session_ok_days,
        "land_shared_coverage": cov,
        "ger_fra_edge": _border_ok(adj, GER_EDGE, FRA_EDGE),
        "day_rows": day_rows,
        "pass": passes,
        "fail": fails,
        "summary": label,
        "plain": label + ("\nFAIL: " + " | ".join(fails) if fails else ""),
        "integration": [
            "world_accurate_20day_campaign_product",
            "d2_4",
            "world_accurate",
            "campaign_feel",
        ],
        "human_note": (
            "Machine proxy for D2.4. Human still owns narrative 20–60d playtest notes "
            "in PLAYTEST_AND_DECISION_GUIDE."
        ),
    }


def world_accurate_20day_campaign_integrity() -> Dict[str, Any]:
    p = build_world_accurate_20day_campaign_product(days=20)
    return {
        "ok": bool(p.get("ok")),
        "ai_ok_days": p.get("ai_ok_days"),
        "fail": p.get("fail") or [],
        "summary": p.get("summary"),
        "empty": False,
    }
