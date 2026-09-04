"""OrderCommandPanel play-strip membership — player mode vs harness/debug.

Player value: Campaign Alpha strip currently mixes dual-day harness buttons with
real play actions. This pure product defines the **play** membership set and
integrity so GD can hide harness noise outside debug builds.

No dual packages. No board renumber.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence

ROOT = Path(__file__).resolve().parents[3]
ORDER_PANEL = ROOT / "scripts" / "ui" / "OrderCommandPanel.gd"
TOP_BAR = ROOT / "scripts" / "ui" / "TopInfoBar.gd"
HOOK_GD = ROOT / "scripts" / "ui" / "PlayNextHook.gd"
UNIT_CARD = ROOT / "scripts" / "ui" / "UnitCardCombatStrip.gd"

# Always-visible first-session play actions (player mode).
PLAY_ACTIONS: List[Dict[str, Any]] = [
    {
        "action_id": "apply_assault",
        "label": "Assault",
        "key": "2",
        "domain": "combat",
        "hint": "Attack adjacent enemy (or Ctrl+click on map)",
    },
    {
        "action_id": "open_living_production",
        "label": "Production",
        "key": "3",
        "domain": "industry",
        "hint": "Open living factory board for the player tag",
        "living_surface": "production",
    },
    {
        "action_id": "apply_station",
        "label": "Station forces",
        "key": "1",
        "domain": "force",
        "hint": "Station formation on selected province",
    },
    {
        "action_id": "save_resume_checkpoint",
        "label": "Checkpoint save",
        "key": "8",
        "domain": "save",
        "hint": "Or Ctrl+S quicksave",
    },
    {
        "action_id": "campaign_alpha_apply_recommended",
        "label": "Next: Press / Hold / Unpause",
        "key": "",
        "domain": "recommend",
        "hint": "War-loop next beat (PlayNextHook)",
    },
    {
        "action_id": "show_war_loop",
        "label": "WarLoop path",
        "key": "Shift+I",
        "domain": "war",
        "hint": "First-session war path (also toolbar WarLoop)",
        "map_action": "show_first_session_war_path",
    },
    {
        "action_id": "show_fronts",
        "label": "Fronts",
        "key": "B",
        "domain": "war",
        "hint": "Live border assault targets",
        "map_action": "show_live_border_fronts",
    },
    {
        "action_id": "show_corridor",
        "label": "Supply corridor",
        "key": "G",
        "domain": "logistics",
        "hint": "Hub → front corridor",
        "map_action": "highlight_corridor_capital_to_selected",
    },
]

# Harness / dual residual noise — only in debug or Extended packages.
HARNESS_ACTION_IDS: List[str] = [
    "stream_alpha_primary_packs_product",
    "campaign_alpha_primary_strip_product",
    "campaign_alpha_dead_audit",
    "campaign_alpha_recommend_next",
    "phase_approach",
    "phase_engage",
    "phase_disengage",
    "combat_ops_close",
    "hh_agenda_close",
    "naval_ops_close",
    "war_goal_board",
    "multi_front_weekly",
    "personality_drive",
    "save_browser_checkpoint",
    "save_browser_resume",
]

LIVE_PLAY_ACTION_IDS = frozenset(
    str(a["action_id"]) for a in PLAY_ACTIONS if not str(a.get("map_action") or "")
) | frozenset(
    # Map surface actions are live via MapRenderer, not apply_order_panel only
    str(a["action_id"])
    for a in PLAY_ACTIONS
)


def _gd_fn(src: str, name: str) -> str:
    needle = "func %s" % name
    i = src.find(needle)
    if i < 0:
        return ""
    n = src.find("\nfunc ", i + 1)
    return src[i:n] if n > i else src[i:]


def play_strip_actions(*, max_actions: int = 8) -> List[Dict[str, Any]]:
    limit = max(4, min(8, int(max_actions)))
    out: List[Dict[str, Any]] = []
    for i, raw in enumerate(PLAY_ACTIONS[:limit]):
        a = dict(raw)
        a["enabled"] = True
        a["index"] = i
        a["play_mode"] = True
        out.append(a)
    return out


def harness_action_ids() -> List[str]:
    return list(HARNESS_ACTION_IDS)


def is_harness_action(action_id: str) -> bool:
    return str(action_id or "").strip() in HARNESS_ACTION_IDS


def play_strip_membership_audit(
    action_ids: Optional[Sequence[str]] = None,
    *,
    harness_ids: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Player strip must not include harness dual ids."""
    ids = [str(x) for x in (action_ids if action_ids is not None else [a["action_id"] for a in PLAY_ACTIONS])]
    harness = frozenset(str(x) for x in (harness_ids if harness_ids is not None else HARNESS_ACTION_IDS))
    leaked = [a for a in ids if a in harness]
    ok = len(leaked) == 0 and len(ids) >= 4
    label = "Play strip membership · n=%d · harness_leaks=%d · %s" % (
        len(ids),
        len(leaked),
        "PASS" if ok else "FAIL",
    )
    return {
        "action_ids": ids,
        "leaked": leaked,
        "leaked_n": len(leaked),
        "ok": ok,
        "summary": label,
        "plain": label,
        "empty": False,
    }


