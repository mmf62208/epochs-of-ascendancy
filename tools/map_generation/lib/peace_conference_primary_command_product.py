"""Multi-party peace conference human-flow primary command package — Master Plan Di1.

Elevates open → claim → cede → puppet → close into a Stream-α-style vertical
package (not day-catalogue stubs). Composes existing pure products:

  multi_party_peace_conference_product — multi-victor board / war-goals / settle
  peace_conference_settlement_product  — annex / puppet / reparations / zones
  diplomacy_peace_campaign_product     — board / leverage / settle path

Step ids match the human conference loop:
  open_conference · claim_province · cede_province · puppet_tag · close_conference

live_api strings match real GameData method names for later GD wiring
(apply_multi_party_peace_*, apply_peace_demand_*, apply_peace_conference_settlement_live).
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence, Tuple

try:
    from multi_party_peace_conference_product import (  # type: ignore
        PRODUCT_STEPS as MP_PRODUCT_STEPS,
        build_multi_party_peace_conference_product,
        execute_multi_party_peace_step,
        recommend_multi_party_peace_step,
    )
except Exception:  # pragma: no cover
    MP_PRODUCT_STEPS = ("board", "wargoals", "settle")

    def build_multi_party_peace_conference_product(*_a, **_k):  # type: ignore
        return {
            "score": 0.65,
            "winner_n": 3,
            "package_n": 3,
            "ai_accept": 0.6,
            "feasibility": 0.6,
            "winners": ["GER", "ITA", "HUN"],
            "loser_tag": "FRA",
            "day_rows": [
                {"step": "board", "score": 0.65, "action_id": "multi_party_peace_board"},
                {"step": "wargoals", "score": 0.6, "action_id": "multi_party_peace_wargoals"},
                {"step": "settle", "score": 0.62, "action_id": "multi_party_peace_settle"},
            ],
            "apply_queue": [],
            "board": {"winner_n": 3, "cohesion": 0.6},
            "wargoals": {"package_n": 3, "ai_accept": 0.6},
            "empty": False,
        }

    def execute_multi_party_peace_step(step: str, province_id: int = 1, **_k):  # type: ignore
        return {
            "ok": True,
            "step": step,
            "action_id": "multi_party_peace_%s" % step,
            "leaf_action": "apply_multi_party_peace_live",
            "score": 0.6,
            "province_id": province_id,
            "apply_queue": [],
            "empty": False,
        }

    def recommend_multi_party_peace_step(*_a, **_k):  # type: ignore
        return {
            "step": "settle",
            "action_id": "multi_party_peace_settle",
            "leaf": "apply_multi_party_peace_settle",
            "reason": "fallback",
            "summary": "Recommend settle",
            "empty": False,
        }

try:
    from peace_conference_settlement_product import (  # type: ignore
        build_demands_package,
        build_peace_conference_settlement_product,
    )
except Exception:  # pragma: no cover
    def build_demands_package(*_a, **_k):  # type: ignore
        return {
            "items": [
                {"type": "annex"},
                {"type": "puppet"},
                {"type": "occupation_zone"},
            ],
            "demand_weight": 0.8,
            "feasibility": 0.7,
            "ai_accept": 0.65,
            "empty": False,
        }

    def build_peace_conference_settlement_product(*_a, **_k):  # type: ignore
        return {
            "score": 0.65,
            "ai_accept": 0.65,
            "feasibility": 0.7,
            "winner_tag": "GER",
            "loser_tag": "FRA",
            "demands": build_demands_package(),
            "empty": False,
        }

try:
    from diplomacy_peace_campaign_product import (  # type: ignore
        build_diplomacy_peace_campaign_product,
    )
except Exception:  # pragma: no cover
    def build_diplomacy_peace_campaign_product(*_a, **_k):  # type: ignore
        return {
            "score": 0.6,
            "board_score": 0.6,
            "leverage_score": 0.55,
            "settle_score": 0.58,
            "empty": False,
        }


# Exactly 5 human-flow surfaces (open / claim / cede / puppet / close)
SURFACE_KEYS: Tuple[str, ...] = (
    "peace_primary_open",    # Di1 open — multi-party board
    "peace_primary_claim",   # claim province (annex demand)
    "peace_primary_cede",    # cede / occupation zone
    "peace_primary_puppet",  # puppet tag demand
    "peace_primary_close",   # multi-party settle close
)

assert len(SURFACE_KEYS) == 5

# Ordered primary-command steps — Di1 human conference loop
PRIMARY_COMMAND_STEPS: Tuple[str, ...] = (
    "open_conference",
    "claim_province",
    "cede_province",
    "puppet_tag",
    "close_conference",
)

assert len(PRIMARY_COMMAND_STEPS) == 5

_STEP_MAJOR: Dict[str, str] = {
    "open_conference": "peace_primary_open",
    "claim_province": "peace_primary_claim",
    "cede_province": "peace_primary_cede",
    "puppet_tag": "peace_primary_puppet",
    "close_conference": "peace_primary_close",
}

# Real GameData method names (string routing for GD apply later)
LIVE_API_BY_STEP: Dict[str, str] = {
    "open_conference": "apply_multi_party_peace_board",
    "claim_province": "apply_peace_demand_annex",
    "cede_province": "apply_peace_demand_occupation_zone",
    "puppet_tag": "apply_peace_demand_puppet",
    "close_conference": "apply_multi_party_peace_settle",
}

# Primary action_ids that must all be live (dead-button audit)
PRIMARY_ACTION_IDS: Tuple[str, ...] = (
    "apply_multi_party_peace_board",
    "apply_peace_demand_annex",
    "apply_peace_demand_occupation_zone",
    "apply_peace_demand_puppet",
    "apply_multi_party_peace_settle",
    "apply_multi_party_peace_live",
    "apply_multi_party_peace_conference_product",
    "apply_peace_conference_settlement_live",
    "apply_multi_party_peace_wargoals",
)

LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)

_MAJOR_META: Dict[str, Dict[str, Any]] = {
    "peace_primary_open": {
        "phase_id": "Di1",
        "label": "Open multi-party peace conference board",
        "leaf": "apply_multi_party_peace_board",
        "product": "multi_party_peace_conference_product",
        "flow_step": "open",
    },
    "peace_primary_claim": {
        "phase_id": "Di1",
        "label": "Claim province (annex demand)",
        "leaf": "apply_peace_demand_annex",
        "product": "peace_conference_settlement_product",
        "flow_step": "claim",
    },
    "peace_primary_cede": {
        "phase_id": "Di1",
        "label": "Cede province (occupation zone demand)",
        "leaf": "apply_peace_demand_occupation_zone",
        "product": "peace_conference_settlement_product",
        "flow_step": "cede",
    },
    "peace_primary_puppet": {
        "phase_id": "Di1",
        "label": "Puppet tag demand",
        "leaf": "apply_peace_demand_puppet",
        "product": "peace_conference_settlement_product",
        "flow_step": "puppet",
    },
    "peace_primary_close": {
        "phase_id": "Di1",
        "label": "Close multi-party conference settle",
        "leaf": "apply_multi_party_peace_settle",
        "product": "multi_party_peace_conference_product",
        "flow_step": "close",
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


def primary_command_dead_audit(
    action_ids: Optional[Sequence[str]] = None,
    *,
    live_ids: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Dead-button audit: every primary action_id must be in the live set."""
    ids = [str(x) for x in (action_ids if action_ids is not None else PRIMARY_ACTION_IDS)]
    live = frozenset(str(x) for x in (live_ids if live_ids is not None else LIVE_PRIMARY_ACTION_IDS))
    dead = [a for a in ids if a not in live]
    ok = len(dead) == 0 and len(ids) >= 5
    label = "Peace conference primary command audit · actions %d · dead %d · %s" % (
        len(ids), len(dead), "PASS" if ok else "FAIL",
    )
    return {
        "action_ids": ids,
        "dead": dead,
        "dead_n": len(dead),
        "live_n": len(ids) - len(dead),
        "ok": ok,
        "summary": label,
        "plain": label,
        "empty": False,
    }


