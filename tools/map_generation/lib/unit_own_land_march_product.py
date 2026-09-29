"""Own-land march rules SOT — hop days, path ETA, calendar, legality.

Synthetic graph only. Godot reimplements later; do not invent exclave stories.
Offline product for the L1 war-loop march slice.
"""
from __future__ import annotations

import math
from typing import Any, Dict, List, Mapping
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FORMATION_MOVEMENT = ROOT / "scripts" / "formations" / "FormationMovement.gd"
TIME_MANAGER = ROOT / "scripts" / "autoload" / "TimeManager.gd"
MAP_RENDERER = ROOT / "scripts" / "map" / "MapRenderer.gd"

# Base hop at plains / infantry / high infra.
BASE_HOP_DAYS = 1.0
HOP_DAYS_MIN = 0.25
HOP_DAYS_MAX = 3.0

# Typical own-land rail/road used by fixtures (high infra → faster).
FIXTURE_INFRA = 1.0
INFANTRY_SPEED = 1.0
ARMOR_SPEED = 1.5

# Terrain day costs (1.0 = plains baseline). Higher = slower.
TERRAIN_COST: Dict[str, float] = {
    "plains": 1.0,
    "hills": 1.20,
    "forest": 1.25,
    "desert": 1.30,
    "urban": 1.15,
    "jungle": 1.50,
    "marsh": 1.60,
    "mountain": 1.80,
}

MOUNTAIN_INFANTRY_DISCOUNT = 0.70
ARMOR_MOUNTAIN_PENALTY = 1.60

_ARMOR_MOTOR_TOKENS = ("armor", "armour", "motor", "mech")


def _clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def _kind(template_kind: str) -> str:
    return str(template_kind or "infantry").strip().lower()


def _is_mountain_infantry(kind: str) -> bool:
    return "mountain" in kind


def _is_armor_motor(kind: str) -> bool:
    return any(tok in kind for tok in _ARMOR_MOTOR_TOKENS)


def _terrain_cost(terrain: str) -> float:
    key = str(terrain or "plains").strip().lower() or "plains"
    return float(TERRAIN_COST.get(key, TERRAIN_COST["plains"]))


def _infra_cost(infra: float) -> float:
    """infra 0.0–1.0; high infra faster. 1.0 → 1.0×, 0.0 → 1.5×."""
    x = _clamp(float(infra), 0.0, 1.0)
    return 1.5 - 0.5 * x


def _speed_cost(template_speed: float) -> float:
    """template_speed 1.0 = infantry; >1.0 armor/motor → fewer days."""
    spd = float(template_speed)
    if spd <= 1e-9:
        return HOP_DAYS_MAX / BASE_HOP_DAYS
    return 1.0 / spd


def hop_days(
    *,
    terrain: str,
    infra: float,
    template_speed: float,
    template_kind: str = "infantry",
) -> float:
    """Base 1.0 day/hop * speed * terrain * infra. Clamp [0.25, 3.0]."""
    kind = _kind(template_kind)
    terr = str(terrain or "plains").strip().lower() or "plains"
    days = BASE_HOP_DAYS * _terrain_cost(terr) * _infra_cost(infra) * _speed_cost(
        template_speed
    )
    if terr == "mountain" and _is_mountain_infantry(kind):
        days *= MOUNTAIN_INFANTRY_DISCOUNT
    if terr == "mountain" and _is_armor_motor(kind):
        days *= ARMOR_MOUNTAIN_PENALTY
    return _clamp(float(days), HOP_DAYS_MIN, HOP_DAYS_MAX)


def path_eta_days(hops: List[Dict[str, Any]]) -> float:
    """Sum hop_days for each hop dict with terrain, infra, template_speed, template_kind."""
    total = 0.0
    for hop in hops or []:
        if not isinstance(hop, Mapping):
            continue
        total += hop_days(
            terrain=str(hop.get("terrain", "plains")),
            infra=float(hop.get("infra", FIXTURE_INFRA)),
            template_speed=float(hop.get("template_speed", INFANTRY_SPEED)),
            template_kind=str(hop.get("template_kind", "infantry")),
        )
    return float(total)


