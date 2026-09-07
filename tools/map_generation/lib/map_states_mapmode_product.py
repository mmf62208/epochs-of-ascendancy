"""M2 — states mapmode tint helper (pure).

Deterministic color from state_id so neighboring states read as distinct
Victoria-style state fills. Sea → deep blue; unassigned land → dim slate.
"""
from __future__ import annotations

import math
from typing import Any, Dict, Mapping, Optional, Sequence, Tuple

SEA = (0.08, 0.14, 0.28)
EMPTY = (0.16, 0.17, 0.20)
GOLDEN = 0.618033988749895


def _clamp01(x: float) -> float:
    return max(0.0, min(1.0, float(x)))


def _hsv_to_rgb(h: float, s: float, v: float) -> Tuple[float, float, float]:
    """h in [0,1), s/v in [0,1]."""
    h = h % 1.0
    i = int(h * 6.0)
    f = h * 6.0 - i
    p = v * (1.0 - s)
    q = v * (1.0 - f * s)
    t = v * (1.0 - (1.0 - f) * s)
    i = i % 6
    if i == 0:
        r, g, b = v, t, p
    elif i == 1:
        r, g, b = q, v, p
    elif i == 2:
        r, g, b = p, v, t
    elif i == 3:
        r, g, b = p, q, v
    elif i == 4:
        r, g, b = t, p, v
    else:
        r, g, b = v, p, q
    return (_clamp01(r), _clamp01(g), _clamp01(b))


def states_mapmode_rgb(
    state_id: int = 0,
    *,
    is_sea: bool = False,
    base_rgb: Optional[Sequence[float]] = None,
) -> Tuple[float, float, float]:
    """RGB for state mapmode. Distinct hues by state_id (golden-angle)."""
    if is_sea:
        return SEA
    sid = int(state_id or 0)
    if sid <= 0:
        return EMPTY
    # Spread hues; slight value variation by id
    h = (sid * GOLDEN) % 1.0
    s = 0.42 + 0.18 * ((sid * 7) % 5) / 4.0
    v = 0.55 + 0.20 * ((sid * 3) % 4) / 3.0
    r, g, b = _hsv_to_rgb(h, s, v)
    if base_rgb is not None and len(base_rgb) >= 3:
        # 20% political blend for owner readability
        r = r * 0.80 + float(base_rgb[0]) * 0.20
        g = g * 0.80 + float(base_rgb[1]) * 0.20
        b = b * 0.80 + float(base_rgb[2]) * 0.20
    return (_clamp01(r), _clamp01(g), _clamp01(b))


def terrain_mapmode_rgb(
    terrain: str = "plains",
    *,
    is_sea: bool = False,
) -> Tuple[float, float, float]:
    """RGB for clean terrain mapmode (HOI-style terrain view)."""
    if is_sea:
        return SEA
    key = str(terrain or "plains").strip().lower()
    palette = {
        "plains": (0.55, 0.68, 0.38),
        "grassland": (0.55, 0.68, 0.38),
        "forest": (0.18, 0.42, 0.22),
        "woods": (0.22, 0.48, 0.26),
        "jungle": (0.12, 0.38, 0.20),
        "mountains": (0.48, 0.45, 0.42),
        "hills": (0.52, 0.50, 0.36),
        "desert": (0.78, 0.68, 0.42),
        "tundra": (0.62, 0.68, 0.70),
        "marsh": (0.32, 0.42, 0.30),
        "urban": (0.45, 0.45, 0.48),
        "sea": SEA,
        "ocean": SEA,
        "water": SEA,
        "lake": (0.15, 0.28, 0.40),
    }
    return palette.get(key, (0.50, 0.52, 0.40))