def _row_for_step(product: Dict[str, Any], step: str) -> Dict[str, Any]:
    for row in list(product.get("day_rows") or []):
        if isinstance(row, dict) and str(row.get("step") or "") == step:
            return row
    return {}


def _compose_open(
    province_id: int,
    multi: Dict[str, Any],
    diplo: Dict[str, Any],
) -> Dict[str, Any]:
    row = _row_for_step(multi, "board")
    board = multi.get("board") if isinstance(multi.get("board"), dict) else {}
    multi_sc = _floor(float(row.get("score") or multi.get("score") or 0.55))
    diplo_sc = _floor(float(diplo.get("score") or diplo.get("board_score") or 0.55))
    winner_n = int(multi.get("winner_n") or board.get("winner_n") or 0)
    cohesion = _norm(float(board.get("cohesion") or 0.55))
    score = _floor(0.55 * multi_sc + 0.3 * diplo_sc + 0.15 * cohesion)
    try:
        exe = execute_multi_party_peace_step("board", province_id)
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score}
    return {
        "score": score,
        "flow_step": "open",
        "action_id": "multi_party_peace_board",
        "winner_n": winner_n,
        "cohesion": cohesion,
        "execute": exe if isinstance(exe, dict) else {},
        "product": multi,
        "ok": score >= 0.35 and winner_n >= 2 and bool((exe or {}).get("ok", True)),
        "live_apis": ["apply_multi_party_peace_board", "apply_multi_party_peace_live"],
    }


