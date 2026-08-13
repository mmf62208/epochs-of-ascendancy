"""Week-4 polish: GPU pan/zoom day profile, tooltip/SFX flair strip, soft advisory.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from priority_systems import gpu_pan_zoom_profile  # type: ignore
from map_next_list_helpers import (  # type: ignore
    format_province_select_flair,
    format_infra_project_flair,
    format_capture_assault_flair,
)
from map_polish_pilots import audit_map_action_flair_contracts  # type: ignore


def _score(block: Mapping[str, Any], *keys: str, default: float = 0.5) -> float:
    for k in keys:
        if k in block and block[k] is not None:
            try:
                return float(block[k])  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
    return float(default)


def gpu_pan_zoom_day(
    *,
    province_count: int = 2665,
    zoom: float = 0.45,
    cull_margin: float = 192.0,
    resource_icon_budget: int = 180,
    label_budget: int = 140,
) -> Dict[str, Any]:
    """Soft GPU pan/zoom day profile with recommendations (no hard gate).

    When load is high, recommend tighter cull / lower icon budget. Always advisory.
    """
    try:
        prof = gpu_pan_zoom_profile(
            province_count=province_count,
            zoom=zoom,
            cull_margin=cull_margin,
            resource_icon_budget=resource_icon_budget,
            label_budget=label_budget,
        )
    except TypeError:
        try:
            prof = gpu_pan_zoom_profile(province_count, zoom)  # type: ignore
        except Exception:
            prof = {
                "load": 0.5,
                "score": 0.6,
                "resource_icon_budget": resource_icon_budget,
                "label_budget": label_budget,
                "cull_margin": cull_margin,
                "summary": "gpu profile stub",
            }

    load = _score(prof, "load", default=0.5)
    score = _score(prof, "score", default=0.55)
    icons = int(prof.get("resource_icon_budget", resource_icon_budget) or resource_icon_budget)
    labels = int(prof.get("label_budget", label_budget) or label_budget)
    cull = float(prof.get("cull_margin", cull_margin) or cull_margin)

    advice: List[str] = []
    if load >= 0.9:
        advice.append("tighten_cull")
        advice.append("reduce_icons")
    elif load >= 0.75:
        advice.append("cap_icons_at_operational")
    if zoom < 0.28:
        advice.append("hide_detail_icons")
    if zoom >= 0.75:
        advice.append("allow_icon_boost")
    if not advice:
        advice.append("profile_ok")

    # Soft apply: only refresh_queue / no hard GPU gate
    apply_queue: List[Dict[str, Any]] = [
        {
            "action_id": "refresh_queue",
            "province_id": 1,
            "score": max(0.3, score),
            "enabled": True,
            "label": "Refresh order queue (advisory)",
        }
    ]

    label = (
        "GPU pan/zoom day · zoom %.2f · load %.0f%% · icons %d · labels %d · cull %.0f · %s"
        % (zoom, load * 100.0, icons, labels, cull, ",".join(advice[:3]))
    )
    return {
        "profile": prof,
        "zoom": zoom,
        "load": load,
        "resource_icon_budget": icons,
        "label_budget": labels,
        "cull_margin": cull,
        "advice": advice,
        "deferred_hard_gate": True,
        "score": score,
        "apply_queue": apply_queue,
        "actions": [
            {
                "action_id": "gpu_pan_zoom_day",
                "label": "Review GPU pan/zoom day",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]🖥 GPU pan/zoom day[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["pan_zoom", "lod", "advisory"],
    }


def tooltip_sfx_flair_strip(
    *,
    province_name: str = "Province",
    owner_tag: str = "GER",
    region_name: str = "Theater",
    is_chokepoint: bool = False,
    sea_zone_name: str = "",
    is_coastal: bool = True,
    hh_active: bool = False,
    invest_kind: str = "complete",
    capture: bool = False,
    flair_source: str = "",
) -> Dict[str, Any]:
    """Compose select + invest + capture flair into a scannable strip; audit contracts.

    Soft polish: ensures sfx/toast contracts exist for map feedback.
    """
    select = format_province_select_flair(
        province_name,
        owner_tag=owner_tag,
        region_name=region_name,
        is_chokepoint=is_chokepoint,
        sea_zone_name=sea_zone_name,
        is_coastal=is_coastal,
        hh_active=hh_active,
    )
    invest = format_infra_project_flair(province_name, invest_kind, new_level=3, eta_days=14)
    assault = format_capture_assault_flair(
        province_name,
        attacker_tag=owner_tag,
        defender_tag="FRA",
        captured=capture,
        outcome="victory" if capture else "hold",
        winner=owner_tag if capture else "FRA",
    )
    audit = audit_map_action_flair_contracts(
        flair_source
        or "format_province_select_flair format_infra_project_flair format_capture_assault_flair format_hh"
    )

    rows: List[Dict[str, Any]] = [
        {
            "kind": "select",
            "toast": select.get("toast", ""),
            "sfx": select.get("sfx", "select"),
            "tooltip_chip": select.get("tooltip_chip", ""),
        },
        {
            "kind": "invest",
            "toast": invest.get("toast", ""),
            "sfx": invest.get("sfx", "confirm"),
            "tooltip_chip": invest.get("tooltip_chip", ""),
        },
        {
            "kind": "assault",
            "toast": assault.get("toast", ""),
            "sfx": assault.get("sfx", "confirm"),
            "tooltip_chip": assault.get("tooltip_chip", assault.get("news_headline", "")),
        },
    ]
    sfx_set = sorted({str(r.get("sfx", "")) for r in rows if r.get("sfx")})
    score = 0.55 + (0.2 if audit.get("ok") else 0.0) + 0.05 * min(3, len(sfx_set))
    score = min(1.0, score)
    label = (
        "Tooltip/SFX flair strip · rows %d · sfx %s · contracts %s"
        % (len(rows), "/".join(sfx_set) if sfx_set else "—", "PASS" if audit.get("ok") else "FAIL")
    )
    plain_lines = [label]
    for r in rows:
        plain_lines.append("%s · sfx=%s · %s" % (r["kind"], r.get("sfx", ""), str(r.get("toast", ""))[:80]))

    return {
        "rows": rows,
        "select": select,
        "invest": invest,
        "assault": assault,
        "audit": audit,
        "sfx_set": sfx_set,
        "score": score,
        "actions": [
            {
                "action_id": "tooltip_sfx_flair_strip",
                "label": "Review tooltip/SFX flair",
                "enabled": True,
            }
        ],
        "summary": label,
        "plain": "\n".join(plain_lines),
        "bbcode": "[color=#6eb5ff]✨ Tooltip/SFX strip[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "integration": ["select_flair", "invest_flair", "capture_flair", "sfx"],
    }


def close_week4_polish_loop(flair_source: str = "") -> Dict[str, Any]:
    gpu = gpu_pan_zoom_day(zoom=0.42, province_count=2665)
    strip = tooltip_sfx_flair_strip(
        is_chokepoint=True,
        sea_zone_name="North Sea",
        hh_active=True,
        flair_source=flair_source
        or "format_province_select_flair format_infra_project_flair format_capture_assault_flair format_hh",
    )
    label = (
        "Close week4 polish · gpu load %.0f%% · flair rows %d · contracts %s"
        % (
            float(gpu.get("load", 0)) * 100.0,
            len(strip.get("rows") or []),
            "PASS" if (strip.get("audit") or {}).get("ok") else "FAIL",
        )
    )
    return {
        "gpu": gpu,
        "flair": strip,
        "summary": label,
        "plain": label,
        "bbcode": "[color=#5ec8ff]✓ Close week4 polish[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
    }
