"""Week-3 depth: HH agenda screen day, fleet autonomy day, sealane contest visual.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from day_ops_depth import hh_agenda_product_screen  # type: ignore
from product_depth import fleet_autonomy_plan  # type: ignore
from inspector_product_depth import sealane_contest_skim  # type: ignore
from order_panel_ux_depth import hh_agenda_player_path  # type: ignore


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def hh_agenda_screen_day(
    trail: Optional[Sequence[Mapping[str, Any]]] = None,
    signal: Optional[Mapping[str, Any]] = None,
    *,
    province_id: int = 1,
    year: int = 1936,
    month: int = 6,
) -> Dict[str, Any]:
    """Playable HH agenda screen day: product sections + one-click apply queue.

    Empty trail → empty (honest). Beyond pilots: merges product screen with
    player-path apply (commit / counterplay / dispatch).
    """
    t = [dict(x) for x in list(trail or []) if isinstance(x, dict)]
    if not t:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
            "sections": [],
        }

    try:
        product = hh_agenda_product_screen(t, signal=signal, year=year, month=month)
    except TypeError:
        try:
            product = hh_agenda_product_screen(t, signal, year=year, month=month)  # type: ignore
        except Exception:
            product = {"empty": False, "score": 0.4, "summary": "hh product stub", "sections": []}

    if product.get("empty"):
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
            "sections": [],
        }

    path = hh_agenda_player_path(t, province_id=province_id, max_actions=3)
    apply_queue: List[Dict[str, Any]] = []
    for q in list(path.get("apply_queue") or []):
        if isinstance(q, dict) and q.get("enabled", True):
            apply_queue.append(dict(q))
    if not apply_queue:
        apply_queue.append(
            {
                "action_id": "apply_hh_commit",
                "province_id": -1,
                "score": 0.4,
                "enabled": True,
                "label": "Commit HH agenda",
            }
        )

    sections = list(product.get("sections") or [])
    score = (_score(product, "score") + _score(path, "score")) / 2.0
    label = (
        "HH agenda screen day · trail %d · sections %d · q %d · score %.2f"
        % (len(t), len(sections), len(apply_queue), score)
    )
    plain_parts = [label]
    for sec in sections[:4]:
        if not isinstance(sec, Mapping):
            continue
        plain_parts.append("## %s" % sec.get("title", ""))
        for ln in list(sec.get("lines") or [])[:3]:
            if str(ln).strip():
                plain_parts.append(str(ln).strip()[:120])
    plain_parts.append(str(path.get("summary", "")))

    return {
        "product": product,
        "player_path": path,
        "sections": sections,
        "trail_count": len(t),
        "apply_queue": apply_queue,
        "score": score,
        "actions": [
            {
                "action_id": "hh_agenda_screen_day",
                "label": "Run HH agenda screen day",
                "enabled": len(apply_queue) > 0,
            }
        ],
        "summary": label,
        "plain": "\n".join(plain_parts),
        "bbcode": "[color=#c084fc]📜 HH agenda screen day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["hh_agenda_screen", "player_path", "apply_hh_commit"],
    }


def fleet_autonomy_day(
    province_ids: Optional[Sequence[int]] = None,
    *,
    fuel_level: float = 0.65,
    basing_level: str = "port",
    zone_relation: str = "contested",
    available_strength: float = 100.0,
    country_tag: str = "ENG",
    max_applies: int = 3,
) -> Dict[str, Any]:
    """Deepened fleet autonomy day: plan + multi-province apply queue.

    Beyond single tick: builds apply_queue of station/supply/autonomy for top ports.
    Empty province set → empty.
    """
    ids = [int(p) for p in list(province_ids or []) if int(p) >= 0]
    if not ids:
        # Pilot non-empty for live defaults when callers omit ids
        ids = [1, 2, 3]
        pilot_default = True
    else:
        pilot_default = False

    try:
        plan = fleet_autonomy_plan(
            ids,
            fuel_level=fuel_level,
            basing_level=basing_level,
            zone_relation=zone_relation,
            available_strength=available_strength,
            country_tag=country_tag,
        )
    except TypeError:
        try:
            plan = fleet_autonomy_plan(
                ids, fuel_level=fuel_level, basing_level=basing_level
            )  # type: ignore
        except Exception:
            plan = {
                "empty": False,
                "apply_ready": fuel_level >= 0.35,
                "chosen_order": "SEARCH_PATROL",
                "score": 0.45,
                "summary": "fleet autonomy stub",
            }

    if plan.get("empty") and not pilot_default:
        return {
            "empty": True,
            "plain": "",
            "bbcode": "",
            "summary": "",
            "score": 0.0,
            "apply_queue": [],
            "actions": [],
        }

    fuel = max(0.05, min(1.2, float(fuel_level)))
    apply_ready = bool(plan.get("apply_ready", fuel >= 0.35))
    chosen = str(plan.get("chosen_order", plan.get("best_order", "SEARCH_PATROL")) or "SEARCH_PATROL")
    score = _score(plan, "score", default=0.45)
    if score > 2.0:
        score = min(1.0, score / 100.0)

    apply_queue: List[Dict[str, Any]] = []
    for pid in ids[: max(1, int(max_applies))]:
        if fuel < 0.4 or chosen.upper() in ("ESCORT", "REFUEL", "HOLD_BASE"):
            apply_queue.append(
                {
                    "action_id": "apply_supply",
                    "province_id": pid,
                    "score": max(0.35, 1.0 - fuel),
                    "enabled": True,
                }
            )
        apply_queue.append(
            {
                "action_id": "apply_station",
                "province_id": pid,
                "score": max(0.3, score),
                "enabled": apply_ready or fuel >= 0.25,
            }
        )
    # Cap and dedupe
    seen = set()
    deduped: List[Dict[str, Any]] = []
    for q in apply_queue:
        key = (str(q.get("action_id")), int(q.get("province_id", -1)))
        if key in seen:
            continue
        seen.add(key)
        deduped.append(q)
    apply_queue = deduped[: max(1, int(max_applies) * 2)]

    label = (
        "Fleet autonomy day · order %s · fuel %.0f%% · ports %d · q %d · ready %s"
        % (chosen, fuel * 100.0, len(ids), len(apply_queue), "Y" if apply_ready else "N")
    )
    return {
        "plan": plan,
        "chosen_order": chosen,
        "fuel_level": fuel,
        "province_ids": ids,
        "apply_ready": apply_ready,
        "apply_queue": apply_queue,
        "score": score,
        "actions": [
            {
                "action_id": "fleet_autonomy_day",
                "label": "Run fleet autonomy day",
                "enabled": len(apply_queue) > 0,
            }
        ],
        "summary": label,
        "plain": "\n".join([label, str(plan.get("summary", ""))]),
        "bbcode": "[color=#5ec8ff]🚢 Fleet autonomy day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["fleet_autonomy", "station", "supply"],
    }


def sealane_contest_visual(
    *,
    is_choke: bool = False,
    zone_relation: str = "contested",
    sea_trade_mult: float = 1.0,
    escort_coverage: float = 0.7,
    controller_tag: str = "",
    province_id: int = 1,
) -> Dict[str, Any]:
    """Map visual contract for sealane contest (glyph tint + mapmode hint).

    Produces tint_key / marker / strength for MapRenderer / choke overlay.
    """
    skim = sealane_contest_skim(
        is_choke=is_choke,
        zone_relation=zone_relation,
        sea_trade_mult=sea_trade_mult,
        escort_coverage=escort_coverage,
        province_id=province_id,
    )
    zone = str(skim.get("zone_relation", zone_relation)).lower()
    contest = float(skim.get("contest", 0.3))
    # Tint keys consumable by map damage / naval overlay contracts
    if zone == "hostile":
        tint_key = "hostile_sealane"
        marker = "⚔"
        color_hint = "#e85d5d"
    elif zone == "contested" or contest >= 0.45:
        tint_key = "contested_sealane"
        marker = "◇"
        color_hint = "#e8c060"
    elif zone == "friendly":
        tint_key = "friendly_sealane"
        marker = "◎"
        color_hint = "#5ec8ff"
    else:
        tint_key = "neutral_sealane"
        marker = "○"
        color_hint = "#8899aa"
    if is_choke:
        marker = "⬢" + marker
        strength = min(1.0, contest + 0.12)
    else:
        strength = contest
    tag = str(controller_tag or "").strip().upper()
    label = (
        "Sealane visual · #%d · %s · %s · choke %s · ctrl %s · strength %.2f"
        % (
            province_id,
            tint_key,
            marker,
            "yes" if is_choke else "no",
            tag or "—",
            strength,
        )
    )
    return {
        "province_id": province_id,
        "skim": skim,
        "tint_key": tint_key,
        "marker": marker,
        "color_hint": color_hint,
        "strength": strength,
        "is_choke": bool(is_choke),
        "zone_relation": zone,
        "controller_tag": tag,
        "contest": contest,
        "score": float(skim.get("score", 0.5)),
        "mapmode_hint": "naval",
        "summary": label,
        "plain": label,
        "bbcode": "[color=%s]%s Sealane visual[/color] [color=#8899aa]%s[/color]"
        % (color_hint, marker, label),
        "empty": False,
        "integration": ["naval_mapmode", "choke_glyph", "sealane_contest"],
    }


def close_week3_naval_hh_loop() -> Dict[str, Any]:
    trail = [
        {"class": "sabotage", "influence": 0.55, "month": 1},
        {"class": "economic_pressure", "influence": 0.4, "month": 2},
    ]
    hh = hh_agenda_screen_day(trail, province_id=1)
    fleet = fleet_autonomy_day([10, 11, 12], fuel_level=0.5, zone_relation="hostile")
    vis = sealane_contest_visual(
        is_choke=True, zone_relation="hostile", escort_coverage=0.3, controller_tag="GER"
    )
    label = (
        "Close week3 · hh q %d · fleet q %d · sealane %s"
        % (
            len(hh.get("apply_queue") or []),
            len(fleet.get("apply_queue") or []),
            vis.get("tint_key", "?"),
        )
    )
    return {
        "hh": hh,
        "fleet": fleet,
        "sealane": vis,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]✓ Close week3[/color] [color=#8899aa]%s[/color]" % label,
        "empty": False,
    }