def calendar_days(eta: float) -> int:
    """Round up to whole days, min 1 if eta > 0."""
    x = float(eta)
    if x <= 0.0:
        return 0
    return max(1, int(math.ceil(x - 1e-9)))


def march_legal(*, dest_owner: str, player_tag: str, dest_is_land: bool) -> bool:
    """True only if dest_is_land and dest_owner == player_tag (own/controlled)."""
    if not dest_is_land:
        return False
    owner = str(dest_owner or "").strip().upper()
    tag = str(player_tag or "").strip().upper()
    return bool(owner) and owner == tag


def _hop(
    terrain: str,
    *,
    infra: float = FIXTURE_INFRA,
    template_speed: float = INFANTRY_SPEED,
    template_kind: str = "infantry",
) -> Dict[str, Any]:
    return {
        "terrain": terrain,
        "infra": infra,
        "template_speed": template_speed,
        "template_kind": template_kind,
    }


def build_unit_own_land_march_product() -> Dict[str, Any]:
    """Run synthetic own-land march fixtures. ok iff all pass."""
    passes: List[str] = []
    fails: List[str] = []

    plains_inf = hop_days(
        terrain="plains",
        infra=FIXTURE_INFRA,
        template_speed=INFANTRY_SPEED,
        template_kind="infantry",
    )
    plains_cal = calendar_days(plains_inf)
    if plains_cal == 1:
        passes.append("adjacent_plains_infantry_1d")
    else:
        fails.append("adjacent_plains_infantry_1d")

    three = [_hop("plains") for _ in range(3)]
    three_eta = path_eta_days(three)
    three_cal = calendar_days(three_eta)
    if three_eta > 1.0 and three_cal >= 3:
        passes.append("three_hop_plains_multi_day")
    else:
        fails.append("three_hop_plains_multi_day")

    mtn_inf = hop_days(
        terrain="mountain",
        infra=FIXTURE_INFRA,
        template_speed=INFANTRY_SPEED,
        template_kind="infantry",
    )
    if mtn_inf > plains_inf:
        passes.append("mountain_slower_than_plains")
    else:
        fails.append("mountain_slower_than_plains")

    plains_arm = hop_days(
        terrain="plains",
        infra=FIXTURE_INFRA,
        template_speed=ARMOR_SPEED,
        template_kind="armor",
    )
    if plains_arm < plains_inf:
        passes.append("armor_faster_plains")
    else:
        fails.append("armor_faster_plains")

    mtn_arm = hop_days(
        terrain="mountain",
        infra=FIXTURE_INFRA,
        template_speed=ARMOR_SPEED,
        template_kind="armor",
    )
    if mtn_arm >= mtn_inf:
        passes.append("armor_not_faster_mountain")
    else:
        fails.append("armor_not_faster_mountain")

    enemy_ok = march_legal(dest_owner="FRA", player_tag="GER", dest_is_land=True)
    sea_ok = march_legal(dest_owner="GER", player_tag="GER", dest_is_land=False)
    own_ok = march_legal(dest_owner="GER", player_tag="GER", dest_is_land=True)
    if (not enemy_ok) and (not sea_ok) and own_ok:
        passes.append("enemy_dest_rejected")
    else:
        fails.append("enemy_dest_rejected")

    fm = FORMATION_MOVEMENT.read_text(encoding="utf-8") if FORMATION_MOVEMENT.is_file() else ""
    tm = TIME_MANAGER.read_text(encoding="utf-8") if TIME_MANAGER.is_file() else ""
    ren = MAP_RENDERER.read_text(encoding="utf-8") if MAP_RENDERER.is_file() else ""
    if "func enqueue_own_land_march" in fm and "func tick_all_marches" in fm:
        passes.append("movement_queue_api")
    else:
        fails.append("movement_queue_api")
    if "func preview_own_land_march" in fm:
        passes.append("preview_api")
    else:
        fails.append("preview_api")
    prev_fn = ""
    _pi = fm.find("func preview_own_land_march")
    if _pi >= 0:
        _plines = fm[_pi:].splitlines()
        _pout = [_plines[0]]
        for _ln in _plines[1:]:
            if _ln.startswith("func ") or _ln.startswith("static func "):
                break
            _pout.append(_ln)
        prev_fn = "\n".join(_pout)
    if prev_fn and "_orders[" not in prev_fn and "_orders." not in prev_fn:
        passes.append("preview_writes_nothing")
    else:
        fails.append("preview_writes_nothing")
    enq_fn = ""
    _ei = fm.find("func enqueue_own_land_march")
    if _ei >= 0:
        _elines = fm[_ei:].splitlines()
        _eout = [_elines[0]]
        for _ln in _elines[1:]:
            if _ln.startswith("func ") or _ln.startswith("static func "):
                break
            _eout.append(_ln)
        enq_fn = "\n".join(_eout)
    if "preview_own_land_march" in enq_fn and "_orders[fid]" in enq_fn:
        passes.append("enqueue_uses_preview")
    else:
        fails.append("enqueue_uses_preview")
    if "_tick_own_land_marches" in tm and "tick_all_marches" in tm:
        passes.append("time_manager_day_tick")
    else:
        fails.append("time_manager_day_tick")
    move_fn = ""
    _i = ren.find("func _try_move_selected_unit_to_province")
    if _i >= 0:
        _lines = ren[_i:].splitlines()
        _out = [_lines[0]]
        for _ln in _lines[1:]:
            if _ln.startswith("func "):
                break
            _out.append(_ln)
        move_fn = "\n".join(_out)
    if "enqueue_own_land_march" in move_fn and "move_formation_to_province" not in move_fn:
        passes.append("renderer_enqueues_not_teleports")
    else:
        fails.append("renderer_enqueues_not_teleports")
    if "MarchPreviewLine" in ren and "_refresh_march_preview_for_hover" in ren:
        passes.append("renderer_hover_preview")
    else:
        fails.append("renderer_hover_preview")
    hover_fn = ""
    _hi = ren.find("func _refresh_hover_tooltip")
    if _hi >= 0:
        _hlines = ren[_hi:].splitlines()
        _hout = [_hlines[0]]
        for _ln in _hlines[1:]:
            if _ln.startswith("func "):
                break
            _hout.append(_ln)
        hover_fn = "\n".join(_hout)
    if (
        hover_fn
        and "preview_own_land_march" not in hover_fn
        and "_refresh_march_preview_for_hover" not in hover_fn
    ):
        passes.append("hover_tooltip_no_bfs")
    else:
        fails.append("hover_tooltip_no_bfs")
    spatial_fn = ""
    _si = ren.find("func _update_spatial_hover")
    if _si >= 0:
        _slines = ren[_si:].splitlines()
        _sout = [_slines[0]]
        for _ln in _slines[1:]:
            if _ln.startswith("func "):
                break
            _sout.append(_ln)
        spatial_fn = "\n".join(_sout)
    if (
        spatial_fn
        and "_unit_detail_popup_is_visible() or _is_mouse_over_blocking_ui()" not in spatial_fn
        and "_refresh_march_preview_for_hover" in spatial_fn
        and "_clear_left_slop_after_still_click" in ren
    ):
        passes.append("card_up_hover_preview")
    else:
        fails.append("card_up_hover_preview")

    ok = len(fails) == 0
    fixtures: Dict[str, Any] = {
        "adjacent_plains_infantry": {
            "hop_days": plains_inf,
            "calendar_days": plains_cal,
        },
        "three_hop_plains_infantry": {
            "eta": three_eta,
            "calendar_days": three_cal,
        },
        "mountain_vs_plains_infantry": {
            "plains": plains_inf,
            "mountain": mtn_inf,
        },
        "armor_vs_infantry_plains": {
            "infantry": plains_inf,
            "armor": plains_arm,
        },
        "armor_vs_infantry_mountain": {
            "infantry": mtn_inf,
            "armor": mtn_arm,
        },
        "march_legal": {
            "own_land": own_ok,
            "enemy_land": enemy_ok,
            "own_sea": sea_ok,
        },
    }
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "fixtures": fixtures,
        "summary": "unit_own_land_march · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "own_land_only_hop_days_clamp_0.25_3.0_calendar_ceil",
        "integration": [
            "unit_own_land_march_product",
            "unit_centric_pick_product",
        ],
    }


def unit_own_land_march_integrity() -> Dict[str, Any]:
    p = build_unit_own_land_march_product()
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
