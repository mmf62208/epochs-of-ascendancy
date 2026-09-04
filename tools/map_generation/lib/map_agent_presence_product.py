"""On-mission player agent tokens on the living map.

Cap 8. Node2D _draw. No ambient pulse. Idle agents do not spam strategic zoom.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence

ROOT = Path(__file__).resolve().parents[3]
LAYER = ROOT / "scripts" / "map" / "AgentPresenceLayer.gd"
NETWORK = ROOT / "scripts" / "map" / "AgentNetworkLayer.gd"
RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"

MAX_TOKENS = 8


def agent_presence_marker(
    *,
    pid: int,
    on_mission: bool,
    player: bool = True,
) -> Dict[str, Any]:
    empty = {"ok": False, "empty": True, "pid": -1, "on_mission": False}
    if int(pid or 0) <= 0 or not on_mission or not player:
        return empty
    return {
        "ok": True,
        "empty": False,
        "pid": int(pid),
        "on_mission": True,
    }


def cap_agent_tokens(
    rows: Optional[Sequence[Mapping[str, Any]]] = None,
    max_n: int = MAX_TOKENS,
) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for raw in rows or []:
        if not isinstance(raw, Mapping):
            continue
        marker = agent_presence_marker(
            pid=int(raw.get("pid") or raw.get("assigned_province_id") or 0),
            on_mission=bool(raw.get("on_mission") or raw.get("current_mission_id")),
            player=bool(raw.get("player", True)),
        )
        if marker.get("ok"):
            out.append(marker)
        if len(out) >= max(1, int(max_n or MAX_TOKENS)):
            break
    return out


def map_agent_presence_integrity() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    lyr = LAYER.read_text(encoding="utf-8") if LAYER.is_file() else ""
    net = NETWORK.read_text(encoding="utf-8") if NETWORK.is_file() else ""
    ren = RENDERER.read_text(encoding="utf-8") if RENDERER.is_file() else ""
    if "func _draw" in lyr and "ColorRect" not in lyr and "Control" not in lyr:
        passes.append("layer_draw_no_control")
    else:
        fails.append("layer_draw_no_control")
    if "max_tokens" in lyr and "MAX_TOKENS" in lyr:
        passes.append("layer_cap")
    else:
        fails.append("layer_cap")
    if "set_process(true)" not in lyr:
        passes.append("layer_no_pulse")
    else:
        fails.append("layer_no_pulse")
    if "game_day_advanced" in lyr and "get_agents_for_country" in lyr:
        passes.append("layer_day_roster")
    else:
        fails.append("layer_day_roster")
    if "on_mission" in lyr and "current_mission_id" in lyr:
        passes.append("on_mission_only")
    else:
        fails.append("on_mission_only")
    if "_setup_agent_presence_layer" in ren and "AgentPresenceLayer" in ren:
        passes.append("renderer_wires_layer")
    else:
        fails.append("renderer_wires_layer")
    if "show_agent_overlay: bool = false" in ren:
        passes.append("network_overlay_stays_off")
    else:
        fails.append("network_overlay_stays_off")
    sample = agent_presence_marker(pid=710707, on_mission=True, player=True)
    idle = agent_presence_marker(pid=710707, on_mission=False, player=True)
    if sample.get("ok") and not idle.get("ok"):
        passes.append("idle_hidden")
    else:
        fails.append("idle_hidden")
    capped = cap_agent_tokens(
        [{"pid": 710000 + i, "on_mission": True} for i in range(20)],
        max_n=MAX_TOKENS,
    )
    if len(capped) == MAX_TOKENS:
        passes.append("cap_eight")
    else:
        fails.append("cap_eight")
    ok = len(fails) == 0
    return {
        "ok": ok,
        "empty": False,
        "pass": passes,
        "fail": fails,
        "network_mentions_pulse": "set_process(true)" in net,
        "summary": "agent_presence · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
    }


def build_map_agent_presence_product() -> Dict[str, Any]:
    g = map_agent_presence_integrity()
    g["product"] = "map_agent_presence_product"
    return g
