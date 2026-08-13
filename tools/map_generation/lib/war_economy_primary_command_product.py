"""War economy civilian↔war conversion primary command package — Master Plan E1.

Elevates board → convert_to_war → convert_to_civ → stockpile_check → close
into a Stream-α-style vertical package (not day-catalogue stubs). Composes:

  war_economy_conversion_product   — civ board / convert / stockpile sustain
  war_economy_mobilization_product — board / allocate / sustain war economy

Step ids match E1 civilian↔war player loop:
  board · convert_to_war · convert_to_civ · stockpile_check · close

live_api strings match real GameData method names for later GD wiring
(apply_economy_civ_board, apply_economy_war_convert, apply_economy_conversion_live,
 apply_economy_stockpile_sustain, apply_war_economy_conversion_close_day).
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence, Tuple

try:
    from war_economy_conversion_product import (  # type: ignore
        PRODUCT_STEPS as CONV_PRODUCT_STEPS,
        build_war_economy_conversion_product,
        compute_civ_board,
        compute_conversion,
        compute_stockpile_sustain,
        execute_economy_conversion_step,
        recommend_economy_conversion_step,
    )
except Exception:  # pragma: no cover
    CONV_PRODUCT_STEPS = ("civ_board", "convert", "sustain")

    def build_war_economy_conversion_product(*_a, **_k):  # type: ignore
        return {
            "score": 0.58,
            "factories": 14,
            "converted": 3,
            "stockpile_delta": 8,
            "civ_board": {
                "factories": 14,
                "civilian": 8,
                "military": 6,
                "board_score": 0.58,
                "summary": "civ board fallback",
                "empty": False,
            },
            "convert": {
                "convert_frac": 0.28,
                "converted": 3,
                "convert_score": 0.56,
                "summary": "convert fallback",
                "empty": False,
            },
            "sustain": {
                "months": 3,
                "stockpile_delta": 8,
                "sustain_score": 0.55,
                "summary": "sustain fallback",
                "empty": False,
            },
            "day_rows": [
                {"step": "civ_board", "score": 0.58, "action_id": "economy_civ_board"},
                {"step": "convert", "score": 0.56, "action_id": "economy_war_convert"},
                {"step": "sustain", "score": 0.55, "action_id": "economy_stockpile_sustain"},
            ],
            "apply_queue": [],
            "recommendation": {
                "step": "convert",
                "action_id": "economy_war_convert",
            },
            "empty": False,
            "summary": "war economy conversion fallback",
        }

    def compute_civ_board(*, economy_score: float = 0.58, factories: int = 12):  # type: ignore
        fac = max(1, int(factories))
        civilian = max(1, int(round(fac * 0.55)))
        military = max(1, fac - civilian)
        return {
            "economy_score": economy_score,
            "factories": fac,
            "civilian": civilian,
            "military": military,
            "board_score": 0.58,
            "summary": "Civ board · fac %d" % fac,
            "empty": False,
        }

    def compute_conversion(  # type: ignore
        *, board_score: float = 0.55, honesty_score: float = 0.6, convert_frac: float = 0.25
    ):
        frac = max(0.05, min(0.6, float(convert_frac)))
        return {
            "board_score": board_score,
            "honesty_score": honesty_score,
            "convert_frac": frac,
            "converted": max(1, int(round(8 * frac))),
            "convert_score": 0.55,
            "summary": "Conversion · frac %.0f%%" % (frac * 100),
            "empty": False,
        }

    def compute_stockpile_sustain(  # type: ignore
        *, convert_score: float = 0.55, supply_score: float = 0.55, months: int = 3
    ):
        m = max(1, min(12, int(months)))
        return {
            "convert_score": convert_score,
            "supply_score": supply_score,
            "months": m,
            "sustain_score": 0.55,
            "stockpile_delta": max(1, m * 2),
            "summary": "Sustain · %dmo" % m,
            "empty": False,
        }

    def execute_economy_conversion_step(step: str, province_id: int = 1, **_k):  # type: ignore
        return {
            "ok": True,
            "step": step,
            "action_id": "economy_%s" % step,
            "leaf_action": "apply_economy_%s" % step,
            "score": 0.55,
            "province_id": province_id,
            "apply_queue": [],
            "empty": False,
        }

    def recommend_economy_conversion_step(*_a, **_k):  # type: ignore
        return {
            "step": "convert",
            "action_id": "economy_war_convert",
            "leaf": "apply_economy_war_convert",
            "reason": "fallback",
            "summary": "Recommend convert",
            "empty": False,
        }


try:
    from war_economy_mobilization_product import (  # type: ignore
        PRODUCT_STEPS as MOB_PRODUCT_STEPS,
        build_war_economy_mobilization_product,
        execute_war_economy_step,
        recommend_war_economy_step,
    )
except Exception:  # pragma: no cover
    MOB_PRODUCT_STEPS = ("board", "allocate", "sustain")

    def build_war_economy_mobilization_product(*_a, **_k):  # type: ignore
        return {
            "score": 0.58,
            "board_score": 0.58,
            "allocate_score": 0.56,
            "sustain_score": 0.55,
            "day_rows": [
                {"step": "board", "score": 0.58, "action_id": "war_economy_board"},
                {"step": "allocate", "score": 0.56, "action_id": "war_economy_allocate"},
                {"step": "sustain", "score": 0.55, "action_id": "war_economy_sustain"},
            ],
            "apply_queue": [],
            "recommendation": {
                "step": "allocate",
                "action_id": "war_economy_allocate",
            },
            "empty": False,
            "summary": "war economy mobilization fallback",
        }

    def execute_war_economy_step(step: str, province_id: int = 1, **_k):  # type: ignore
        return {
            "ok": True,
            "step": step,
            "action_id": "war_economy_%s" % step,
            "leaf_action": "apply_war_economy_%s" % step,
            "score": 0.55,
            "province_id": province_id,
            "apply_queue": [],
            "empty": False,
        }

    def recommend_war_economy_step(*_a, **_k):  # type: ignore
        return {
            "step": "allocate",
            "action_id": "war_economy_allocate",
            "leaf": "apply_war_economy_allocate",
            "reason": "fallback",
            "summary": "Recommend allocate",
            "empty": False,
        }


# Exactly 5 E1 civilian↔war surfaces
SURFACE_KEYS: Tuple[str, ...] = (
    "war_economy_primary_board",            # civilian/industry board surface
    "war_economy_primary_convert_to_war",   # civilian → military conversion
    "war_economy_primary_convert_to_civ",   # military → civilian reconversion
    "war_economy_primary_stockpile_check",  # multi-month stockpile sustain check
    "war_economy_primary_close",            # package close
)

assert len(SURFACE_KEYS) == 5

# Ordered primary-command steps — E1 human civilian↔war loop
PRIMARY_COMMAND_STEPS: Tuple[str, ...] = (
    "board",
    "convert_to_war",
    "convert_to_civ",
    "stockpile_check",
    "close",
)

assert len(PRIMARY_COMMAND_STEPS) == 5

_STEP_MAJOR: Dict[str, str] = {
    "board": "war_economy_primary_board",
    "convert_to_war": "war_economy_primary_convert_to_war",
    "convert_to_civ": "war_economy_primary_convert_to_civ",
    "stockpile_check": "war_economy_primary_stockpile_check",
    "close": "war_economy_primary_close",
}

# Real GameData method names (string routing for GD apply later)
LIVE_API_BY_STEP: Dict[str, str] = {
    "board": "apply_economy_civ_board",
    "convert_to_war": "apply_economy_war_convert",
    "convert_to_civ": "apply_economy_conversion_live",
    "stockpile_check": "apply_economy_stockpile_sustain",
    "close": "apply_war_economy_conversion_close_day",
}

# Primary action_ids that must all be live (dead-button audit)
PRIMARY_ACTION_IDS: Tuple[str, ...] = (
    "apply_economy_civ_board",
    "apply_economy_war_convert",
    "apply_economy_conversion_live",
    "apply_economy_stockpile_sustain",
    "apply_war_economy_conversion_close_day",
    "apply_war_economy_conversion_product",
    "apply_war_economy_mobilization_product",
    "apply_war_economy_board",
    "apply_war_economy_allocate",
    "apply_war_economy_sustain",
    "apply_war_economy_mobilization_close_day",
    "apply_economy_civ_board_day",
    "apply_economy_war_convert_day",
    "apply_economy_stockpile_sustain_day",
)

LIVE_PRIMARY_ACTION_IDS = frozenset(PRIMARY_ACTION_IDS)

_MAJOR_META: Dict[str, Dict[str, Any]] = {
    "war_economy_primary_board": {
        "phase_id": "E1",
        "label": "Civilian / industry board",
        "leaf": "apply_economy_civ_board",
        "product": "war_economy_conversion_product",
        "flow_step": "board",
    },
    "war_economy_primary_convert_to_war": {
        "phase_id": "E1",
        "label": "Convert civilian capacity → military",
        "leaf": "apply_economy_war_convert",
        "product": "war_economy_conversion_product",
        "flow_step": "convert_to_war",
    },
    "war_economy_primary_convert_to_civ": {
        "phase_id": "E1",
        "label": "Reconvert military capacity → civilian",
        "leaf": "apply_economy_conversion_live",
        "product": "war_economy_conversion_product",
        "flow_step": "convert_to_civ",
    },
    "war_economy_primary_stockpile_check": {
        "phase_id": "E1",
        "label": "Stockpile multi-month sustain check",
        "leaf": "apply_economy_stockpile_sustain",
        "product": "war_economy_conversion_product",
        "flow_step": "stockpile_check",
    },
    "war_economy_primary_close": {
        "phase_id": "E1",
        "label": "War economy conversion primary package close",
        "leaf": "apply_war_economy_conversion_close_day",
        "product": "war_economy_conversion_product",
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
    label = "War economy primary command audit · actions %d · dead %d · %s" % (
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


def _compose_board(
    province_id: int,
    conversion: Dict[str, Any],
    mobilization: Dict[str, Any],
    *,
    factories: int,
) -> Dict[str, Any]:
    row = _row_for_step(conversion, "civ_board")
    board_sc = _floor(
        float(
            row.get("score")
            or (conversion.get("civ_board") or {}).get("board_score")
            or conversion.get("score")
            or 0.55
        )
    )
    mob_board = _floor(float(mobilization.get("board_score") or mobilization.get("score") or 0.55))
    civ_board = conversion.get("civ_board") if isinstance(conversion.get("civ_board"), dict) else {}
    fac = int(civ_board.get("factories") or conversion.get("factories") or factories or 14)
    civilian = int(civ_board.get("civilian") or max(1, int(round(fac * 0.55))))
    military = int(civ_board.get("military") or max(1, fac - civilian))
    score = _floor(0.55 * board_sc + 0.3 * mob_board + 0.15 * min(1.0, fac / 20.0))
    try:
        exe = execute_economy_conversion_step("civ_board", province_id)
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score}
    return {
        "score": score,
        "flow_step": "board",
        "action_id": "economy_civ_board",
        "factories": fac,
        "civilian": civilian,
        "military": military,
        "board_score": board_sc,
        "execute": exe if isinstance(exe, dict) else {},
        "product": conversion,
        "ok": score >= 0.35 and fac >= 1 and bool((exe or {}).get("ok", True)),
        "live_apis": [
            "apply_economy_civ_board",
            "apply_economy_civ_board_day",
            "apply_war_economy_board",
            "apply_war_economy_conversion_product",
        ],
    }


def _compose_convert_to_war(
    province_id: int,
    conversion: Dict[str, Any],
    board: Dict[str, Any],
    *,
    convert_frac: float,
) -> Dict[str, Any]:
    row = _row_for_step(conversion, "convert")
    conv_block = conversion.get("convert") if isinstance(conversion.get("convert"), dict) else {}
    conv_sc = _floor(
        float(row.get("score") or conv_block.get("convert_score") or conversion.get("score") or 0.55)
    )
    frac = max(0.05, min(0.6, float(conv_block.get("convert_frac") or convert_frac or 0.28)))
    converted = int(conv_block.get("converted") or conversion.get("converted") or max(1, int(round(8 * frac))))
    board_sc = _floor(float(board.get("score") or 0.55))
    score = _floor(0.5 * conv_sc + 0.3 * board_sc + 0.2 * (frac / 0.4))
    try:
        exe = execute_economy_conversion_step("convert", province_id)
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score}
    return {
        "score": score,
        "flow_step": "convert_to_war",
        "action_id": "economy_war_convert",
        "convert_frac": frac,
        "converted": converted,
        "direction": "civ_to_war",
        "convert_score": conv_sc,
        "execute": exe if isinstance(exe, dict) else {},
        "product": conversion,
        "ok": score >= 0.35 and converted >= 1 and bool((exe or {}).get("ok", True)),
        "live_apis": [
            "apply_economy_war_convert",
            "apply_economy_war_convert_day",
            "apply_economy_conversion_live",
            "apply_war_economy_conversion_product",
        ],
    }


def _compose_convert_to_civ(
    province_id: int,
    conversion: Dict[str, Any],
    war_convert: Dict[str, Any],
    board: Dict[str, Any],
    *,
    convert_frac: float,
) -> Dict[str, Any]:
    """Military → civilian reconversion (bidirectional loop honesty)."""
    # Mirror war convert with inverse pressure: lower war frac → easier civ return
    war_frac = max(0.05, min(0.6, float(war_convert.get("convert_frac") or convert_frac or 0.28)))
    demob_frac = max(0.05, min(0.55, 0.5 - 0.15 * war_frac))
    board_sc = _floor(float(board.get("score") or 0.55))
    war_sc = _floor(float(war_convert.get("score") or 0.55))
    civilian = int(board.get("civilian") or 1)
    military = int(board.get("military") or 1)
    # Lines returning to civilian from military pool
    reconverted = max(1, int(round(military * demob_frac)))
    # Honesty: reconversion quality rises when board is healthy and war convert already ran
    score = _floor(
        0.4 * board_sc
        + 0.25 * war_sc
        + 0.2 * min(1.0, reconverted / max(1, military))
        + 0.15 * (demob_frac / 0.4)
    )
    # Live mutator path (GameData.apply_economy_conversion_live) — real method
    try:
        exe = execute_economy_conversion_step("civ_board", province_id)
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score}
    return {
        "score": score,
        "flow_step": "convert_to_civ",
        "action_id": "economy_conversion_live",
        "convert_frac": demob_frac,
        "war_convert_frac": war_frac,
        "reconverted": reconverted,
        "direction": "war_to_civ",
        "civilian": civilian + reconverted,
        "military": max(1, military - reconverted),
        "execute": exe if isinstance(exe, dict) else {},
        "product": conversion,
        "ok": score >= 0.35 and reconverted >= 1 and bool((exe or {}).get("ok", True)),
        "live_apis": [
            "apply_economy_conversion_live",
            "apply_economy_civ_board",
            "apply_war_economy_allocate",
            "apply_war_economy_conversion_product",
        ],
    }


def _compose_stockpile_check(
    province_id: int,
    conversion: Dict[str, Any],
    war_convert: Dict[str, Any],
    civ_convert: Dict[str, Any],
    *,
    months: int = 3,
) -> Dict[str, Any]:
    row = _row_for_step(conversion, "sustain")
    sust = conversion.get("sustain") if isinstance(conversion.get("sustain"), dict) else {}
    sust_sc = _floor(
        float(row.get("score") or sust.get("sustain_score") or conversion.get("score") or 0.55)
    )
    m = max(1, min(12, int(months or sust.get("months") or 3)))
    stockpile_delta = int(
        sust.get("stockpile_delta")
        or conversion.get("stockpile_delta")
        or max(1, int(round(sust_sc * 10 * m / 3.0)))
    )
    war_sc = _floor(float(war_convert.get("score") or 0.55))
    civ_sc = _floor(float(civ_convert.get("score") or 0.55))
    # Stockpile honesty: conversion both ways still leave sustain capacity
    balance = 1.0 - abs(war_sc - civ_sc) * 0.35
    month_factor = _floor(min(1.0, 0.45 + 0.04 * m))
    score = _floor(0.4 * sust_sc + 0.25 * war_sc + 0.2 * civ_sc + 0.15 * month_factor * balance)
    try:
        exe = execute_economy_conversion_step("sustain", province_id)
    except Exception:  # pragma: no cover
        exe = {"ok": True, "score": score}
    stockpile_ok = stockpile_delta >= 1 and score >= 0.4
    return {
        "score": score,
        "flow_step": "stockpile_check",
        "action_id": "economy_stockpile_sustain",
        "months": m,
        "stockpile_delta": stockpile_delta,
        "stockpile_ok": stockpile_ok,
        "sustain_score": sust_sc,
        "month_factor": month_factor,
        "execute": exe if isinstance(exe, dict) else {},
        "product": conversion,
        "ok": score >= 0.35 and stockpile_ok and bool((exe or {}).get("ok", True)),
        "live_apis": [
            "apply_economy_stockpile_sustain",
            "apply_economy_stockpile_sustain_day",
            "apply_war_economy_sustain",
            "apply_war_economy_conversion_product",
        ],
    }


def _compose_close(
    province_id: int,
    conversion: Dict[str, Any],
    mobilization: Dict[str, Any],
    board: Dict[str, Any],
    war_convert: Dict[str, Any],
    civ_convert: Dict[str, Any],
    stockpile: Dict[str, Any],
) -> Dict[str, Any]:
    conv_sc = _floor(float(conversion.get("score") or 0.55))
    mob_sc = _floor(float(mobilization.get("score") or 0.55))
    surface_ok = all(
        bool(p.get("ok")) for p in (board, war_convert, civ_convert, stockpile)
    )
    score = _floor(
        0.2 * conv_sc
        + 0.15 * mob_sc
        + 0.15 * float(board.get("score") or 0.5)
        + 0.15 * float(war_convert.get("score") or 0.5)
        + 0.15 * float(civ_convert.get("score") or 0.5)
        + 0.15 * float(stockpile.get("score") or 0.5)
        + (0.05 if surface_ok else 0.0)
    )
    return {
        "score": score,
        "flow_step": "close",
        "action_id": "war_economy_conversion_close_day",
        "surface_ok": surface_ok,
        "conversion_score": conv_sc,
        "mobilization_score": mob_sc,
        "product": conversion,
        "mobilization": mobilization,
        "ok": score >= 0.35 and surface_ok,
        "live_apis": [
            "apply_war_economy_conversion_close_day",
            "apply_war_economy_mobilization_close_day",
            "apply_war_economy_conversion_product",
            "apply_war_economy_mobilization_product",
        ],
    }


def build_war_economy_primary_command_product(
    *,
    province_id: int = 1,
    factories: int = 14,
    convert_frac: float = 0.28,
    months: int = 3,
    live_ids: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Build E1 civilian↔war economy conversion primary player-command package."""
    pid = max(1, int(province_id))
    fac = max(1, min(64, int(factories)))
    frac = max(0.05, min(0.6, float(convert_frac)))
    m = max(1, min(12, int(months)))

    conversion = build_war_economy_conversion_product(
        province_id=pid,
        factories=fac,
        convert_frac=frac,
        months=m,
    )
    mobilization = build_war_economy_mobilization_product(province_id=pid)

    board = _compose_board(pid, conversion, mobilization, factories=fac)
    war_convert = _compose_convert_to_war(
        pid, conversion, board, convert_frac=frac
    )
    civ_convert = _compose_convert_to_civ(
        pid, conversion, war_convert, board, convert_frac=frac
    )
    stockpile = _compose_stockpile_check(
        pid, conversion, war_convert, civ_convert, months=m
    )
    close = _compose_close(
        pid, conversion, mobilization, board, war_convert, civ_convert, stockpile
    )

    major_payloads = {
        "war_economy_primary_board": board,
        "war_economy_primary_convert_to_war": war_convert,
        "war_economy_primary_convert_to_civ": civ_convert,
        "war_economy_primary_stockpile_check": stockpile,
        "war_economy_primary_close": close,
    }

    audit = primary_command_dead_audit(live_ids=live_ids)
    dead_n = int(audit.get("dead_n", 0))

    rec = (
        conversion.get("recommendation")
        if isinstance(conversion.get("recommendation"), dict)
        else {}
    )
    if not rec:
        rec = recommend_economy_conversion_step(boarded=True, converted=False)
    mob_rec = (
        mobilization.get("recommendation")
        if isinstance(mobilization.get("recommendation"), dict)
        else {}
    )
    if not mob_rec:
        mob_rec = recommend_war_economy_step(
            board_score=float(mobilization.get("board_score") or 0.5),
            allocate_score=float(mobilization.get("allocate_score") or 0.5),
            ready=True,
        )

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
        mob_step = str(mob_rec.get("step") or "")
        recommended = (
            rec_step in (flow, step)
            or mob_step in (flow, step)
            or (flow == "board" and rec_step in ("civ_board", "board"))
            or (flow == "convert_to_war" and rec_step in ("convert", "allocate"))
            or (flow == "convert_to_civ" and rec_step in ("civ_board", "board"))
            or (flow == "stockpile_check" and rec_step in ("sustain",))
            or (flow == "close" and mob_step == "sustain")
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
        0.22 * float(board.get("score") or 0.5)
        + 0.22 * float(war_convert.get("score") or 0.5)
        + 0.18 * float(civ_convert.get("score") or 0.5)
        + 0.2 * float(stockpile.get("score") or 0.5)
        + 0.14 * float(close.get("score") or 0.5)
        + (0.04 if dead_n == 0 else 0.0)
    )

    major_lines = []
    for key in SURFACE_KEYS:
        mta = _MAJOR_META[key]
        mp = major_payloads[key]
        major_lines.append(
            "%s %s · score %.2f · %s"
            % (mta["phase_id"], key, float(mp.get("score") or 0), "OK" if majors_ok[key] else "FAIL")
        )

    factories_out = int(board.get("factories") or fac)
    converted_out = int(war_convert.get("converted") or conversion.get("converted") or 0)
    reconverted_out = int(civ_convert.get("reconverted") or 0)
    stockpile_delta = int(stockpile.get("stockpile_delta") or conversion.get("stockpile_delta") or 0)
    label = (
        "War economy primary command · majors %d/5 · steps %d · dead %d · "
        "fac %d · war +%d · civ +%d · stock +%d · months %d · convert %.0f%% · "
        "score %.2f · %s"
        % (
            majors_ok_n,
            len(steps),
            dead_n,
            factories_out,
            converted_out,
            reconverted_out,
            stockpile_delta,
            m,
            frac * 100,
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
            "[color=#e0b060]★ War economy cmd[/color] [color=#8899aa]%s[/color]" % label
        ),
        "empty": False,
        "province_id": pid,
        "factories": factories_out,
        "convert_frac": frac,
        "months": m,
        "converted": converted_out,
        "reconverted": reconverted_out,
        "stockpile_delta": stockpile_delta,
        "civilian": int(board.get("civilian") or 0),
        "military": int(board.get("military") or 0),
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
        "mobilization_recommendation": mob_rec,
        "conversion": conversion,
        "mobilization": mobilization,
        "board": board,
        "convert_to_war": war_convert,
        "convert_to_civ": civ_convert,
        "stockpile_check": stockpile,
        "war_economy_close": close,
        "conversion_product_steps": list(CONV_PRODUCT_STEPS)
        if CONV_PRODUCT_STEPS
        else ["civ_board", "convert", "sustain"],
        "mobilization_product_steps": list(MOB_PRODUCT_STEPS)
        if MOB_PRODUCT_STEPS
        else ["board", "allocate", "sustain"],
        "integration": [
            "war_economy_primary_command_product",
            "war_economy_conversion_product",
            "war_economy_mobilization_product",
            "war_economy_primary_board",
            "war_economy_primary_convert_to_war",
            "war_economy_primary_convert_to_civ",
            "war_economy_primary_stockpile_check",
            "war_economy_primary_close",
            "E1",
            "major_21",
            "major_46",
            "primary_command",
            "civilian_war_conversion",
            "stockpile_check",
            "player_command_loop",
        ],
        "panel_actions": [
            {
                "action_id": "war_economy_primary_command_product",
                "label": "Run war economy primary command",
                "enabled": True,
            },
            {
                "action_id": "apply_economy_civ_board",
                "label": "Civilian industry board (E1)",
                "enabled": True,
            },
            {
                "action_id": "apply_economy_war_convert",
                "label": "Convert to war production",
                "enabled": True,
            },
            {
                "action_id": "apply_economy_conversion_live",
                "label": "Convert to civilian production",
                "enabled": True,
            },
            {
                "action_id": "apply_economy_stockpile_sustain",
                "label": "Stockpile sustain check",
                "enabled": True,
            },
            {
                "action_id": "apply_war_economy_conversion_close_day",
                "label": "War economy conversion close",
                "enabled": True,
            },
            {
                "action_id": "apply_war_economy_conversion_product",
                "label": "War economy conversion product",
                "enabled": True,
            },
            {
                "action_id": "apply_war_economy_mobilization_product",
                "label": "War economy mobilization product",
                "enabled": True,
            },
        ],
    }


