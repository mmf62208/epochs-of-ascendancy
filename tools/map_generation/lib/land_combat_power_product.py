"""Fielded-template land combat power SOT — infantry ≠ armor.

Offline product for CombatLoop. Godot helper: scripts/combat/LandCombatPower.gd
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional

ROOT = Path(__file__).resolve().parents[3]
LAND_COMBAT_POWER_GD = ROOT / "scripts" / "combat" / "LandCombatPower.gd"

INFANTRY_SPEED = 1.0
ARMOR_SPEED = 1.5
BASE_POWER = 100.0
ARMOR_PLAINS_HILLS = 1.5
ARMOR_MOUNTAIN = 0.85
MOUNTAIN_INFANTRY_MOUNTAIN = 1.15
READINESS_MIN = 0.3
READINESS_MAX = 1.2

_ARMOR_TOKENS = ("armor", "armour", "panzer", "tank")
_MOUNTAIN_TOKENS = ("mountain", "gebirg")

_GD_FUNCS = ("template_kind", "template_speed", "combat_power")


def _clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def _as_map(formation: Any) -> Optional[Mapping[str, Any]]:
    if formation is None:
        return None
    if isinstance(formation, Mapping):
        return formation
    return None


def _blob(formation: Mapping[str, Any]) -> str:
    parts = [
        str(formation.get("design_id") or ""),
        str(formation.get("name") or ""),
        str(formation.get("formation_type") or ""),
        str(formation.get("formation_id") or ""),
        str(formation.get("template_kind") or ""),
    ]
    return " ".join(parts).lower()


def _norm_terrain(terrain: str) -> str:
    key = str(terrain or "plains").strip().lower() or "plains"
    if key in ("mountain", "mountains", "alpine", "snow_capped"):
        return "mountain"
    if key in ("hills", "hill", "highland"):
        return "hills"
    return key


def template_kind(formation: Any) -> str:
    data = _as_map(formation)
    if data is None:
        return "infantry"
    explicit = str(data.get("template_kind") or "").strip().lower()
    if explicit in ("infantry", "armor", "mountain_infantry"):
        return explicit
    blob = _blob(data)
    kind = "infantry"
    if any(tok in blob for tok in _MOUNTAIN_TOKENS):
        kind = "mountain_infantry"
    if any(tok in blob for tok in _ARMOR_TOKENS):
        kind = "armor"
    return kind


def template_speed(formation: Any) -> float:
    if template_kind(formation) == "armor":
        return ARMOR_SPEED
    return INFANTRY_SPEED


def _read_f(data: Mapping[str, Any], keys: List[str], default: float) -> float:
    for k in keys:
        if k in data and data.get(k) is not None:
            try:
                return float(data.get(k))
            except (TypeError, ValueError):
                continue
    return default


def _soft_attack(data: Mapping[str, Any]) -> Optional[float]:
    raw = data.get("soft_attack")
    if raw is None:
        stats = data.get("template")
        if isinstance(stats, Mapping) and "soft_attack" in stats:
            raw = stats.get("soft_attack")
    if raw is None:
        return None
    try:
        return float(raw)
    except (TypeError, ValueError):
        return None


def combat_power(formation: Any, terrain: str = "plains") -> float:
    data = _as_map(formation)
    if data is None:
        return 0.0
    org = _read_f(data, ["organization", "org"], 1.0)
    strength = _read_f(data, ["strength"], 1.0)
    readiness = _clamp(_read_f(data, ["readiness"], 1.0), READINESS_MIN, READINESS_MAX)
    power = BASE_POWER * org * strength * readiness
    kind = template_kind(data)
    terr = _norm_terrain(terrain)
    if kind == "armor":
        if terr in ("plains", "hills"):
            power *= ARMOR_PLAINS_HILLS
        elif terr == "mountain":
            power *= ARMOR_MOUNTAIN
    elif kind == "mountain_infantry" and terr == "mountain":
        power *= MOUNTAIN_INFANTRY_MOUNTAIN
    soft = _soft_attack(data)
    if soft is not None:
        power *= 0.7 + 0.3 * soft
    return float(power)


def _full(*, design_id: str, name: str = "", **kw: Any) -> Dict[str, Any]:
    out: Dict[str, Any] = {
        "design_id": design_id,
        "name": name or design_id,
        "organization": 1.0,
        "strength": 1.0,
        "readiness": 1.0,
    }
    out.update(kw)
    return out


def _gd_has_helpers(src: str) -> bool:
    if "class_name LandCombatPower" not in src:
        return False
    return all("static func %s" % name in src for name in _GD_FUNCS)


def build_land_combat_power_product() -> Dict[str, Any]:
    """Run infantry/armor/mountain fixtures. ok iff fixtures pass + GD helpers exist."""
    passes: List[str] = []
    fails: List[str] = []

    inf = _full(design_id="infantry_division")
    arm = _full(design_id="panzer_division", name="1st Panzer")
    mtn = _full(design_id="mountain_infantry", name="Alpine Infantry")

    inf_plains = combat_power(inf, "plains")
    arm_plains = combat_power(arm, "plains")
    if arm_plains > inf_plains:
        passes.append("armor_plains_gt_infantry_plains")
    else:
        fails.append("armor_plains_gt_infantry_plains")

    inf_mtn = combat_power(inf, "mountain")
    arm_mtn = combat_power(arm, "mountain")
    mtn_mtn = combat_power(mtn, "mountain")
    armor_not_greater = arm_mtn <= inf_mtn
    mountain_inf_higher = mtn_mtn > arm_mtn
    if armor_not_greater or mountain_inf_higher:
        passes.append("armor_mountain_not_gt_infantry_or_mtn_inf_higher")
    else:
        fails.append("armor_mountain_not_gt_infantry_or_mtn_inf_higher")

    missing = combat_power(None, "plains")
    if missing == 0.0:
        passes.append("missing_formation_zero")
    else:
        fails.append("missing_formation_zero")

    gd_src = LAND_COMBAT_POWER_GD.read_text(encoding="utf-8") if LAND_COMBAT_POWER_GD.is_file() else ""
    if _gd_has_helpers(gd_src):
        passes.append("gd_helpers")
    else:
        fails.append("gd_helpers")

    ok = len(fails) == 0
    fixtures: Dict[str, Any] = {
        "infantry_plains": inf_plains,
        "armor_plains": arm_plains,
        "infantry_mountain": inf_mtn,
        "armor_mountain": arm_mtn,
        "mountain_infantry_mountain": mtn_mtn,
        "missing": missing,
        "kinds": {
            "infantry": template_kind(inf),
            "armor": template_kind(arm),
            "mountain_infantry": template_kind(mtn),
        },
        "speeds": {
            "infantry": template_speed(inf),
            "armor": template_speed(arm),
            "mountain_infantry": template_speed(mtn),
        },
    }
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "fixtures": fixtures,
        "summary": "land_combat_power · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "base_100_org_str_ready_armor_1.5_plains_0.85_mtn_mtninf_1.15",
        "integration": [
            "land_combat_power_product",
            "LandCombatPower.gd",
        ],
    }


def land_combat_power_integrity() -> Dict[str, Any]:
    p = build_land_combat_power_product()
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