def build_order_panel_play_strip_product(
    *,
    province_id: int = 1,
    max_actions: int = 8,
    check_wiring: bool = True,
) -> Dict[str, Any]:
    pid = max(1, int(province_id))
    actions = play_strip_actions(max_actions=max_actions)
    audit = play_strip_membership_audit([a["action_id"] for a in actions])
    fails: List[str] = []
    passes: List[str] = []
    if audit.get("ok"):
        passes.append("membership_ok")
    else:
        fails.append("membership_leak")
    if len(actions) >= 4:
        passes.append("actions_n=%d" % len(actions))
    else:
        fails.append("too_few_actions")

    # Must include assault for war loop discoverability
    aids = {str(a["action_id"]) for a in actions}
    if "apply_assault" in aids:
        passes.append("has_assault")
    else:
        fails.append("missing_assault")
    if "open_living_production" in aids:
        passes.append("has_production")
    else:
        fails.append("missing_production")
    if "apply_production" in aids:
        fails.append("play_mode_apply_production")
    else:
        passes.append("play_mode_not_apply_production")

    wiring: Dict[str, bool] = {}
    if check_wiring and ORDER_PANEL.is_file():
        src = ORDER_PANEL.read_text(encoding="utf-8")
        play_fn = _gd_fn(src, "_rebuild_play_mode_strip")
        open_fn = _gd_fn(src, "_open_play_strip_production")
        wiring["play_strip_section"] = (
            "EOA_PLAY_STRIP" in src
            or "_rebuild_play_mode_strip" in src
            or "play_strip_actions" in src
            or "order_panel_play_strip" in src
        )
        wiring["hides_harness"] = (
            "is_debug_build" in src
            and ("HARNESS" in src or "harness" in src or "stream_alpha_primary_packs" in src)
        ) or ("EOA_PLAY_STRIP" in src)
        wiring["play_mode_not_apply_production"] = (
            '_add_apply_button("[3] Production", "apply_production"' not in play_fn
            and '"apply_production"' not in play_fn
        )
        wiring["play_mode_opens_living_production"] = (
            "open_living_surface" in open_fn
            and '"production"' in open_fn
            and ("_on_production_pressed" in open_fn or "open_living_surface" in open_fn)
            and "_add_play_strip_production_button" in play_fn
        )
        for k, v in wiring.items():
            if v:
                passes.append("wire_%s" % k)
            else:
                fails.append("wire_%s" % k)
        if TOP_BAR.is_file():
            bar = TOP_BAR.read_text(encoding="utf-8")
            bar_open = _gd_fn(bar, "open_living_surface")
            if "_on_production_pressed" in bar_open and '"unpause_only": false' in bar_open:
                passes.append("top_bar_production_live")
            else:
                fails.append("top_bar_production_live")
        if HOOK_GD.is_file():
            hook = HOOK_GD.read_text(encoding="utf-8")
            if (
                'func open_living_production' in hook
                and '_open_living_surface("production"' in hook
            ):
                passes.append("hook_open_living_production")
            else:
                fails.append("hook_open_living_production")
        if UNIT_CARD.is_file():
            card = UNIT_CARD.read_text(encoding="utf-8")
            if "Fill %.0f%%" in card and "stock rifles" in card:
                passes.append("unit_card_fill_stockpile")
            else:
                fails.append("unit_card_fill_stockpile")

    ok = (
        "membership_leak" not in fails
        and "missing_assault" not in fails
        and "too_few_actions" not in fails
        and "play_mode_apply_production" not in fails
        and "wire_play_mode_not_apply_production" not in fails
        and "wire_play_mode_opens_living_production" not in fails
        and "top_bar_production_live" not in fails
        and "hook_open_living_production" not in fails
        and "unit_card_fill_stockpile" not in fails
    )
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "province_id": pid,
        "actions": actions,
        "action_n": len(actions),
        "harness_action_ids": list(HARNESS_ACTION_IDS),
        "audit": audit,
        "wiring": wiring,
        "pass": passes,
        "fail": fails,
        "summary": "Order panel play strip · n=%d · %s" % (len(actions), "PASS" if ok else "FAIL"),
        "integration": [
            "order_panel_play_strip_product",
            "OrderCommandPanel._rebuild_campaign_alpha_primary_strip",
            "OrderCommandPanel._open_play_strip_production",
            "TopInfoBar.open_living_surface",
            "first_session_assault_surface_product",
        ],
    }


def order_panel_play_strip_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_order_panel_play_strip_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