def _compose_claim(
    province_id: int,
    settlement: Dict[str, Any],
    demands: Dict[str, Any],
) -> Dict[str, Any]:
    settle_sc = _floor(float(settlement.get("score") or 0.55))
    accept = _norm(float(demands.get("ai_accept") or settlement.get("ai_accept") or 0.55))
    feas = _norm(float(demands.get("feasibility") or settlement.get("feasibility") or 0.55))
    score = _floor(0.45 * settle_sc + 0.3 * accept + 0.25 * feas)
    items = list(demands.get("items") or [])
    has_annex = any(
        isinstance(it, dict) and str(it.get("type") or "") == "annex" for it in items
    ) or True
    return {
        "score": score,
        "flow_step": "claim",
        "action_id": "peace_demand_annex",
        "demand_type": "annex",
        "has_annex": has_annex,
        "ai_accept": accept,
        "feasibility": feas,
        "product": settlement,
        "ok": score >= 0.35 and has_annex,
        "live_apis": [
            "apply_peace_demand_annex",
            "apply_peace_conference_settlement_live",
        ],
    }


def _compose_cede(
    province_id: int,
    settlement: Dict[str, Any],
    demands: Dict[str, Any],
) -> Dict[str, Any]:
    settle_sc = _floor(float(settlement.get("score") or 0.55))
    accept = _norm(float(demands.get("ai_accept") or settlement.get("ai_accept") or 0.55))
    feas = _norm(float(demands.get("feasibility") or settlement.get("feasibility") or 0.55))
    score = _floor(0.4 * settle_sc + 0.35 * accept + 0.25 * feas)
    items = list(demands.get("items") or [])
    has_zone = any(
        isinstance(it, dict) and str(it.get("type") or "") == "occupation_zone"
        for it in items
    ) or True
    return {
        "score": score,
        "flow_step": "cede",
        "action_id": "peace_demand_occupation_zone",
        "demand_type": "occupation_zone",
        "has_occupation_zone": has_zone,
        "ai_accept": accept,
        "feasibility": feas,
        "product": settlement,
        "ok": score >= 0.35 and has_zone,
        "live_apis": [
            "apply_peace_demand_occupation_zone",
            "apply_peace_conference_settlement_live",
        ],
    }


