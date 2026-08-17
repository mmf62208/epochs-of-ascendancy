"""Play-strip / map chip: one recommended next beat (war loop first)."""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[3]
HOOK_GD = ROOT / "scripts" / "ui" / "PlayNextHook.gd"
PANEL_GD = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
REN_GD = ROOT / "scripts" / "map" / "MapRenderer.gd"


def recommend_from_hook(hint: str) -> str:
    low = str(hint or "").lower()
    if "arrives tomorrow" in low:
        return "hold"
    if "break tomorrow" in low or "one day from breaking" in low:
        return "press"
    if "river/fort" in low:
        return "hold"
    return "unpause"


def build_play_next_hook_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    if recommend_from_hook("Reinforcement arrives tomorrow — Hold") == "hold":
        passes.append("arrive_means_hold")
    else:
        fails.append("arrive_means_hold")
    if recommend_from_hook("They break tomorrow — Press") == "press":
        passes.append("break_means_press")
    else:
        fails.append("break_means_press")
    hook = HOOK_GD.read_text(encoding="utf-8") if HOOK_GD.is_file() else ""
    panel = PANEL_GD.read_text(encoding="utf-8") if PANEL_GD.is_file() else ""
    ren = REN_GD.read_text(encoding="utf-8") if REN_GD.is_file() else ""
    if "func recommend" in hook and "func apply" in hook:
        passes.append("hook_api")
    else:
        fails.append("hook_api")
    if "PlayNextHook" in panel and "Next:" in panel:
        passes.append("panel_shows_next")
    else:
        fails.append("panel_shows_next")
    if "PlayNextHook" in ren and "_refresh_next_hook_chip" in ren:
        passes.append("map_next_chip")
    else:
        fails.append("map_next_chip")
    ok = len(fails) == 0
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "summary": "play_next_hook · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "one_visible_next_beat_war_loop_first",
    }
