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


def rank_next_beat(facts: Dict[str, Any] | None = None) -> Dict[str, Any]:
    """War first, then organize-ready, dry fuel, shortage — idle unpause last."""
    f = facts if isinstance(facts, dict) else {}
    aar_pid = int(f.get("aar_next_pid", -1) or -1)
    if aar_pid > 0:
        return {
            "ok": True,
            "action": "next_hex",
            "source": "aar",
            "label": "Press the next hex",
            "fid": str(f.get("aar_fid") or ""),
            "to_id": aar_pid,
        }
    hook = str(f.get("battle_hook") or "")
    if hook or bool(f.get("has_open_battle")):
        action = recommend_from_hook(hook)
        if action == "unpause" and bool(f.get("has_open_battle")):
            action = "press"
        if action != "unpause" or bool(f.get("has_open_battle")):
            return {
                "ok": True,
                "action": action,
                "source": "land_battle",
                "label": action,
                "fid": str(f.get("battle_fid") or ""),
                "hint": hook,
            }
    for row in f.get("training") or []:
        if not isinstance(row, dict):
            continue
        try:
            left = float(row.get("days_left", 99))
        except (TypeError, ValueError):
            left = 99.0
        if left <= 1.001:
            return {
                "ok": True,
                "action": "send_trained",
                "source": "organize",
                "label": "Training ready tomorrow",
                "fid": str(row.get("fid") or ""),
                "hint": "Division ready — send to the front",
            }
    dry = f.get("dry_fuel") or []
    fuel_stock = float(f.get("fuel_stock") or 0) + float(f.get("oil_stock") or 0)
    if dry:
        first = dry[0] if isinstance(dry[0], dict) else {}
        return {
            "ok": True,
            "action": "refuel",
            "source": "fuel",
            "label": "Tanks dry" if fuel_stock <= 0.001 else "Refuel tanks",
            "fid": str(first.get("fid") or ""),
            "hint": "Empty fuel stock" if fuel_stock <= 0.001 else "National fuel can refill",
        }
    steel = f.get("steel_stock")
    try:
        steel_v = 99.0 if steel is None else float(steel)
    except (TypeError, ValueError):
        steel_v = 99.0
    if steel_v < 1.0 and bool(f.get("has_vehicle")):
        return {
            "ok": True,
            "action": "shortage",
            "source": "industry",
            "label": "Steel short — produce / develop",
            "fid": "",
            "hint": "TOE lines cannot pay steel",
        }
    if bool(f.get("paused")):
        return {
            "ok": True,
            "action": "unpause",
            "source": "clock",
            "label": "Unpause a day",
        }
    return {
        "ok": True,
        "action": "unpause",
        "source": "idle",
        "label": "One more day",
    }


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
    idle = rank_next_beat({})
    if str(idle.get("action")) == "unpause" and str(idle.get("source")) == "idle":
        passes.append("idle_last")
    else:
        fails.append("idle_last")
    train = rank_next_beat({"training": [{"fid": "u1", "days_left": 1}]})
    if str(train.get("action")) == "send_trained" and str(train.get("source")) == "organize":
        passes.append("train_beats_idle")
    else:
        fails.append("train_beats_idle")
    dry = rank_next_beat({"dry_fuel": [{"fid": "u2"}], "fuel_stock": 0, "oil_stock": 0})
    if str(dry.get("action")) == "refuel":
        passes.append("dry_fuel_beats_idle")
    else:
        fails.append("dry_fuel_beats_idle")
    short = rank_next_beat({"steel_stock": 0.0, "has_vehicle": True})
    if str(short.get("action")) == "shortage":
        passes.append("shortage_beats_idle")
    else:
        fails.append("shortage_beats_idle")
    war = rank_next_beat(
        {
            "has_open_battle": True,
            "battle_hook": "They break tomorrow — Press",
            "training": [{"fid": "u1", "days_left": 1}],
        }
    )
    if str(war.get("action")) == "press" and str(war.get("source")) == "land_battle":
        passes.append("war_beats_train")
    else:
        fails.append("war_beats_train")
    if "func _recommend_organize" in hook and "func _recommend_fuel" in hook:
        passes.append("gd_organize_fuel")
    else:
        fails.append("gd_organize_fuel")
    harness = (
        (ROOT / "scripts" / "core" / "HeadlessWorldAccurateUnitOrderLoopTest.gd").read_text(
            encoding="utf-8"
        )
        if (ROOT / "scripts" / "core" / "HeadlessWorldAccurateUnitOrderLoopTest.gd").is_file()
        else ""
    )
    if "PlayNextHook" in harness and "send_trained" in harness:
        passes.append("harness_train_next")
    else:
        fails.append("harness_train_next")
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