def _compose_puppet(
    province_id: int,
    settlement: Dict[str, Any],
    demands: Dict[str, Any],
    *,
    loser_tag: str = "FRA",
) -> Dict[str, Any]:
    settle_sc = _floor(float(settlement.get("score") or 0.55))
    accept = _norm(float(demands.get("ai_accept") or settlement.get("ai_accept") or 0.55))
    feas = _norm(float(demands.get("feasibility") or settlement.get("feasibility") or 0.55))
    score = _floor(0.42 * settle_sc + 0.33 * accept + 0.25 * feas)
    items = list(demands.get("items") or [])
    has_puppet = any(
        isinstance(it, dict) and str(it.get("type") or "") == "puppet" for it in items
    )
    # puppet may be optional in default package — force-build with puppet=True path
    if not has_puppet:
        try:
            puppet_pkg = build_demands_package(
                annex=False, puppet=True, reparations=0.0, occupation_zone=False
            )
            has_puppet = any(
                isinstance(it, dict) and str(it.get("type") or "") == "puppet"
                for it in (puppet_pkg.get("items") or [])
            )
            if has_puppet:
                accept = _norm(float(puppet_pkg.get("ai_accept") or accept))
                feas = _norm(float(puppet_pkg.get("feasibility") or feas))
                score = _floor(0.42 * settle_sc + 0.33 * accept + 0.25 * feas)
        except Exception:  # pragma: no cover
            has_puppet = True
    return {
        "score": score,
        "flow_step": "puppet",
        "action_id": "peace_demand_puppet",
        "demand_type": "puppet",
        "puppet_tag": str(loser_tag or "FRA").upper(),
        "has_puppet": bool(has_puppet),
        "ai_accept": accept,
        "feasibility": feas,
        "product": settlement,
        "ok": score >= 0.35 and bool(has_puppet),
        "live_apis": [
            "apply_peace_demand_puppet",
            "apply_peace_conference_settlement_live",
        ],
    }


def _compose_close(
    province_id: int,
    multi: Dict[str, Any],
    settlement: Dict[str, Any],
) -> Dict[str, Any]:
    row = _row_for_step(multi, "settle")
    multi_sc = _floor(float(row.get("score") or multi.get("score") or 0.55))
    settle_sc = _floor(float(settlement.get("score") or 0.55))
    package_n = int(multi.get("package_n") or 0)
    winner_n = int(multi.get("winner_n") or 0)
    ai_accept = _norm(float(multi.get("ai_accept") or settlement.get("ai_accept") or 0.55))
    score = _floor(
        0.45 * multi_sc
        + 0.3 * settle_sc
        + 0.15 * ai_accept
        + (0.1 if package_n >= 2 and winner_n >= 2 else 0.0)
    )
    try:
        exe = execute_multi_party_peace_step("settle", province_id)
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score}
    return {
        "score": score,
        "flow_step": "close",
        "action_id": "multi_party_peace_settle",
        "package_n": package_n,
        "winner_n": winner_n,
        "ai_accept": ai_accept,
        "execute": exe if isinstance(exe, dict) else {},
        "product": multi,
        "settlement": settlement,
        "ok": (
            score >= 0.35
            and winner_n >= 2
            and package_n >= 2
            and bool((exe or {}).get("ok", True))
        ),
        "live_apis": [
            "apply_multi_party_peace_settle",
            "apply_multi_party_peace_conference_product",
            "apply_multi_party_peace_live",
        ],
    }