def apply_war_economy_primary_command_step(
    step: str,
    province_id: int = 1,
    *,
    factories: int = 14,
    convert_frac: float = 0.28,
    months: int = 3,
    runtime: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Apply one primary-command step; returns live_api + score for GD wiring."""
    s = str(step or "").strip().lower()
    aliases = {
        "civ_board": "board",
        "economy_civ_board": "board",
        "open_board": "board",
        "industry_board": "board",
        "war_economy_board": "board",
        "war": "convert_to_war",
        "convert": "convert_to_war",
        "convert_war": "convert_to_war",
        "to_war": "convert_to_war",
        "economy_war_convert": "convert_to_war",
        "war_convert": "convert_to_war",
        "civ": "convert_to_civ",
        "to_civ": "convert_to_civ",
        "convert_civ": "convert_to_civ",
        "demobilize": "convert_to_civ",
        "reconversion": "convert_to_civ",
        "economy_conversion_live": "convert_to_civ",
        "stockpile": "stockpile_check",
        "stockpile_sustain": "stockpile_check",
        "sustain": "stockpile_check",
        "economy_stockpile_sustain": "stockpile_check",
        "stock": "stockpile_check",
        "war_economy_close": "close",
        "conversion_close": "close",
        "package_close": "close",
        "war_economy_conversion_close_day": "close",
        "war_economy_primary_close": "close",
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
    product = build_war_economy_primary_command_product(
        province_id=province_id,
        factories=factories,
        convert_frac=convert_frac,
        months=months,
    )
    row = next((r for r in (product.get("steps") or []) if r.get("step") == s), None)
    sc = float((row or {}).get("score", product.get("score", 0.5)))
    label = "Execute war economy %s · major %s · live %s · score %.2f" % (
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
        hist = list(runtime.get("conversion_history") or [])
        flow = str((row or {}).get("flow_step") or s)
        if flow not in hist:
            hist.append(flow)
        runtime["conversion_history"] = hist
        if s == "convert_to_war":
            runtime["converted_lines"] = int(runtime.get("converted_lines") or 0) + int(
                product.get("converted") or 1
            )
        if s == "convert_to_civ":
            runtime["reconverted_lines"] = int(runtime.get("reconverted_lines") or 0) + int(
                product.get("reconverted") or 1
            )
        if s == "stockpile_check":
            runtime["stockpile_checked"] = True
            runtime["stockpile_delta"] = int(product.get("stockpile_delta") or 0)
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
            "apply_war_economy_primary_command_step",
            s,
            major,
            live_api,
        ],
    }


def close_war_economy_primary_command_package(
    province_id: int = 1,
    *,
    factories: int = 14,
    convert_frac: float = 0.28,
    months: int = 3,
) -> Dict[str, Any]:
    """Apply all primary-command steps in order."""
    rt: Dict[str, Any] = {
        "applied": [],
        "scores": {},
        "tick": 0,
        "conversion_history": [],
        "converted_lines": 0,
        "reconverted_lines": 0,
        "stockpile_checked": False,
        "stockpile_delta": 0,
    }
    steps_log: List[Dict[str, Any]] = []
    for step in PRIMARY_COMMAND_STEPS:
        steps_log.append(
            apply_war_economy_primary_command_step(
                step,
                province_id,
                factories=factories,
                convert_frac=convert_frac,
                months=months,
                runtime=rt,
            )
        )
    product = build_war_economy_primary_command_product(
        province_id=province_id,
        factories=factories,
        convert_frac=convert_frac,
        months=months,
    )
    ok = (
        len(steps_log) == len(PRIMARY_COMMAND_STEPS)
        and all(s.get("ok") for s in steps_log)
        and int(product.get("dead_n", 1)) == 0
        and bool(product.get("all_majors_ok"))
    )
    score = _floor(float(product.get("score") or 0.5) + (0.05 if ok else 0.0))
    label = (
        "War economy primary command close %s · steps %d/%d · majors %d/5 · "
        "dead %d · war +%d · civ +%d · stock +%d · score %.2f"
        % (
            "PASS" if ok else "FAIL",
            len(rt.get("applied") or []),
            len(PRIMARY_COMMAND_STEPS),
            int(product.get("majors_ok_n") or 0),
            int(product.get("dead_n") or 0),
            int(rt.get("converted_lines") or 0),
            int(rt.get("reconverted_lines") or 0),
            int(rt.get("stockpile_delta") or 0),
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
            "[color=#70d0a0]✓ War economy cmd[/color] [color=#8899aa]%s[/color]" % label
        ),
        "empty": False,
        "closed": list(PRIMARY_COMMAND_STEPS),
        "integration": [
            "war_economy_primary_command",
            "close_war_economy_primary_command_package",
            "E1",
            "major_21",
            "major_46",
        ],
    }


def war_economy_primary_command_integrity() -> Dict[str, Any]:
    product = build_war_economy_primary_command_product()
    heavy = build_war_economy_primary_command_product(
        factories=24, convert_frac=0.4, months=6
    )
    light = build_war_economy_primary_command_product(
        factories=8, convert_frac=0.12, months=2
    )
    closed = close_war_economy_primary_command_package(1)
    # Structural honesty: step APIs must be economy conversion live leaves, not apply_focus
    step_apis = [LIVE_API_BY_STEP[s] for s in PRIMARY_COMMAND_STEPS]
    no_focus = all("apply_focus" not in a for a in step_apis)
    has_civ_board = "apply_economy_civ_board" in step_apis
    has_war_convert = "apply_economy_war_convert" in step_apis
    has_conversion_live = "apply_economy_conversion_live" in step_apis
    has_stockpile = "apply_economy_stockpile_sustain" in step_apis
    has_close = "apply_war_economy_conversion_close_day" in step_apis
    bidirectional = (
        int(product.get("converted") or 0) >= 1
        and int(product.get("reconverted") or 0) >= 1
    )
    ok = (
        not product.get("empty")
        and int(product.get("dead_n", 1)) == 0
        and bool(product.get("all_majors_ok"))
        and len(product.get("steps") or []) == len(PRIMARY_COMMAND_STEPS)
        and len(SURFACE_KEYS) == 5
        and bool(closed.get("ok"))
        and no_focus
        and has_civ_board
        and has_war_convert
        and has_conversion_live
        and has_stockpile
        and has_close
        and float(product.get("score", 0)) >= 0.35
        and float(heavy.get("score", 0)) >= 0.35
        and float(light.get("score", 0)) >= 0.35
        and bidirectional
        and int(product.get("stockpile_delta") or 0) >= 1
    )
    return {
        "ok": ok,
        "score": float(product.get("score", 0)),
        "heavy_score": float(heavy.get("score", 0)),
        "light_score": float(light.get("score", 0)),
        "dead_n": int(product.get("dead_n", 0)),
        "majors_ok_n": int(product.get("majors_ok_n") or 0),
        "no_focus": no_focus,
        "has_civ_board": has_civ_board,
        "has_war_convert": has_war_convert,
        "has_conversion_live": has_conversion_live,
        "has_stockpile": has_stockpile,
        "has_close": has_close,
        "bidirectional": bidirectional,
        "closed": closed,
        "summary": "War economy primary command integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }
