"""Play-strip / map chip: one recommended next beat (war loop first)."""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional

from era_resource_deposits_product import occupation_harvest_mult, scale_deposits_for_year

ROOT = Path(__file__).resolve().parents[3]
HOOK_GD = ROOT / "scripts" / "ui" / "PlayNextHook.gd"
PANEL_GD = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
REN_GD = ROOT / "scripts" / "map" / "MapRenderer.gd"
AAR_GD = ROOT / "scripts" / "combat" / "LandBattleAar.gd"
BM_GD = ROOT / "scripts" / "combat" / "BattleManager.gd"
TM_GD = ROOT / "scripts" / "technology" / "TechnologyManager.gd"
RHC_GD = ROOT / "scripts" / "production" / "ResourceHarvestCalculator.gd"
HARNESS_GD = ROOT / "scripts" / "core" / "HeadlessWorldAccurateUnitOrderLoopTest.gd"

AAR_CAPTURE_GOODS = ("oil", "steel", "coal")
AAR_GOOD_VERBS = {"oil": "pumping", "steel": "mining", "coal": "mining"}


def capture_economy_sentence(
    resources: Optional[Mapping[str, Any]] = None,
    year: int = 1936,
    owner: str = "",
    controller: str = "",
) -> str:
    """Era-visible oil/steel/coal on the captured hex. Occupied uses harvest ×0.65."""
    scaled = scale_deposits_for_year(resources or {}, int(year))
    best = ""
    best_amt = 0.0
    for key in AAR_CAPTURE_GOODS:
        try:
            amt = float(scaled.get(key) or 0.0)
        except (TypeError, ValueError):
            amt = 0.0
        if amt > best_amt:
            best = key
            best_amt = amt
    if not best:
        return ""
    verb = AAR_GOOD_VERBS.get(best, "taking")
    occ = float(occupation_harvest_mult(owner, controller))
    if occ < 0.999:
        return "Now %s %s (occupied ×%.2f)." % (verb, best, occ)
    return "Now %s %s." % (verb, best)


def recommend_from_hook(hint: str) -> str:
    low = str(hint or "").lower()
    if "arrives tomorrow" in low:
        return "hold"
    if "break tomorrow" in low or "one day from breaking" in low:
        return "press"
    if "river/fort" in low:
        return "hold"
    return "unpause"


def _optional_days(f: Mapping[str, Any], key: str) -> float:
    if key not in f or f[key] is None or f[key] == "":
        return 99.0
    try:
        return float(f[key])
    except (TypeError, ValueError):
        return 99.0


def rank_next_beat(facts: Dict[str, Any] | None = None) -> Dict[str, Any]:
    """War first, then organize-ready, dry fuel, shortage, completing bars — idle last."""
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
            "hint": str(f.get("aar_line") or ""),
        }
    eco = str(f.get("aar_economy") or "").strip()
    if eco:
        return {
            "ok": True,
            "action": "unpause",
            "source": "aar",
            "label": eco.rstrip("."),
            "fid": str(f.get("aar_fid") or ""),
            "hint": str(f.get("aar_line") or eco),
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
    rleft = _optional_days(f, "research_days_left")
    if rleft <= 1.001:
        rname = str(f.get("research_name") or "").strip()
        return {
            "ok": True,
            "action": "tech_done",
            "source": "research",
            "label": "Research completes tomorrow",
            "fid": str(f.get("research_id") or ""),
            "hint": rname or "Research completes tomorrow",
        }
    fleft = _optional_days(f, "focus_days_left")
    if fleft <= 1.001:
        fname = str(f.get("focus_name") or f.get("focus_id") or "").strip()
        return {
            "ok": True,
            "action": "focus_done",
            "source": "focus",
            "label": "Focus completes tomorrow",
            "fid": str(f.get("focus_id") or ""),
            "hint": fname or "Focus completes tomorrow",
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
    if "func rank_from_snapshot" in hook:
        passes.append("gd_rank_from_snapshot")
    else:
        fails.append("gd_rank_from_snapshot")
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
    occ_oil = capture_economy_sentence({"oil": 3.0}, 1936, "FRA", "GER")
    if "oil" in occ_oil.lower() and "0.65" in occ_oil and "pumping" in occ_oil:
        passes.append("occupy_oil_sentence")
    else:
        fails.append("occupy_oil_sentence")
    own_steel = capture_economy_sentence({"steel": 2.0}, 1936, "GER", "GER")
    if "steel" in own_steel.lower() and "0.65" not in own_steel:
        passes.append("own_steel_no_occ")
    else:
        fails.append("own_steel_no_occ")
    eco_beat = rank_next_beat(
        {
            "aar_economy": "Now pumping oil (occupied ×0.65).",
            "training": [{"fid": "u1", "days_left": 1}],
        }
    )
    if str(eco_beat.get("source")) == "aar" and "oil" in str(eco_beat.get("label", "")).lower():
        passes.append("aar_economy_beats_train")
    else:
        fails.append("aar_economy_beats_train")
    war_next = rank_next_beat(
        {
            "aar_next_pid": 710000,
            "aar_economy": "Now pumping oil (occupied ×0.65).",
            "aar_line": (
                "Took Bas-Rhin · 1 day — Press Haguenau next? "
                "Now pumping oil (occupied ×0.65)."
            ),
        }
    )
    if str(war_next.get("action")) == "next_hex" and str(war_next.get("source")) == "aar":
        passes.append("next_hex_beats_economy")
    else:
        fails.append("next_hex_beats_economy")
    aar_gd = AAR_GD.read_text(encoding="utf-8") if AAR_GD.is_file() else ""
    bm_gd = BM_GD.read_text(encoding="utf-8") if BM_GD.is_file() else ""
    if "func economy_sentence" in aar_gd and "scale_deposits_for_year" in aar_gd:
        passes.append("gd_aar_economy")
    else:
        fails.append("gd_aar_economy")
    if "economy_sentence" in bm_gd and "economy" in bm_gd:
        passes.append("bm_appends_economy")
    else:
        fails.append("bm_appends_economy")
    if 'aar.get("economy"' in hook:
        passes.append("hook_reads_economy")
    else:
        fails.append("hook_reads_economy")
    harness = HARNESS_GD.read_text(encoding="utf-8") if HARNESS_GD.is_file() else ""
    if "PlayNextHook" in harness and "send_trained" in harness:
        passes.append("harness_train_next")
    else:
        fails.append("harness_train_next")
    if "economy_sentence" in harness and ("pump" in harness or "oil" in harness):
        passes.append("harness_capture_economy")
    else:
        fails.append("harness_capture_economy")
    research = rank_next_beat({"research_days_left": 1})
    if str(research.get("action")) == "tech_done" and str(research.get("source")) == "research":
        passes.append("research_beats_idle")
    else:
        fails.append("research_beats_idle")
    focus = rank_next_beat({"focus_days_left": 1})
    if str(focus.get("action")) == "focus_done" and str(focus.get("source")) == "focus":
        passes.append("focus_beats_idle")
    else:
        fails.append("focus_beats_idle")
    far = rank_next_beat({"research_days_left": 5, "focus_days_left": 12})
    if str(far.get("source")) == "idle":
        passes.append("far_research_stays_idle")
    else:
        fails.append("far_research_stays_idle")
    war_bars = rank_next_beat(
        {
            "has_open_battle": True,
            "battle_hook": "They break tomorrow — Press",
            "research_days_left": 1,
            "focus_days_left": 1,
        }
    )
    if str(war_bars.get("action")) == "press" and str(war_bars.get("source")) == "land_battle":
        passes.append("war_beats_completing")
    else:
        fails.append("war_beats_completing")
    short_bars = rank_next_beat(
        {"steel_stock": 0.0, "has_vehicle": True, "research_days_left": 1, "focus_days_left": 1}
    )
    if str(short_bars.get("action")) == "shortage":
        passes.append("shortage_beats_research")
    else:
        fails.append("shortage_beats_research")
    train_bars = rank_next_beat(
        {"training": [{"fid": "u1", "days_left": 1}], "research_days_left": 1}
    )
    if str(train_bars.get("action")) == "send_trained":
        passes.append("train_beats_research")
    else:
        fails.append("train_beats_research")
    fuel_bars = rank_next_beat(
        {
            "dry_fuel": [{"fid": "u2"}],
            "fuel_stock": 0,
            "oil_stock": 0,
            "research_days_left": 1,
        }
    )
    if str(fuel_bars.get("action")) == "refuel":
        passes.append("fuel_beats_research")
    else:
        fails.append("fuel_beats_research")
    if "tech_done" in hook and "focus_done" in hook:
        passes.append("gd_completing_actions")
    else:
        fails.append("gd_completing_actions")
    tm = TM_GD.read_text(encoding="utf-8") if TM_GD.is_file() else ""
    if "func completing_snapshot" in tm:
        passes.append("tm_completing_snapshot")
    else:
        fails.append("tm_completing_snapshot")
    rhc = RHC_GD.read_text(encoding="utf-8") if RHC_GD.is_file() else ""
    if "DEVELOP_COMPLETES_INSTANT" in rhc and "func develop_days_remaining" in rhc:
        passes.append("develop_instant")
    else:
        fails.append("develop_instant")
    if "rank_from_snapshot" in harness and "tech_done" in harness:
        passes.append("harness_completing")
    else:
        fails.append("harness_completing")
    if (
        '"dry_fuel"' in harness
        and "send_trained" in harness
        and "shortage" in harness
        and "research_days_left" in harness
    ):
        passes.append("harness_higher_beats_completing")
    else:
        fails.append("harness_higher_beats_completing")
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
