"""First-session play surface — AND of shipped world_accurate builders.

Thin composer. Child pass bits are p["ok"] except save, which has no ok key
(use all_majors_ok and dead_n == 0).
"""
from __future__ import annotations

from typing import Any, Dict, Mapping

from first_session_assault_surface_product import (  # type: ignore
    build_first_session_assault_surface_product,
)
from first_session_hotkeys_product import (  # type: ignore
    build_first_session_hotkeys_product,
)
from map_live_border_fronts_surface_product import (  # type: ignore
    build_map_live_border_fronts_surface_product,
)
from map_supply_corridor_product import build_supply_corridor_product  # type: ignore
from map_war_path_surface_product import (  # type: ignore
    build_map_war_path_surface_product,
)
from order_panel_play_strip_product import (  # type: ignore
    build_order_panel_play_strip_product,
)
from save_resume_primary_command_product import (  # type: ignore
    build_save_resume_primary_command_product,
)
from world_accurate_capital_pick_product import (  # type: ignore
    build_world_accurate_capital_pick_product,
)


def _save_pass(p: Mapping[str, Any]) -> bool:
    return bool(p.get("all_majors_ok")) and int(p.get("dead_n") or 0) == 0


def _child(ok: bool, summary: Any) -> Dict[str, Any]:
    return {"ok": bool(ok), "summary": str(summary or "")}


def build_first_session_play_surface_product() -> Dict[str, Any]:
    capital_pick = build_world_accurate_capital_pick_product()
    fronts = build_map_live_border_fronts_surface_product(country_tag="GER")
    war_path = build_map_war_path_surface_product(country_tag="GER")
    corridor = build_supply_corridor_product()
    save = build_save_resume_primary_command_product(province_id=1)
    hotkeys = build_first_session_hotkeys_product(player_tag="GER")
    assault = build_first_session_assault_surface_product(
        country_tag="GER", check_wiring=True
    )
    play_strip = build_order_panel_play_strip_product(province_id=1)

    bits = {
        "capital_pick": bool(capital_pick.get("ok")),
        "fronts": bool(fronts.get("ok")),
        "war_path": bool(war_path.get("ok")),
        "corridor": bool(corridor.get("ok")),
        "save": _save_pass(save),
        "hotkeys": bool(hotkeys.get("ok")),
        "assault": bool(assault.get("ok")),
        "play_strip": bool(play_strip.get("ok")),
    }
    products: Dict[str, Mapping[str, Any]] = {
        "capital_pick": capital_pick,
        "fronts": fronts,
        "war_path": war_path,
        "corridor": corridor,
        "save": save,
        "hotkeys": hotkeys,
        "assault": assault,
        "play_strip": play_strip,
    }
    children = {
        name: _child(ok, products[name].get("summary")) for name, ok in bits.items()
    }
    passes = [name for name, ok in bits.items() if ok]
    fails = [name for name, ok in bits.items() if not ok]
    ok = all(bits.values())
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "summary": "First-session play surface · %d/%d · %s"
        % (len(passes), len(bits), "PASS" if ok else "FAIL"),
        "children": children,
    }
