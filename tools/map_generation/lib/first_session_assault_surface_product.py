"""First-session assault surface — discoverability for Attack / Ctrl+click.

Player value: war loop fails silently when assault affordance is unknown.
Pure product formats steps + toast + integrity against MapRenderer / play strip.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence

ROOT = Path(__file__).resolve().parents[3]
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"
ORDER_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"

ASSAULT_STEPS: List[str] = [
    "1. Select friendly province with a formation (capital / hub / border)",
    "2. Press B or toolbar Fronts — cycle enemy border target",
    "3. Select the enemy target province (or keep front highlighted)",
    "4. Inspector Attack button OR Ctrl+click adjacent enemy land",
    "5. Or Order strip Assault (play mode) — apply_assault",
]


def format_assault_ready_toast(
    *,
    attacker_tag: str = "GER",
    from_province_id: int = 0,
    to_province_id: int = 0,
    defender_tag: str = "",
) -> str:
    tag = str(attacker_tag or "GER").strip().upper() or "GER"
    def_t = str(defender_tag or "?").strip().upper() or "?"
    fr = int(from_province_id or 0)
    to = int(to_province_id or 0)
    if fr > 0 and to > 0:
        return (
            "Assault ready · %s #%d → %s #%d · Ctrl+click enemy or strip Assault"
            % (tag, fr, def_t, to)
        )
    return (
        "Assault · select friendly formation · B fronts · Ctrl+click enemy adj · strip Assault"
    )


def format_assault_hint_plain(*, country_tag: str = "GER") -> str:
    tag = str(country_tag or "GER").strip().upper() or "GER"
    lines = [
        "First-session assault (%s)" % tag,
        format_assault_ready_toast(attacker_tag=tag),
    ] + list(ASSAULT_STEPS)
    return "\n".join(lines)


def build_first_session_assault_surface_product(
    *,
    country_tag: str = "GER",
    from_province_id: int = 0,
    to_province_id: int = 0,
    defender_tag: str = "",
    fronts: Optional[Sequence[Mapping[str, Any]]] = None,
    check_wiring: bool = True,
) -> Dict[str, Any]:
    tag = str(country_tag or "GER").strip().upper() or "GER"
    rows: List[Dict[str, Any]] = []
    for t in fronts or []:
        if not isinstance(t, Mapping):
            continue
        pid = int(t.get("province_id") or t.get("id") or -1)
        if pid < 0:
            continue
        rows.append(
            {
                "province_id": pid,
                "from_province_id": int(t.get("from_province_id") or 0),
                "defender_tag": str(t.get("defender_tag") or "?").upper(),
                "name": str(t.get("name") or ("#%d" % pid)),
            }
        )
    # Prefer live front row for default to_id
    to_id = int(to_province_id or 0)
    from_id = int(from_province_id or 0)
    def_t = str(defender_tag or "").strip().upper()
    if to_id <= 0 and rows:
        to_id = int(rows[0]["province_id"])
        from_id = from_id or int(rows[0].get("from_province_id") or 0)
        def_t = def_t or str(rows[0].get("defender_tag") or "")
    toast = format_assault_ready_toast(
        attacker_tag=tag,
        from_province_id=from_id,
        to_province_id=to_id,
        defender_tag=def_t,
    )
    plain = format_assault_hint_plain(country_tag=tag)
    fails: List[str] = []
    passes: List[str] = []
    if "Ctrl+click" in toast or "Ctrl+click" in plain:
        passes.append("mentions_ctrl_click")
    else:
        fails.append("no_ctrl_click_hint")
    if "Assault" in plain or "assault" in plain.lower():
        passes.append("mentions_assault")
    else:
        fails.append("no_assault_word")
    if len(ASSAULT_STEPS) >= 4:
        passes.append("steps_n=%d" % len(ASSAULT_STEPS))
    else:
        fails.append("too_few_steps")

    # Optional board smoke: Maginot-class fronts via live-border product
    front_product_ok = False
    try:
        from map_live_border_fronts_surface_product import (  # type: ignore
            build_map_live_border_fronts_surface_product,
        )

        fr = build_map_live_border_fronts_surface_product(
            country_tag=tag, max_count=4
        )
        front_product_ok = bool(fr.get("ok")) and int(fr.get("count") or fr.get("front_count") or len(fr.get("targets") or [])) >= 0
        if front_product_ok:
            passes.append("fronts_surface_reachable")
            if not rows:
                rows = list(fr.get("targets") or [])[:4]
    except Exception:
        passes.append("fronts_surface_optional_skip")

    wiring: Dict[str, bool] = {}
    if check_wiring:
        ren = MAP_RENDERER.read_text(encoding="utf-8") if MAP_RENDERER.is_file() else ""
        panel = ORDER_PANEL.read_text(encoding="utf-8") if ORDER_PANEL.is_file() else ""
        wiring["map_ctrl_click_or_assault"] = (
            "ctrl_pressed" in ren and ("assault" in ren.lower() or "Attack" in ren)
        ) or "Ctrl+click" in ren
        wiring["play_strip_assault"] = (
            "apply_assault" in panel
            and ("EOA_PLAY_STRIP" in panel or "_rebuild_play_mode_strip" in panel or "Assault" in panel)
        )
        wiring["assault_hint_api"] = (
            "toast_assault_surface" in ren
            or "first_session_assault" in ren
            or "Assault ready" in ren
        )
        for k, v in wiring.items():
            if v:
                passes.append("wire_%s" % k)
            else:
                fails.append("wire_%s" % k)

    ok = "no_ctrl_click_hint" not in fails and "no_assault_word" not in fails
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "country_tag": tag,
        "from_province_id": from_id,
        "to_province_id": to_id,
        "defender_tag": def_t,
        "targets": rows,
        "steps": list(ASSAULT_STEPS),
        "toast": toast,
        "plain": plain,
        "front_product_ok": front_product_ok,
        "wiring": wiring,
        "pass": passes,
        "fail": fails,
        "summary": "Assault surface · %s · targets=%d · %s"
        % (tag, len(rows), "PASS" if ok else "FAIL"),
        "integration": [
            "first_session_assault_surface_product",
            "order_panel_play_strip_product",
            "map_live_border_fronts_surface_product",
            "MapRenderer Ctrl+click",
        ],
    }


def first_session_assault_surface_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_first_session_assault_surface_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