def build_states_mapmode_product(
    samples: Optional[Sequence[Mapping[str, Any]]] = None,
) -> Dict[str, Any]:
    fails = []
    passes = []
    a = states_mapmode_rgb(1)
    b = states_mapmode_rgb(2)
    empty = states_mapmode_rgb(0)
    sea = states_mapmode_rgb(0, is_sea=True)
    if a == b:
        fails.append("state1_eq_state2")
    else:
        passes.append("states_distinct")
    if a == empty:
        fails.append("state_eq_empty")
    else:
        passes.append("state_ne_empty")
    if sea[2] > sea[0]:
        passes.append("sea_blue")
    else:
        fails.append("sea_not_blue")
    # Terrain product slice
    plains = terrain_mapmode_rgb("plains")
    mtn = terrain_mapmode_rgb("mountains")
    if plains == mtn:
        fails.append("plains_eq_mtn")
    else:
        passes.append("terrain_distinct")
    sample_rows = []
    for s in samples or []:
        if not isinstance(s, Mapping):
            continue
        sid = int(s.get("state_id") or 0)
        rgb = states_mapmode_rgb(sid, is_sea=bool(s.get("is_sea", False)))
        sample_rows.append({"id": s.get("id"), "state_id": sid, "rgb": rgb})
    ok = len(fails) == 0
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "state1_rgb": a,
        "state2_rgb": b,
        "empty_rgb": empty,
        "sea_rgb": sea,
        "plains_rgb": plains,
        "mountains_rgb": mtn,
        "samples": sample_rows,
        "pass": passes,
        "fail": fails,
        "summary": "States/terrain mapmode tint %s" % ("PASS" if ok else "FAIL"),
        "integration": ["map_states_mapmode_product", "m2", "m3", "states", "terrain"],
    }


def states_mapmode_integrity_from_board(board_dir: str = "") -> Dict[str, Any]:
    """Drive real membership state ids from accurate board."""
    import json
    from pathlib import Path

    root = Path(__file__).resolve().parents[3]
    d = Path(board_dir) if board_dir else root / "data" / "provinces_world_accurate"
    mem = json.loads((d / "hierarchy_membership_1936.json").read_text(encoding="utf-8"))
    p2s = mem.get("province_to_state") or {}
    # two different states
    sids = []
    samples = []
    for pid_s, sid in p2s.items():
        si = int(sid or 0)
        if si <= 0:
            continue
        if si not in sids:
            sids.append(si)
            samples.append({"id": int(pid_s), "state_id": si, "is_sea": False})
        if len(sids) >= 3:
            break
    prod = build_states_mapmode_product(samples)
    if len(sids) >= 2:
        c0 = states_mapmode_rgb(sids[0])
        c1 = states_mapmode_rgb(sids[1])
        if c0 == c1:
            prod["ok"] = False
            prod["fail"] = list(prod.get("fail") or []) + ["board_states_same_color"]
        else:
            prod["pass"] = list(prod.get("pass") or []) + ["board_states_distinct"]
    prod["board"] = str(d)
    prod["sample_state_ids"] = sids
    return prod


def states_terrain_hotkey_integrity() -> Dict[str, Any]:
    """F1–F4 / F9 / Shift+F9 / Ctrl+F9 must call live set_map_mode from _input; toolbar follows."""
    from pathlib import Path

    root = Path(__file__).resolve().parents[3]
    ren_path = root / "scripts" / "map" / "MapRenderer.gd"
    tb_path = root / "scripts" / "ui" / "map" / "MapModeToolbar.gd"
    ren = ren_path.read_text(encoding="utf-8") if ren_path.is_file() else ""
    tb = tb_path.read_text(encoding="utf-8") if tb_path.is_file() else ""
    input_i = ren.find("func _input")
    unh_i = ren.find("func _unhandled_input")
    input_fn = ren[input_i:unh_i] if input_i >= 0 and unh_i > input_i else ""
    fails: list = []
    passes: list = []
    for mode, needle in (
        ("political", 'set_map_mode("political")'),
        ("strain", 'set_map_mode("strain")'),
        ("vitality", 'set_map_mode("vitality")'),
        ("development", 'set_map_mode("development")'),
        ("resources", 'set_map_mode("resources")'),
        ("states", 'set_map_mode("states")'),
        ("terrain", 'set_map_mode("terrain")'),
    ):
        if needle in input_fn:
            passes.append("input_%s" % mode)
        else:
            fails.append("missing_input_%s" % mode)
    if "KEY_F9" in input_fn and "event.ctrl_pressed" in input_fn and 'set_map_mode("terrain")' in input_fn:
        passes.append("ctrl_f9_terrain_in_input")
    else:
        fails.append("ctrl_f9_terrain_not_in_input")
    set_fn_i = ren.find("func set_map_mode")
    set_fn = ren[set_fn_i : set_fn_i + 2500] if set_fn_i >= 0 else ""
    if "_sync_mapmode_toolbar" in set_fn:
        passes.append("set_map_mode_syncs_toolbar")
    else:
        fails.append("set_map_mode_no_toolbar_sync")
    if "func set_mode" in tb and "notify_renderer" in tb and "false" in tb:
        passes.append("toolbar_set_mode_notify_false")
    else:
        fails.append("toolbar_set_mode_missing")
    ok = len(fails) == 0
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "summary": "states/terrain F-key path %s" % ("PASS" if ok else "FAIL"),
    }