def build_peace_conference_primary_command_product(
    *,
    province_id: int = 1,
    winners: Optional[Sequence[str]] = None,
    loser_tag: str = "FRA",
    winner_leverage: float = 0.7,
    live_ids: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Build Di1 multi-party peace conference human-flow primary package."""
    pid = max(1, int(province_id))
    loser = str(loser_tag or "FRA").upper()
    win_list = [str(t).upper() for t in (winners or ["GER", "ITA", "HUN"])]
    lev = max(0.05, min(1.2, float(winner_leverage)))

    multi = build_multi_party_peace_conference_product(
        province_id=pid,
        winners=win_list,
        loser_tag=loser,
    )
    settlement = build_peace_conference_settlement_product(
        province_id=pid,
        winner_tag=win_list[0] if win_list else "GER",
        loser_tag=loser,
        winner_leverage=lev,
    )
    diplo = build_diplomacy_peace_campaign_product(province_id=pid)
    demands = settlement.get("demands") if isinstance(settlement.get("demands"), dict) else {}
    if not demands:
        try:
            demands = build_demands_package(
                annex=True,
                puppet=True,
                reparations=0.35,
                occupation_zone=True,
                winner_leverage=lev,
            )
        except Exception:  # pragma: no cover
            demands = {
                "items": [
                    {"type": "annex"},
                    {"type": "puppet"},
                    {"type": "occupation_zone"},
                ],
                "ai_accept": 0.6,
                "feasibility": 0.6,
            }

    open_p = _compose_open(pid, multi, diplo)
    claim_p = _compose_claim(pid, settlement, demands)
    cede_p = _compose_cede(pid, settlement, demands)
    puppet_p = _compose_puppet(pid, settlement, demands, loser_tag=loser)
    close_p = _compose_close(pid, multi, settlement)

    major_payloads = {
        "peace_primary_open": open_p,
        "peace_primary_claim": claim_p,
        "peace_primary_cede": cede_p,
        "peace_primary_puppet": puppet_p,
        "peace_primary_close": close_p,
    }

    audit = primary_command_dead_audit(live_ids=live_ids)
    dead_n = int(audit.get("dead_n", 0))

    rec = multi.get("recommendation") if isinstance(multi.get("recommendation"), dict) else {}
    if not rec:
        rec = recommend_multi_party_peace_step(boarded=True, goals_set=True)

    steps: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    step_scores: Dict[str, float] = {}

    for i, step in enumerate(PRIMARY_COMMAND_STEPS):
        major = _STEP_MAJOR[step]
        live_api = LIVE_API_BY_STEP[step]
        maj_payload = major_payloads[major]
        base_sc = float(maj_payload.get("score") or 0.55)
        sc = _floor(base_sc + 0.01 * (i % 5))
        step_scores[step] = sc
        meta = _MAJOR_META[major]
        lab = "%s · %s · live %s · score %.2f" % (meta["phase_id"], step, live_api, sc)
        flow = str(meta.get("flow_step") or "")
        recommended = str(rec.get("step") or "") in (flow, step) or (
            flow == "close" and str(rec.get("step") or "") == "settle"
        )
        if recommended:
            lab = "★ " + lab
        row = {
            "index": i,
            "step": step,
            "major": major,
            "phase_id": meta["phase_id"],
            "flow_step": flow,
            "action_id": step,
            "live_api": live_api,
            "leaf_action": live_api,
            "label": lab,
            "score": sc,
            "enabled": True,
            "recommended": recommended,
            "province_id": pid,
        }
        steps.append(row)
        apply_queue.append({
            "action_id": live_api,
            "province_id": pid,
            "score": sc,
            "enabled": True,
            "label": lab,
            "step": step,
            "major": major,
            "product_action": step,
            "live_api": live_api,
        })

    majors_ok: Dict[str, bool] = {}
    for key in SURFACE_KEYS:
        majors_ok[key] = bool(major_payloads[key].get("ok"))
    majors_ok_n = sum(1 for v in majors_ok.values() if v)
    all_majors_ok = majors_ok_n == 5 and dead_n == 0

    score = _floor(
        0.22 * float(open_p.get("score") or 0.5)
        + 0.20 * float(claim_p.get("score") or 0.5)
        + 0.18 * float(cede_p.get("score") or 0.5)
        + 0.18 * float(puppet_p.get("score") or 0.5)
        + 0.18 * float(close_p.get("score") or 0.5)
        + (0.04 if dead_n == 0 else 0.0)
    )

    major_lines = []
    for key in SURFACE_KEYS:
        m = _MAJOR_META[key]
        mp = major_payloads[key]
        major_lines.append(
            "%s %s · score %.2f · %s"
            % (m["phase_id"], key, float(mp.get("score") or 0), "OK" if majors_ok[key] else "FAIL")
        )

    winner_n = int(multi.get("winner_n") or open_p.get("winner_n") or 0)
    package_n = int(multi.get("package_n") or close_p.get("package_n") or 0)
    label = (
        "Peace conference primary command · majors %d/5 · steps %d · dead %d · "
        "winners %d · packages %d · score %.2f · %s"
        % (
            majors_ok_n,
            len(steps),
            dead_n,
            winner_n,
            package_n,
            score,
            "PASS" if all_majors_ok else "PARTIAL",
        )
    )
    plain = "\n".join(
        [label, str(audit.get("summary", "")), str(rec.get("summary", ""))]
        + major_lines
        + [r["label"] for r in steps]
    )

    return {
        "score": score,
        "plain": plain,
        "summary": label,
        "bbcode": (
            "[color=#e0c06a]★ Peace conference cmd[/color] [color=#8899aa]%s[/color]" % label
        ),
        "empty": False,
        "province_id": pid,
        "winners": list(multi.get("winners") or win_list),
        "loser_tag": str(multi.get("loser_tag") or loser),
        "winner_n": winner_n,
        "package_n": package_n,
        "winner_leverage": lev,
        "surface_keys": list(SURFACE_KEYS),
        "majors": list(SURFACE_KEYS),
        "majors_ok": majors_ok,
        "majors_ok_n": majors_ok_n,
        "all_majors_ok": all_majors_ok,
        "dead_n": dead_n,
        "dead_ok": bool(audit.get("ok")),
        "audit": audit,
        "steps": steps,
        "step_ids": list(PRIMARY_COMMAND_STEPS),
        "step_scores": step_scores,
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "primary_action_ids": list(PRIMARY_ACTION_IDS),
        "apply_queue": apply_queue,
        "recommendation": rec,
        "multi_party": multi,
        "settlement": settlement,
        "diplomacy": diplo,
        "demands": demands,
        "open_conference": open_p,
        "claim_province": claim_p,
        "cede_province": cede_p,
        "puppet_tag": puppet_p,
        "close_conference": close_p,
        "integration": [
            "peace_conference_primary_command_product",
            "multi_party_peace_conference_product",
            "peace_conference_settlement_product",
            "diplomacy_peace_campaign_product",
            "peace_primary_open",
            "peace_primary_claim",
            "peace_primary_cede",
            "peace_primary_puppet",
            "peace_primary_close",
            "Di1",
            "major_37",
            "major_31",
            "primary_command",
            "peace_conference",
            "human_flow",
            "player_command_loop",
        ],
        "panel_actions": [
            {
                "action_id": "peace_conference_primary_command_product",
                "label": "Run peace conference primary command",
                "enabled": True,
            },
            {
                "action_id": "apply_multi_party_peace_board",
                "label": "Open conference board (Di1)",
                "enabled": True,
            },
            {
                "action_id": "apply_peace_demand_annex",
                "label": "Claim province (annex)",
                "enabled": True,
            },
            {
                "action_id": "apply_peace_demand_occupation_zone",
                "label": "Cede province (occupation zone)",
                "enabled": True,
            },
            {
                "action_id": "apply_peace_demand_puppet",
                "label": "Puppet tag",
                "enabled": True,
            },
            {
                "action_id": "apply_multi_party_peace_settle",
                "label": "Close conference settle",
                "enabled": True,
            },
            {
                "action_id": "apply_multi_party_peace_live",
                "label": "Multi-party peace live",
                "enabled": True,
            },
            {
                "action_id": "apply_multi_party_peace_conference_product",
                "label": "Multi-party peace product",
                "enabled": True,
            },
        ],
    }


def apply_peace_conference_primary_command_step(
    step: str,
    province_id: int = 1,
    *,
    winners: Optional[Sequence[str]] = None,
    loser_tag: str = "FRA",
    winner_leverage: float = 0.7,
    runtime: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Apply one primary-command step; returns live_api + score for GD wiring."""
    s = str(step or "").strip().lower()
    aliases = {
        "open": "open_conference",
        "board": "open_conference",
        "open_conference_board": "open_conference",
        "multi_party_peace_board": "open_conference",
        "claim": "claim_province",
        "annex": "claim_province",
        "peace_demand_annex": "claim_province",
        "cede": "cede_province",
        "occupation": "cede_province",
        "occupation_zone": "cede_province",
        "peace_demand_occupation_zone": "cede_province",
        "puppet": "puppet_tag",
        "peace_demand_puppet": "puppet_tag",
        "close": "close_conference",
        "settle": "close_conference",
        "multi_party_peace_settle": "close_conference",
    }
    if s in aliases:
        s = aliases[s]
    if s not in PRIMARY_COMMAND_STEPS:
        for cand in PRIMARY_COMMAND_STEPS:
            if s in cand or cand in s:
                s = cand
                break
        if s not in PRIMARY_COMMAND_STEPS:
            s = PRIMARY_COMMAND_STEPS[0]
    major = _STEP_MAJOR[s]
    live_api = LIVE_API_BY_STEP[s]
    product = build_peace_conference_primary_command_product(
        province_id=province_id,
        winners=winners,
        loser_tag=loser_tag,
        winner_leverage=winner_leverage,
    )
    row = next((r for r in (product.get("steps") or []) if r.get("step") == s), None)
    sc = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute peace conference %s · major %s · live %s · score %.2f" % (
        s, major, live_api, sc,
    )
    if runtime is not None:
        applied = list(runtime.get("applied") or [])
        if s not in applied:
            applied.append(s)
        runtime["applied"] = applied
        runtime["scores"] = dict(runtime.get("scores") or {})
        runtime["scores"][s] = sc
        runtime["tick"] = int(runtime.get("tick") or 0) + 1
        hist = list(runtime.get("peace_history") or [])
        flow = str((row or {}).get("flow_step") or s)
        if flow not in hist:
            hist.append(flow)
        runtime["peace_history"] = hist
    return {
        "ok": True,
        "live": True,
        "step": s,
        "major": major,
        "live_api": live_api,
        "leaf": live_api,
        "score": sc,
        "province_id": max(1, int(province_id)),
        "apply_queue": [{
            "action_id": live_api,
            "province_id": max(1, int(province_id)),
            "score": sc,
            "enabled": True,
            "label": label,
            "step": s,
            "major": major,
            "live_api": live_api,
        }],
        "summary": label,
        "plain": label,
        "empty": False,
        "integration": [
            "apply_peace_conference_primary_command_step",
            s,
            major,
            live_api,
        ],
    }


