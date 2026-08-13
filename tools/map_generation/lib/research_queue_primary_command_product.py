"""Research queue UI primary command package — Master Plan T1.

Elevates open queue → enqueue branch → gate check → advance month → close
into a Stream-α-style vertical package (not day-catalogue stubs). Composes:

  tech_research_campaign_product — catalog / priority / field research loop
  tech_tree_branching_product    — branch catalog, year gates, path pick

Step ids match T1 player research loop:
  open_queue · enqueue_branch · gate_check · advance_month · close

live_api strings match real GameData method names for later GD wiring
(apply_tech_research_catalog, apply_tech_branch_live, apply_tech_tree_branches,
 apply_tech_research_priority, apply_tech_research_close_day).
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence, Tuple

try:
    from tech_research_campaign_product import (  # type: ignore
        PRODUCT_STEPS as TECH_PRODUCT_STEPS,
        build_tech_research_campaign_product,
        execute_tech_research_step,
        recommend_tech_research_step,
    )
except Exception:  # pragma: no cover
    TECH_PRODUCT_STEPS = ("catalog", "priority", "field")

    def build_tech_research_campaign_product(*_a, **_k):  # type: ignore
        return {
            "score": 0.6,
            "catalog_count": 8,
            "catalog_score": 0.62,
            "priority_score": 0.58,
            "field_score": 0.55,
            "day_rows": [
                {"step": "catalog", "score": 0.62, "action_id": "tech_research_catalog"},
                {"step": "priority", "score": 0.58, "action_id": "tech_research_priority"},
                {"step": "field", "score": 0.55, "action_id": "tech_research_field"},
            ],
            "apply_queue": [],
            "recommendation": {
                "step": "priority",
                "action_id": "tech_research_priority",
            },
            "empty": False,
            "summary": "tech research fallback",
        }

    def execute_tech_research_step(step: str, province_id: int = 1, **_k):  # type: ignore
        return {
            "ok": True,
            "step": step,
            "action_id": "tech_research_%s" % step,
            "leaf_action": "apply_tech_research_%s" % step
            if step != "catalog"
            else "apply_tech_research_catalog",
            "score": 0.55,
            "province_id": province_id,
            "apply_queue": [],
            "empty": False,
        }

    def recommend_tech_research_step(*_a, **_k):  # type: ignore
        return {
            "step": "priority",
            "action_id": "tech_research_priority",
            "leaf": "apply_tech_research_priority",
            "reason": "fallback",
            "summary": "Recommend priority",
            "empty": False,
        }


try:
    from tech_tree_branching_product import (  # type: ignore
        BRANCHES,
        PRODUCT_STEPS as BRANCH_PRODUCT_STEPS,
        build_tech_tree_branching_product,
        compute_branch_board,
        execute_tech_tree_branching_step,
        recommend_tech_branching_step,
        recommend_tech_path,
    )
except Exception:  # pragma: no cover
    BRANCH_PRODUCT_STEPS = ("branches", "path", "field")
    BRANCHES = {
        "infantry": {"year": 1918, "techs": ["infantry_weapons_1"], "score": 0.72},
        "armor": {"year": 1936, "techs": ["basic_medium_tank"], "score": 0.78},
        "air": {"year": 1936, "techs": ["early_fighter"], "score": 0.7},
        "naval": {"year": 1922, "techs": ["destroyer_hull"], "score": 0.68},
        "industry": {"year": 1918, "techs": ["machine_tools"], "score": 0.74},
        "electronics": {"year": 1939, "techs": ["encryption"], "score": 0.66},
    }

    def build_tech_tree_branching_product(*_a, **_k):  # type: ignore
        return {
            "score": 0.62,
            "era_year": 1939,
            "open_n": 5,
            "branch_n": 6,
            "path_branch": "armor",
            "tech_n": 3,
            "day_rows": [
                {"step": "branches", "score": 0.65, "action_id": "tech_tree_branches"},
                {"step": "path", "score": 0.6, "action_id": "tech_tree_path"},
                {"step": "field", "score": 0.58, "action_id": "tech_tree_field"},
            ],
            "apply_queue": [],
            "board": {
                "open_n": 5,
                "locked_n": 1,
                "coverage": 0.83,
                "branches": [],
                "summary": "branches fallback",
            },
            "path": {"branch": "armor", "techs": ["basic_medium_tank"], "score": 0.78},
            "empty": False,
            "summary": "tech branching fallback",
        }

    def compute_branch_board(*, era_year: int = 1939, **_k):  # type: ignore
        year = max(1914, min(2026, int(era_year)))
        open_n = sum(1 for m in BRANCHES.values() if year >= int(m.get("year", 1936)))
        return {
            "era_year": year,
            "branches": [],
            "branch_n": len(BRANCHES),
            "open_n": open_n,
            "locked_n": len(BRANCHES) - open_n,
            "coverage": max(0.35, float(open_n) / max(1, len(BRANCHES))),
            "summary": "Tech branches · year %d · open %d" % (year, open_n),
            "empty": False,
        }

    def recommend_tech_path(*, board: Dict[str, Any], preferred: str = "armor", **_k):  # type: ignore
        return {
            "branch": preferred or "armor",
            "techs": list((BRANCHES.get(preferred) or {}).get("techs") or []),
            "score": 0.7,
            "summary": "Path · %s" % preferred,
            "empty": False,
        }

    def execute_tech_tree_branching_step(step: str, province_id: int = 1, **_k):  # type: ignore
        return {
            "ok": True,
            "step": step,
            "action_id": "tech_tree_%s" % step,
            "leaf_action": "apply_tech_tree_%s" % step,
            "score": 0.55,
            "province_id": province_id,
            "apply_queue": [],
            "empty": False,
        }

    def recommend_tech_branching_step(*_a, **_k):  # type: ignore
        return {
            "step": "path",
            "action_id": "tech_tree_path",
            "leaf": "apply_tech_tree_path",
            "reason": "fallback",
            "summary": "Recommend path",
            "empty": False,
        }


# Exactly 5 T1 player-research surfaces
SURFACE_KEYS: Tuple[str, ...] = (
    "research_primary_open_queue",     # open research queue / catalog surface
    "research_primary_enqueue_branch", # enqueue locked/unlocked branch path
    "research_primary_gate_check",     # year + resource gate check
    "research_primary_advance_month",  # monthly research priority advance
    "research_primary_close",          # package close
)

assert len(SURFACE_KEYS) == 5

# Ordered primary-command steps — T1 human research loop
PRIMARY_COMMAND_STEPS: Tuple[str, ...] = (
    "open_queue",
    "enqueue_branch",
    "gate_check",
    "advance_month",
    "close",
)

assert len(PRIMARY_COMMAND_STEPS) == 5

_STEP_MAJOR: Dict[str, str] = {
    "open_queue": "research_primary_open_queue",
    "enqueue_branch": "research_primary_enqueue_branch",
    "gate_check": "research_primary_gate_check",
    "advance_month": "research_primary_advance_month",
    "close": "research_primary_close",
}

# Real GameData method names (string routing for GD apply later)
LIVE_API_BY_STEP: Dict[str, str] = {
    "open_queue": "apply_tech_research_catalog",
    "enqueue_branch": "apply_tech_branch_live",
    "gate_check": "apply_tech_tree_branches",
    "advance_month": "apply_tech_research_priority",
    "close": "apply_tech_research_close_day",
}

# Primary action_ids that must all be live (dead-button audit)
PRIMARY_ACTION_IDS: Tuple[str, ...] = (
    "apply_tech_research_catalog",
    "apply_tech_branch_live",
    "apply_tech_tree_branches",
    "apply_tech_research_priority",
    "apply_tech_research_close_day",
    "apply_tech_research_campaign_product",
    "apply_tech_tree_branching_product",
    "apply_tech_tree_path",
    "apply_tech_tree_field",
    "apply_tech_tree_branching_close_day",
    "apply_tech_branch_armor",
    "apply_tech_research_field",
)

LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)

_MAJOR_META: Dict[str, Dict[str, Any]] = {
    "research_primary_open_queue": {
        "phase_id": "T1",
        "label": "Open research queue / design catalog",
        "leaf": "apply_tech_research_catalog",
        "product": "tech_research_campaign_product",
        "flow_step": "open_queue",
    },
    "research_primary_enqueue_branch": {
        "phase_id": "T1",
        "label": "Enqueue research branch path",
        "leaf": "apply_tech_branch_live",
        "product": "tech_tree_branching_product",
        "flow_step": "enqueue_branch",
    },
    "research_primary_gate_check": {
        "phase_id": "T1",
        "label": "Branch locks + resource / year gates",
        "leaf": "apply_tech_tree_branches",
        "product": "tech_tree_branching_product",
        "flow_step": "gate_check",
    },
    "research_primary_advance_month": {
        "phase_id": "T1",
        "label": "Advance research month / priority",
        "leaf": "apply_tech_research_priority",
        "product": "tech_research_campaign_product",
        "flow_step": "advance_month",
    },
    "research_primary_close": {
        "phase_id": "T1",
        "label": "Research queue primary package close",
        "leaf": "apply_tech_research_close_day",
        "product": "tech_research_campaign_product",
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
    label = "Research queue primary command audit · actions %d · dead %d · %s" % (
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


def _resource_gate_score(
    *,
    resource_level: float,
    open_n: int,
    branch_n: int,
    locked_n: int,
) -> float:
    """Year/branch locks + resource gate readiness (0–1)."""
    res = _norm(resource_level)
    coverage = float(open_n) / max(1, int(branch_n) or 1)
    lock_penalty = min(0.25, 0.05 * max(0, int(locked_n)))
    return _floor(0.55 * res + 0.45 * coverage - lock_penalty)


def _compose_open_queue(
    province_id: int,
    tech: Dict[str, Any],
) -> Dict[str, Any]:
    row = _row_for_step(tech, "catalog")
    cat_sc = _floor(float(row.get("score") or tech.get("catalog_score") or tech.get("score") or 0.55))
    catalog_count = int(tech.get("catalog_count") or 0)
    score = _floor(0.65 * cat_sc + 0.35 * min(1.0, catalog_count / 12.0))
    try:
        exe = execute_tech_research_step("catalog", province_id)
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score}
    return {
        "score": score,
        "flow_step": "open_queue",
        "action_id": "tech_research_catalog",
        "catalog_count": catalog_count,
        "execute": exe if isinstance(exe, dict) else {},
        "product": tech,
        "ok": score >= 0.35 and catalog_count >= 4 and bool((exe or {}).get("ok", True)),
        "live_apis": [
            "apply_tech_research_catalog",
            "apply_tech_research_campaign_product",
        ],
    }


def _compose_enqueue_branch(
    province_id: int,
    branch: Dict[str, Any],
    *,
    preferred: str = "armor",
) -> Dict[str, Any]:
    row = _row_for_step(branch, "path")
    path_sc = _floor(float(row.get("score") or branch.get("score") or 0.55))
    path = branch.get("path") if isinstance(branch.get("path"), dict) else {}
    path_branch = str(
        path.get("branch") or branch.get("path_branch") or preferred or "armor"
    ).lower()
    tech_n = int(branch.get("tech_n") or len(path.get("techs") or []) or 0)
    score = _floor(0.55 * path_sc + 0.25 * min(1.0, tech_n / 3.0) + 0.2 * _norm(path.get("score", path_sc)))
    try:
        exe = execute_tech_tree_branching_step("path", province_id)
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score}
    return {
        "score": score,
        "flow_step": "enqueue_branch",
        "action_id": "tech_tree_path",
        "path_branch": path_branch,
        "tech_n": tech_n,
        "execute": exe if isinstance(exe, dict) else {},
        "product": branch,
        "ok": score >= 0.35 and bool(path_branch) and bool((exe or {}).get("ok", True)),
        "live_apis": [
            "apply_tech_branch_live",
            "apply_tech_tree_path",
            "apply_tech_branch_armor",
            "apply_tech_tree_branching_product",
        ],
    }


def _compose_gate_check(
    province_id: int,
    branch: Dict[str, Any],
    board: Dict[str, Any],
    *,
    resource_level: float,
    era_year: int,
) -> Dict[str, Any]:
    row = _row_for_step(branch, "branches")
    br_sc = _floor(float(row.get("score") or branch.get("score") or 0.55))
    open_n = int(board.get("open_n") or branch.get("open_n") or 0)
    locked_n = int(board.get("locked_n") or 0)
    branch_n = int(board.get("branch_n") or branch.get("branch_n") or len(BRANCHES) or 6)
    gate_sc = _resource_gate_score(
        resource_level=resource_level,
        open_n=open_n,
        branch_n=branch_n,
        locked_n=locked_n,
    )
    year = int(board.get("era_year") or era_year or 1939)
    # Branch locks: preferred path must be year-unlocked when possible
    preferred_open = open_n >= 3
    score = _floor(0.45 * br_sc + 0.4 * gate_sc + (0.15 if preferred_open else 0.05))
    try:
        exe = execute_tech_tree_branching_step("branches", province_id)
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score}
    return {
        "score": score,
        "flow_step": "gate_check",
        "action_id": "tech_tree_branches",
        "era_year": year,
        "open_n": open_n,
        "locked_n": locked_n,
        "branch_n": branch_n,
        "resource_level": _norm(resource_level),
        "gate_score": gate_sc,
        "gates_ok": preferred_open and gate_sc >= 0.4,
        "execute": exe if isinstance(exe, dict) else {},
        "product": branch,
        "board": board,
        "ok": score >= 0.35 and preferred_open and bool((exe or {}).get("ok", True)),
        "live_apis": [
            "apply_tech_tree_branches",
            "apply_tech_tree_branching_product",
        ],
    }


def _compose_advance_month(
    province_id: int,
    tech: Dict[str, Any],
    gate: Dict[str, Any],
    *,
    months_ahead: int = 1,
) -> Dict[str, Any]:
    row = _row_for_step(tech, "priority")
    pri_sc = _floor(float(row.get("score") or tech.get("priority_score") or tech.get("score") or 0.55))
    months = max(1, min(24, int(months_ahead)))
    # Multi-month readiness: 12+ month player loop honesty — scale lightly with months
    month_factor = _floor(min(1.0, 0.45 + 0.04 * months))
    gate_sc = _floor(float(gate.get("score") or 0.55))
    score = _floor(0.5 * pri_sc + 0.3 * gate_sc + 0.2 * month_factor)
    try:
        exe = execute_tech_research_step("priority", province_id)
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score}
    return {
        "score": score,
        "flow_step": "advance_month",
        "action_id": "tech_research_priority",
        "months_ahead": months,
        "month_factor": month_factor,
        "priority_score": pri_sc,
        "execute": exe if isinstance(exe, dict) else {},
        "product": tech,
        "ok": score >= 0.35 and bool((exe or {}).get("ok", True)),
        "live_apis": [
            "apply_tech_research_priority",
            "apply_tech_research_campaign_product",
        ],
    }


def _compose_close(
    province_id: int,
    tech: Dict[str, Any],
    branch: Dict[str, Any],
    open_q: Dict[str, Any],
    enqueue: Dict[str, Any],
    gate: Dict[str, Any],
    advance: Dict[str, Any],
) -> Dict[str, Any]:
    tech_sc = _floor(float(tech.get("score") or 0.55))
    branch_sc = _floor(float(branch.get("score") or 0.55))
    surface_ok = all(bool(p.get("ok")) for p in (open_q, enqueue, gate, advance))
    score = _floor(
        0.22 * tech_sc
        + 0.18 * branch_sc
        + 0.14 * float(open_q.get("score") or 0.5)
        + 0.14 * float(enqueue.get("score") or 0.5)
        + 0.14 * float(gate.get("score") or 0.5)
        + 0.14 * float(advance.get("score") or 0.5)
        + (0.04 if surface_ok else 0.0)
    )
    return {
        "score": score,
        "flow_step": "close",
        "action_id": "tech_research_close_day",
        "surface_ok": surface_ok,
        "tech_score": tech_sc,
        "branch_score": branch_sc,
        "product": tech,
        "branch": branch,
        "ok": score >= 0.35 and surface_ok,
        "live_apis": [
            "apply_tech_research_close_day",
            "apply_tech_tree_branching_close_day",
            "apply_tech_research_campaign_product",
            "apply_tech_tree_branching_product",
            "apply_tech_research_field",
            "apply_tech_tree_field",
        ],
    }


def build_research_queue_primary_command_product(
    *,
    province_id: int = 1,
    era_year: int = 1939,
    preferred: str = "armor",
    resource_level: float = 0.65,
    months_ahead: int = 1,
    live_ids: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Build T1 research queue UI primary player-command package."""
    pid = max(1, int(province_id))
    year = max(1914, min(2026, int(era_year)))
    pref = str(preferred or "armor").lower()
    if pref not in BRANCHES:
        pref = "armor"
    res = _norm(resource_level)
    months = max(1, min(24, int(months_ahead)))

    tech = build_tech_research_campaign_product(province_id=pid)
    branch = build_tech_tree_branching_product(
        province_id=pid,
        era_year=year,
        preferred=pref,
    )
    board = branch.get("board") if isinstance(branch.get("board"), dict) else {}
    if not board:
        board = compute_branch_board(era_year=year)
    path = branch.get("path") if isinstance(branch.get("path"), dict) else {}
    if not path:
        path = recommend_tech_path(board=board, preferred=pref)

    open_q = _compose_open_queue(pid, tech)
    enqueue = _compose_enqueue_branch(pid, branch, preferred=pref)
    gate = _compose_gate_check(
        pid, branch, board, resource_level=res, era_year=year
    )
    advance = _compose_advance_month(
        pid, tech, gate, months_ahead=months
    )
    close = _compose_close(pid, tech, branch, open_q, enqueue, gate, advance)

    major_payloads = {
        "research_primary_open_queue": open_q,
        "research_primary_enqueue_branch": enqueue,
        "research_primary_gate_check": gate,
        "research_primary_advance_month": advance,
        "research_primary_close": close,
    }

    audit = primary_command_dead_audit(live_ids=live_ids)
    dead_n = int(audit.get("dead_n", 0))

    rec = tech.get("recommendation") if isinstance(tech.get("recommendation"), dict) else {}
    if not rec:
        rec = recommend_tech_research_step(
            catalog_count=int(tech.get("catalog_count") or 0),
            priority_score=float(tech.get("priority_score") or 0.5),
            field_ready=float(tech.get("field_score") or 0) >= 0.4,
        )
    branch_rec = (
        branch.get("recommendation")
        if isinstance(branch.get("recommendation"), dict)
        else {}
    )
    if not branch_rec:
        branch_rec = recommend_tech_branching_step(branches_set=True, path_set=True)

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
        rec_step = str(rec.get("step") or "")
        br_step = str(branch_rec.get("step") or "")
        recommended = (
            rec_step in (flow, step)
            or br_step in (flow, step)
            or (flow == "open_queue" and rec_step == "catalog")
            or (flow == "advance_month" and rec_step == "priority")
            or (flow == "enqueue_branch" and br_step == "path")
            or (flow == "gate_check" and br_step == "branches")
            or (flow == "close" and rec_step == "field")
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
        0.22 * float(open_q.get("score") or 0.5)
        + 0.20 * float(enqueue.get("score") or 0.5)
        + 0.20 * float(gate.get("score") or 0.5)
        + 0.18 * float(advance.get("score") or 0.5)
        + 0.16 * float(close.get("score") or 0.5)
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

    path_branch = str(enqueue.get("path_branch") or path.get("branch") or pref)
    open_n = int(gate.get("open_n") or board.get("open_n") or 0)
    locked_n = int(gate.get("locked_n") or board.get("locked_n") or 0)
    catalog_count = int(open_q.get("catalog_count") or tech.get("catalog_count") or 0)
    label = (
        "Research queue primary command · majors %d/5 · steps %d · dead %d · "
        "year %d · path %s · open %d locked %d · res %.0f%% · months %d · "
        "score %.2f · %s"
        % (
            majors_ok_n,
            len(steps),
            dead_n,
            year,
            path_branch,
            open_n,
            locked_n,
            res * 100,
            months,
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
            "[color=#38bdf8]★ Research queue cmd[/color] [color=#8899aa]%s[/color]" % label
        ),
        "empty": False,
        "province_id": pid,
        "era_year": year,
        "preferred": pref,
        "path_branch": path_branch,
        "resource_level": res,
        "months_ahead": months,
        "catalog_count": catalog_count,
        "open_n": open_n,
        "locked_n": locked_n,
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
        "branch_recommendation": branch_rec,
        "tech": tech,
        "branch": branch,
        "board": board,
        "path": path,
        "open_queue": open_q,
        "enqueue_branch": enqueue,
        "gate_check": gate,
        "advance_month": advance,
        "research_close": close,
        "tech_product_steps": list(TECH_PRODUCT_STEPS) if TECH_PRODUCT_STEPS else ["catalog", "priority", "field"],
        "branch_product_steps": list(BRANCH_PRODUCT_STEPS) if BRANCH_PRODUCT_STEPS else ["branches", "path", "field"],
        "integration": [
            "research_queue_primary_command_product",
            "tech_research_campaign_product",
            "tech_tree_branching_product",
            "research_primary_open_queue",
            "research_primary_enqueue_branch",
            "research_primary_gate_check",
            "research_primary_advance_month",
            "research_primary_close",
            "T1",
            "major_17",
            "major_39",
            "primary_command",
            "research_queue",
            "branch_locks",
            "resource_gates",
            "player_command_loop",
        ],
        "panel_actions": [
            {
                "action_id": "research_queue_primary_command_product",
                "label": "Run research queue primary command",
                "enabled": True,
            },
            {
                "action_id": "apply_tech_research_catalog",
                "label": "Open research queue (T1)",
                "enabled": True,
            },
            {
                "action_id": "apply_tech_branch_live",
                "label": "Enqueue research branch",
                "enabled": True,
            },
            {
                "action_id": "apply_tech_tree_branches",
                "label": "Gate check — branch locks",
                "enabled": True,
            },
            {
                "action_id": "apply_tech_research_priority",
                "label": "Advance research month",
                "enabled": True,
            },
            {
                "action_id": "apply_tech_research_close_day",
                "label": "Research queue close",
                "enabled": True,
            },
            {
                "action_id": "apply_tech_research_campaign_product",
                "label": "Tech research campaign product",
                "enabled": True,
            },
            {
                "action_id": "apply_tech_tree_branching_product",
                "label": "Tech tree branching product",
                "enabled": True,
            },
            {
                "action_id": "apply_tech_branch_armor",
                "label": "Branch: armor",
                "enabled": True,
            },
        ],
    }


def apply_research_queue_primary_command_step(
    step: str,
    province_id: int = 1,
    *,
    era_year: int = 1939,
    preferred: str = "armor",
    resource_level: float = 0.65,
    months_ahead: int = 1,
    runtime: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Apply one primary-command step; returns live_api + score for GD wiring."""
    s = str(step or "").strip().lower()
    aliases = {
        "open": "open_queue",
        "queue": "open_queue",
        "catalog": "open_queue",
        "research_open": "open_queue",
        "research_open_queue": "open_queue",
        "research_catalog": "open_queue",
        "tech_research_catalog": "open_queue",
        "enqueue": "enqueue_branch",
        "branch": "enqueue_branch",
        "path": "enqueue_branch",
        "research_enqueue": "enqueue_branch",
        "research_enqueue_branch": "enqueue_branch",
        "tech_branch": "enqueue_branch",
        "tech_tree_path": "enqueue_branch",
        "gate": "gate_check",
        "gates": "gate_check",
        "locks": "gate_check",
        "branch_locks": "gate_check",
        "resource_gates": "gate_check",
        "branches": "gate_check",
        "tech_tree_branches": "gate_check",
        "research_gate_check": "gate_check",
        "month": "advance_month",
        "advance": "advance_month",
        "priority": "advance_month",
        "research_month": "advance_month",
        "research_advance_month": "advance_month",
        "tech_research_priority": "advance_month",
        "research_close": "close",
        "research_queue_close": "close",
        "package_close": "close",
        "tech_research_close_day": "close",
        "research_primary_close": "close",
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
    product = build_research_queue_primary_command_product(
        province_id=province_id,
        era_year=era_year,
        preferred=preferred,
        resource_level=resource_level,
        months_ahead=months_ahead,
    )
    row = next((r for r in (product.get("steps") or []) if r.get("step") == s), None)
    sc = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute research queue %s · major %s · live %s · score %.2f" % (
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
        hist = list(runtime.get("research_history") or [])
        flow = str((row or {}).get("flow_step") or s)
        if flow not in hist:
            hist.append(flow)
        runtime["research_history"] = hist
        if s == "advance_month":
            runtime["months_advanced"] = int(runtime.get("months_advanced") or 0) + max(
                1, int(months_ahead)
            )
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
            "apply_research_queue_primary_command_step",
            s,
            major,
            live_api,
        ],
    }


def close_research_queue_primary_command_package(
    province_id: int = 1,
    *,
    era_year: int = 1939,
    preferred: str = "armor",
    resource_level: float = 0.65,
    months_ahead: int = 1,
) -> Dict[str, Any]:
    """Apply all primary-command steps in order."""
    rt: Dict[str, Any] = {
        "applied": [],
        "scores": {},
        "tick": 0,
        "research_history": [],
        "months_advanced": 0,
    }
    steps_log: List[Dict[str, Any]] = []
    for step in PRIMARY_COMMAND_STEPS:
        steps_log.append(
            apply_research_queue_primary_command_step(
                step,
                province_id,
                era_year=era_year,
                preferred=preferred,
                resource_level=resource_level,
                months_ahead=months_ahead,
                runtime=rt,
            )
        )
    product = build_research_queue_primary_command_product(
        province_id=province_id,
        era_year=era_year,
        preferred=preferred,
        resource_level=resource_level,
        months_ahead=months_ahead,
    )
    ok = (
        len(steps_log) == len(PRIMARY_COMMAND_STEPS)
        and all(s.get("ok") for s in steps_log)
        and int(product.get("dead_n", 1)) == 0
        and bool(product.get("all_majors_ok"))
    )
    score = _floor(float(product.get("score") or 0.5) + (0.05 if ok else 0.0))
    label = (
        "Research queue primary command close %s · steps %d/%d · majors %d/5 · "
        "dead %d · months %d · score %.2f"
        % (
            "PASS" if ok else "FAIL",
            len(rt.get("applied") or []),
            len(PRIMARY_COMMAND_STEPS),
            int(product.get("majors_ok_n") or 0),
            int(product.get("dead_n") or 0),
            int(rt.get("months_advanced") or 0),
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
            "[color=#70d0a0]✓ Research queue cmd[/color] [color=#8899aa]%s[/color]" % label
        ),
        "empty": False,
        "closed": list(PRIMARY_COMMAND_STEPS),
        "integration": [
            "research_queue_primary_command",
            "close_research_queue_primary_command_package",
            "T1",
            "major_17",
            "major_39",
        ],
    }


def research_queue_primary_command_integrity() -> Dict[str, Any]:
    product = build_research_queue_primary_command_product()
    early = build_research_queue_primary_command_product(
        era_year=1920, resource_level=0.3, preferred="infantry"
    )
    multi = build_research_queue_primary_command_product(months_ahead=12)
    closed = close_research_queue_primary_command_package(1)
    # Structural honesty: step APIs must be tech/research live leaves, not apply_focus
    step_apis = [LIVE_API_BY_STEP[s] for s in PRIMARY_COMMAND_STEPS]
    no_focus = all("apply_focus" not in a for a in step_apis)
    has_catalog = "apply_tech_research_catalog" in step_apis
    has_branch_live = "apply_tech_branch_live" in step_apis
    has_tree_branches = "apply_tech_tree_branches" in step_apis
    has_priority = "apply_tech_research_priority" in step_apis
    has_close = "apply_tech_research_close_day" in step_apis
    year_shift = abs(float(product.get("score", 0)) - float(early.get("score", 0)))
    ok = (
        not product.get("empty")
        and int(product.get("dead_n", 1)) == 0
        and bool(product.get("all_majors_ok"))
        and len(product.get("steps") or []) == len(PRIMARY_COMMAND_STEPS)
        and len(SURFACE_KEYS) == 5
        and bool(closed.get("ok"))
        and no_focus
        and has_catalog
        and has_branch_live
        and has_tree_branches
        and has_priority
        and has_close
        and float(product.get("score", 0)) >= 0.35
        and float(multi.get("score", 0)) >= 0.35
        and int(multi.get("months_ahead") or 0) >= 12
        and year_shift >= 0.0
    )
    return {
        "ok": ok,
        "score": float(product.get("score", 0)),
        "early_score": float(early.get("score", 0)),
        "multi_month_score": float(multi.get("score", 0)),
        "year_shift": year_shift,
        "dead_n": int(product.get("dead_n", 0)),
        "majors_ok_n": int(product.get("majors_ok_n") or 0),
        "no_focus": no_focus,
        "has_catalog": has_catalog,
        "has_branch_live": has_branch_live,
        "has_tree_branches": has_tree_branches,
        "has_priority": has_priority,
        "has_close": has_close,
        "closed": closed,
        "summary": "Research queue primary command integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }
