"""Long-session (20–60d) save contract: mid-war blob must round-trip.

A mid-war Ctrl+S / year autosave must keep scenario metadata, clock, map,
leaders (formations + is_in_combat), active infra projects, production, and
the land_war blob (open_battles + marches). Empty battle/march lists are
valid; a missing land_war.open_battles key is not.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional

ROOT = Path(__file__).resolve().parents[3]
SL_GD = ROOT / "scripts" / "autoload" / "SaveLoadManager.gd"
LM_GD = ROOT / "scripts" / "leaders" / "LeaderManager.gd"

REQUIRED_ROOT_KEYS = (
    "metadata",
    "time",
    "map",
    "leaders",
    "infrastructure_projects",
    "land_war",
    "production",
)
LAND_WAR_REQUIRED_KEYS = ("open_battles", "marches")
METADATA_REQUIRED_KEYS = ("scenario_id", "game_version")

EMPTY_LAND_WAR = {
    "version": 1,
    "open_battles": [],
    "marches": {},
    "next_seq": 1,
    "last_aar": {},
}


def extract_gd_func_body(src: str, func_name: str) -> str:
    needle = "func %s" % func_name
    i = src.find(needle)
    if i < 0:
        return ""
    lines = src[i:].splitlines()
    out = [lines[0]]
    for line in lines[1:]:
        if line.startswith("func ") or line.startswith("static func "):
            break
        out.append(line)
    return "\n".join(out)


def empty_land_war_shape() -> Dict[str, Any]:
    return {
        "version": int(EMPTY_LAND_WAR["version"]),
        "open_battles": [],
        "marches": {},
        "next_seq": int(EMPTY_LAND_WAR["next_seq"]),
        "last_aar": {},
    }


def ensure_land_war_save_shape(raw: Any) -> Dict[str, Any]:
    """Always emit the land_war {} shape. Missing open_battles → []."""
    out = empty_land_war_shape()
    if not isinstance(raw, Mapping):
        return out
    battles = raw.get("open_battles")
    if isinstance(battles, (list, tuple)):
        out["open_battles"] = list(battles)
    marches = raw.get("marches")
    if isinstance(marches, Mapping):
        out["marches"] = dict(marches)
    try:
        out["next_seq"] = max(1, int(raw.get("next_seq") or 1))
    except (TypeError, ValueError):
        out["next_seq"] = 1
    aar = raw.get("last_aar")
    if isinstance(aar, Mapping):
        out["last_aar"] = dict(aar)
    try:
        out["version"] = int(raw.get("version") or 1)
    except (TypeError, ValueError):
        out["version"] = 1
    return out


def build_mid_war_20d_save(
    *,
    scenario_id: str = "world_accurate",
    game_version: str = "0.2-dev",
    days_elapsed: int = 20,
    open_battles: Optional[List[Any]] = None,
    marches: Optional[Mapping[str, Any]] = None,
    infrastructure_projects: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    battles = list(open_battles) if open_battles is not None else [
        {
            "id": "lb_20d",
            "from_id": 710173,
            "to_id": 710739,
            "att_tag": "GER",
            "def_tag": "FRA",
            "att_fid": "ger_1",
            "def_fid": "fra_1",
            "att_org": 0.55,
            "def_org": 0.42,
            "days_elapsed": 4,
            "att_stance": "press",
        }
    ]
    march_blob = dict(marches) if marches is not None else {
        "ger_2": {
            "formation_id": "ger_2",
            "country_tag": "GER",
            "path": [710173, 710180],
            "hop_index": 1,
            "progress": 0.3,
            "dest_id": 710180,
            "from_id": 710173,
        }
    }
    infra = dict(infrastructure_projects) if infrastructure_projects is not None else {
        "version": 1,
        "active_projects": {
            "710173": {"kind": "rail", "days_left": 8},
        },
    }
    return {
        "save_version": 1,
        "metadata": {
            "scenario_id": str(scenario_id),
            "game_version": str(game_version),
            "player_tag": "GER",
        },
        "time": {
            "current_date": {"year": 1936, "month": 1, "day": 21},
            "total_days_elapsed": int(days_elapsed),
        },
        "map": {"provinces": [{"id": 710173, "owner_tag": "GER"}]},
        "leaders": {
            "formations": {
                "ger_1": {
                    "formation_id": "ger_1",
                    "stationed_province_id": 710173,
                    "is_in_combat": True,
                }
            }
        },
        "infrastructure_projects": infra,
        "land_war": ensure_land_war_save_shape(
            {"open_battles": battles, "marches": march_blob, "next_seq": 3}
        ),
        "production": {"stance": "civilian"},
    }


def validate_long_session_save(blob: Any) -> Dict[str, Any]:
    """Fail if required mid-war keys are missing. Empty open_battles list is OK."""
    missing: List[str] = []
    errors: List[str] = []
    if not isinstance(blob, Mapping):
        return {
            "ok": False,
            "missing": list(REQUIRED_ROOT_KEYS),
            "errors": ["root_not_mapping"],
        }
    for key in REQUIRED_ROOT_KEYS:
        if key not in blob:
            missing.append(key)

    meta = blob.get("metadata") if "metadata" in blob else None
    if "metadata" in blob and not isinstance(meta, Mapping):
        errors.append("metadata_not_mapping")
    elif isinstance(meta, Mapping):
        for key in METADATA_REQUIRED_KEYS:
            if key not in meta:
                missing.append("metadata.%s" % key)
            elif str(meta.get(key) or "").strip() == "":
                errors.append("metadata.%s_empty" % key)

    lw = blob.get("land_war") if "land_war" in blob else None
    if "land_war" in blob:
        if not isinstance(lw, Mapping):
            errors.append("land_war_not_mapping")
        else:
            if "open_battles" not in lw:
                missing.append("land_war.open_battles")
            elif not isinstance(lw.get("open_battles"), (list, tuple)):
                errors.append("land_war.open_battles_not_list")
            if "marches" not in lw:
                missing.append("land_war.marches")
            elif not isinstance(lw.get("marches"), Mapping):
                errors.append("land_war.marches_not_mapping")

    for key in ("time", "map", "leaders", "infrastructure_projects", "production"):
        if key in blob and not isinstance(blob.get(key), Mapping):
            errors.append("%s_not_mapping" % key)

    ok = not missing and not errors
    return {
        "ok": ok,
        "missing": missing,
        "errors": errors,
        "summary": "long_session_save · %s · missing=%d errors=%d"
        % ("PASS" if ok else "FAIL", len(missing), len(errors)),
    }


def land_war_applied_after_leaders(src: str) -> bool:
    body = extract_gd_func_body(src, "_apply_save_data")
    if not body:
        return False
    i_leaders = body.find('_apply_leader_state')
    if i_leaders < 0:
        i_leaders = body.find('data.has("leaders")')
    i_land = body.find('data.has("land_war")')
    if i_land < 0:
        i_land = body.find("land_war")
    return i_leaders >= 0 and i_land >= 0 and i_leaders < i_land


def save_game_detailed_refuses_missing_land_war(src: str) -> bool:
    body = extract_gd_func_body(src, "save_game_detailed")
    if not body:
        return False
    has_key_check = 'has("land_war")' in body or "has('land_war')" in body
    refuses = '"ok": false' in body and "missing land_war key" in body
    return has_key_check and refuses


def shipped_save_integrity() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    sl = SL_GD.read_text(encoding="utf-8") if SL_GD.is_file() else ""
    lm = LM_GD.read_text(encoding="utf-8") if LM_GD.is_file() else ""

    if 'data["land_war"]' in sl or "data['land_war']" in sl:
        passes.append("sl_gather_land_war")
    else:
        fails.append("sl_gather_land_war")
    if "infrastructure_projects" in sl:
        passes.append("sl_infrastructure_projects")
    else:
        fails.append("sl_infrastructure_projects")
    if "autosave" in sl:
        passes.append("sl_autosave")
    else:
        fails.append("sl_autosave")
    if land_war_applied_after_leaders(sl):
        passes.append("apply_land_war_after_leaders")
    else:
        fails.append("apply_land_war_after_leaders")
    if save_game_detailed_refuses_missing_land_war(sl):
        passes.append("save_refuses_missing_land_war")
    else:
        fails.append("save_refuses_missing_land_war")

    gather = extract_gd_func_body(sl, "_gather_save_data")
    if gather and '"open_battles": []' in gather and '"marches": {}' in gather:
        passes.append("gather_emits_land_war_shape")
    else:
        fails.append("gather_emits_land_war_shape")

    get_body = extract_gd_func_body(lm, "get_save_data")
    apply_body = extract_gd_func_body(lm, "apply_save_data")
    if get_body and "is_in_combat" in get_body:
        passes.append("leaders_save_is_in_combat")
    else:
        fails.append("leaders_save_is_in_combat")
    if apply_body and "is_in_combat" in apply_body and 'get("is_in_combat"' in apply_body:
        passes.append("leaders_load_is_in_combat_additive")
    else:
        fails.append("leaders_load_is_in_combat_additive")
    for key in ("combat_experience", "planning", "entrenchment"):
        if get_body and key in get_body and apply_body and 'get("%s"' % key in apply_body:
            passes.append("leaders_save_%s" % key)
        else:
            fails.append("leaders_save_%s" % key)

    ok = len(fails) == 0
    return {
        "ok": ok,
        "pass": passes,
        "fail": fails,
    }


def build_long_session_save_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []

    mid = build_mid_war_20d_save()
    good = validate_long_session_save(mid)
    if good.get("ok"):
        passes.append("mid_war_20d_valid")
    else:
        fails.append("mid_war_20d_valid")

    empty_battles = build_mid_war_20d_save(open_battles=[], marches={})
    empty_ok = validate_long_session_save(empty_battles)
    if empty_ok.get("ok"):
        passes.append("empty_battles_ok")
    else:
        fails.append("empty_battles_ok")

    missing_ob = dict(mid)
    missing_ob["land_war"] = {"marches": {}, "version": 1}
    bad_ob = validate_long_session_save(missing_ob)
    if not bad_ob.get("ok") and "land_war.open_battles" in (bad_ob.get("missing") or []):
        passes.append("missing_open_battles_fails")
    else:
        fails.append("missing_open_battles_fails")

    missing_root = {k: mid[k] for k in mid if k != "land_war"}
    bad_root = validate_long_session_save(missing_root)
    if not bad_root.get("ok") and "land_war" in (bad_root.get("missing") or []):
        passes.append("missing_land_war_root_fails")
    else:
        fails.append("missing_land_war_root_fails")

    no_meta_keys = dict(mid)
    no_meta_keys["metadata"] = {"player_tag": "GER"}
    bad_meta = validate_long_session_save(no_meta_keys)
    miss_meta = set(bad_meta.get("missing") or [])
    if (
        not bad_meta.get("ok")
        and "metadata.scenario_id" in miss_meta
        and "metadata.game_version" in miss_meta
    ):
        passes.append("metadata_requires_scenario_and_version")
    else:
        fails.append("metadata_requires_scenario_and_version")

    ship = shipped_save_integrity()
    for name in ship.get("pass") or []:
        passes.append(name)
    for name in ship.get("fail") or []:
        fails.append(name)

    ok = len(fails) == 0
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "summary": "long_session_save · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "mid_war_20d_required_keys",
        "required_root_keys": list(REQUIRED_ROOT_KEYS),
    }


def long_session_save_integrity() -> Dict[str, Any]:
    p = build_long_session_save_product()
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