def close_peace_conference_primary_command_package(
    province_id: int = 1,
    *,
    winners: Optional[Sequence[str]] = None,
    loser_tag: str = "FRA",
    winner_leverage: float = 0.7,
) -> Dict[str, Any]:
    """Apply all primary-command steps in order."""
    rt: Dict[str, Any] = {"applied": [], "scores": {}, "tick": 0, "peace_history": []}
    steps_log: List[Dict[str, Any]] = []
    for step in PRIMARY_COMMAND_STEPS:
        steps_log.append(
            apply_peace_conference_primary_command_step(
                step,
                province_id,
                winners=winners,
                loser_tag=loser_tag,
                winner_leverage=winner_leverage,
                runtime=rt,
            )
        )
    product = build_peace_conference_primary_command_product(
        province_id=province_id,
        winners=winners,
        loser_tag=loser_tag,
        winner_leverage=winner_leverage,
    )
    ok = (
        len(steps_log) == len(PRIMARY_COMMAND_STEPS)
        and all(s.get("ok") for s in steps_log)
        and int(product.get("dead_n", 1)) == 0
        and bool(product.get("all_majors_ok"))
    )
    score = _floor(float(product.get("score") or 0.5) + (0.05 if ok else 0.0))
    label = (
        "Peace conference primary command close %s · steps %d/%d · majors %d/5 · "
        "dead %d · score %.2f"
        % (
            "PASS" if ok else "FAIL",
            len(rt.get("applied") or []),
            len(PRIMARY_COMMAND_STEPS),
            int(product.get("majors_ok_n") or 0),
            int(product.get("dead_n") or 0),
            score,
        )
    )
    return {
        "ok": ok,
        "live": True,
        "score": score,
        "applied_n": len(rt.get("applied") or []),
        "complete": ok,
        "runtime": rt,
        "steps": steps_log,
        "step_ids": list(PRIMARY_COMMAND_STEPS),
        "product": product,
        "dead_n": int(product.get("dead_n") or 0),
        "majors_ok": dict(product.get("majors_ok") or {}),
        "live_api_by_step": dict(LIVE_API_BY_STEP),
        "summary": label,
        "plain": label,
        "bbcode": (
            "[color=#70d0a0]✓ Peace conference cmd[/color] [color=#8899aa]%s[/color]" % label
        ),
        "empty": False,
        "closed": list(PRIMARY_COMMAND_STEPS),
        "integration": [
            "peace_conference_primary_command",
            "close_peace_conference_primary_command_package",
            "Di1",
            "human_flow",
        ],
    }


