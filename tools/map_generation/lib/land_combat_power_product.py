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
LEADER_BONUS_SCALE = 1.0
LEADER_BONUS_CAP = 0.25
LEADER_DEFEND_ATTACK_SCALE = 0.6

_ARMOR_TOKENS = ("armor", "armour", "panzer", "tank")
_MOUNTAIN_TOKENS = ("mountain", "gebirg")

_GD_FUNCS = ("template_kind", "template_speed", "combat_power", "leader_power_mult")
_ATTACK_KEYS = ("attack_modifier", "get_attack_modifier", "attack")
_DEFENSE_KEYS = ("defense_modifier", "get_defense_modifier", "defense")
_TERRAIN_KEYS = ("terrain_modifier", "get_terrain_modifier")
_DEFEND_ROLES = ("defend", "defender", "defense", "def")
_ATTACK_ROLES = ("attack", "attacker", "offense", "offence", "att")
_DEFEND_MISSIONS = ("DEFEND", "GARRISON")


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


def _leader_blob(data: Mapping[str, Any]) -> Optional[Mapping[str, Any]]:
    for key in ("assigned_leader", "leader"):
        nested = data.get(key)
        if isinstance(nested, Mapping):
            return nested
    return None


def _read_opt(data: Mapping[str, Any], keys: List[str]) -> Optional[float]:
    for k in keys:
        if k in data and data.get(k) is not None:
            try:
                return float(data.get(k))
            except (TypeError, ValueError):
                continue
    return None


def _terrain_mod(blob: Mapping[str, Any], terrain: str) -> float:
    direct = _read_opt(blob, list(_TERRAIN_KEYS))
    if direct is not None:
        return float(direct)
    raw = blob.get("terrain")
    if isinstance(raw, Mapping):
        terr = _norm_terrain(terrain)
        if terr in raw and raw.get(terr) is not None:
            try:
                return float(raw.get(terr))
            except (TypeError, ValueError):
                return 0.0
    return 0.0


def _resolve_combat_role(data: Optional[Mapping[str, Any]], role: str = "") -> str:
    r = str(role or "").strip().lower()
    if r in _DEFEND_ROLES:
        return "defend"
    if r in _ATTACK_ROLES:
        return "attack"
    if data is None:
        return "attack"
    if bool(data.get("is_defender")):
        return "defend"
    cr = str(data.get("combat_role") or data.get("role") or "").strip().lower()
    if cr in _DEFEND_ROLES:
        return "defend"
    mission = str(data.get("current_land_mission") or "").strip().upper()
    if mission in _DEFEND_MISSIONS:
        return "defend"
    return "attack"


def leader_power_mult(formation: Any, terrain: str = "plains", role: str = "") -> float:
    """1.0 + clamp(attack|defense * scale, 0, 0.25). No leader → 1.0."""
    data = _as_map(formation)
    if data is None:
        return 1.0
    blob = _leader_blob(data)
    src: Mapping[str, Any] = blob if blob is not None else data
    attack = _read_opt(src, list(_ATTACK_KEYS))
    defense = _read_opt(src, list(_DEFENSE_KEYS))
    has_leader = attack is not None or defense is not None or blob is not None
    if not has_leader:
        return 1.0
    att = float(attack) if attack is not None else 0.0
    if _resolve_combat_role(data, role) == "defend":
        raw = float(defense) if defense is not None else att * LEADER_DEFEND_ATTACK_SCALE
    else:
        raw = att
    raw += _terrain_mod(src, terrain)
    return 1.0 + _clamp(raw * LEADER_BONUS_SCALE, 0.0, LEADER_BONUS_CAP)


def combat_power(formation: Any, terrain: str = "plains", role: str = "") -> float:
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
    power *= leader_power_mult(data, terrain, role)
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

    no_lead = leader_power_mult(inf)
    if abs(no_lead - 1.0) < 1e-9:
        passes.append("no_leader_mult_1")
    else:
        fails.append("no_leader_mult_1")

    att_led = _full(design_id="infantry_division", attack_modifier=0.2)
    att_mult = leader_power_mult(att_led)
    if abs(att_mult - 1.2) < 1e-6:
        passes.append("attack_0_2_about_1_2")
    else:
        fails.append("attack_0_2_about_1_2")

    clamped = leader_power_mult(_full(design_id="infantry_division", attack_modifier=0.5))
    if abs(clamped - 1.25) < 1e-6:
        passes.append("leader_clamp_1_25")
    else:
        fails.append("leader_clamp_1_25")

    def_mult = leader_power_mult(
        _full(design_id="infantry_division", attack_modifier=0.2, defense_modifier=0.1),
        "plains",
        "defend",
    )
    if abs(def_mult - 1.1) < 1e-6:
        passes.append("defender_uses_defense")
    else:
        fails.append("defender_uses_defense")

    def_fb = leader_power_mult(att_led, "plains", "defend")
    if abs(def_fb - (1.0 + 0.2 * LEADER_DEFEND_ATTACK_SCALE)) < 1e-6:
        passes.append("defender_fallback_attack_0_6")
    else:
        fails.append("defender_fallback_attack_0_6")

    led_power = combat_power(att_led, "plains")
    if abs(led_power - inf_plains * 1.2) < 1e-6:
        passes.append("combat_power_times_leader")
    else:
        fails.append("combat_power_times_leader")

    gd_src = LAND_COMBAT_POWER_GD.read_text(encoding="utf-8") if LAND_COMBAT_POWER_GD.is_file() else ""
    if _gd_has_helpers(gd_src):
        passes.append("gd_helpers")
    else:
        fails.append("gd_helpers")
    if "static func leader_power_mult" in gd_src and "LEADER_BONUS_CAP" in gd_src:
        passes.append("gd_leader_power_mult")
    else:
        fails.append("gd_leader_power_mult")

    ok = len(fails) == 0
    fixtures: Dict[str, Any] = {
        "infantry_plains": inf_plains,
        "armor_plains": arm_plains,
        "infantry_mountain": inf_mtn,
        "armor_mountain": arm_mtn,
        "mountain_infantry_mountain": mtn_mtn,
        "missing": missing,
        "leader": {
            "no_leader": no_lead,
            "attack_0_2": att_mult,
            "clamp": clamped,
            "defend": def_mult,
            "defend_fallback": def_fb,
            "combat_power_with_leader": led_power,
        },
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
        "policy": "base_100_org_str_ready_armor_1.5_plains_0.85_mtn_mtninf_1.15_leader_1_plus_clamp_0_25",
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