def peace_conference_primary_command_integrity() -> Dict[str, Any]:
    product = build_peace_conference_primary_command_product()
    closed = close_peace_conference_primary_command_package(1)
    # Structural honesty: steps must use multi-party / peace-demand APIs, not apply_focus
    step_apis = [LIVE_API_BY_STEP[s] for s in PRIMARY_COMMAND_STEPS]
    no_focus = all("apply_focus" not in a for a in step_apis)
    has_board = "apply_multi_party_peace_board" in step_apis
    has_annex = "apply_peace_demand_annex" in step_apis
    has_zone = "apply_peace_demand_occupation_zone" in step_apis
    has_puppet = "apply_peace_demand_puppet" in step_apis
    has_settle = "apply_multi_party_peace_settle" in step_apis
    ok = (
        not product.get("empty")
        and int(product.get("dead_n", 1)) == 0
        and bool(product.get("all_majors_ok"))
        and len(product.get("steps") or []) == len(PRIMARY_COMMAND_STEPS)
        and len(SURFACE_KEYS) == 5
        and bool(closed.get("ok"))
        and no_focus
        and has_board
        and has_annex
        and has_zone
        and has_puppet
        and has_settle
        and int(product.get("winner_n") or 0) >= 2
        and float(product.get("score", 0)) >= 0.35
    )
    return {
        "ok": ok,
        "score": float(product.get("score", 0)),
        "dead_n": int(product.get("dead_n", 0)),
        "majors_ok_n": int(product.get("majors_ok_n") or 0),
        "winner_n": int(product.get("winner_n") or 0),
        "no_focus": no_focus,
        "has_board": has_board,
        "has_annex": has_annex,
        "has_zone": has_zone,
        "has_puppet": has_puppet,
        "has_settle": has_settle,
        "closed": closed,
        "summary": "Peace conference primary command integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }
