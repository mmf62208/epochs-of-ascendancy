"""Persist open land battles + own-land march queues across save/load.

20–60d sessions lose the war loop if a mid-fight Ctrl+S / autosave drops
_open_land_battles and FormationMovement._orders. This product is the
round-trip contract; SaveLoadManager stores one land_war blob.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional

ROOT = Path(__file__).resolve().parents[3]
BM_GD = ROOT / "scripts" / "combat" / "BattleManager.gd"
FM_GD = ROOT / "scripts" / "formations" / "FormationMovement.gd"
SL_GD = ROOT / "scripts" / "autoload" / "SaveLoadManager.gd"

LAND_WAR_VERSION = 1

BATTLE_REQUIRED = (
    "id",
    "from_id",
    "to_id",
    "att_tag",
    "def_tag",
    "att_fid",
    "def_fid",
    "att_org",
    "def_org",
    "days_elapsed",
    "att_stance",
)
BATTLE_OPTIONAL = (
    "att_fids",
    "def_fids",
    "att_n",
    "def_n",
    "att_power",
    "def_power",
    "combat_width",
    "att_used_width",
    "terrain",
    "day_started",
    "est_days",
    "lean",
    "withdraw_pending",
    "ground_hard",
    "next_hook",
)
MARCH_REQUIRED = (
    "formation_id",
    "country_tag",
    "path",
    "hop_index",
    "progress",
    "dest_id",
    "from_id",
)


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


def _as_int_list(raw: Any) -> List[int]:
    out: List[int] = []
    if not isinstance(raw, (list, tuple)):
        return out
    for item in raw:
        try:
            n = int(item)
        except (TypeError, ValueError):
            continue
        if n > 0:
            out.append(n)
    return out


def validate_saved_battle(raw: Any) -> bool:
    if not isinstance(raw, Mapping):
        return False
    for key in BATTLE_REQUIRED:
        if key not in raw:
            return False
    try:
        if int(raw.get("to_id", 0)) <= 0 or int(raw.get("from_id", 0)) <= 0:
            return False
    except (TypeError, ValueError):
        return False
    att = str(raw.get("att_tag") or "").strip()
    fid = str(raw.get("att_fid") or "").strip()
    if not att or not fid:
        return False
    return True


def validate_saved_march(raw: Any) -> bool:
    if not isinstance(raw, Mapping):
        return False
    for key in MARCH_REQUIRED:
        if key not in raw:
            return False
    path = _as_int_list(raw.get("path"))
    if len(path) < 2:
        return False
    fid = str(raw.get("formation_id") or "").strip()
    tag = str(raw.get("country_tag") or "").strip()
    if not fid or not tag:
        return False
    try:
        if int(raw.get("dest_id", 0)) <= 0:
            return False
    except (TypeError, ValueError):
        return False
    return True


def serialize_open_battles(battles: Optional[List[Any]] = None) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for raw in battles or []:
        if not validate_saved_battle(raw):
            continue
        row: Dict[str, Any] = {}
        for key in BATTLE_REQUIRED + BATTLE_OPTIONAL:
            if key in raw:
                row[key] = raw[key]
        if "att_fids" not in row:
            row["att_fids"] = [str(raw.get("att_fid"))]
        if "def_fids" not in row:
            row["def_fids"] = [str(raw.get("def_fid"))]
        out.append(row)
    return out


def serialize_marches(orders: Optional[Mapping[str, Any]] = None) -> Dict[str, Dict[str, Any]]:
    out: Dict[str, Dict[str, Any]] = {}
    for fid_raw, raw in dict(orders or {}).items():
        if not isinstance(raw, Mapping):
            continue
        row = dict(raw)
        row.setdefault("formation_id", str(fid_raw))
        if not validate_saved_march(row):
            continue
        keep: Dict[str, Any] = {}
        for key in MARCH_REQUIRED:
            keep[key] = row[key]
        keep["path"] = _as_int_list(row.get("path"))
        keep["hop_index"] = int(row.get("hop_index", 1))
        keep["progress"] = float(row.get("progress", 0.0))
        keep["hop_cost"] = float(row.get("hop_cost", 1.0))
        keep["order_type"] = str(row.get("order_type") or "own_land_march")
        out[str(row.get("formation_id") or fid_raw)] = keep
    return out


def build_land_war_save_blob(
    *,
    battles: Optional[List[Any]] = None,
    marches: Optional[Mapping[str, Any]] = None,
    next_seq: int = 1,
    last_aar: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    aar = dict(last_aar or {}) if isinstance(last_aar, Mapping) else {}
    return {
        "version": LAND_WAR_VERSION,
        "open_battles": serialize_open_battles(battles),
        "marches": serialize_marches(marches),
        "next_seq": max(1, int(next_seq or 1)),
        "last_aar": aar,
    }


def apply_land_war_save_blob(blob: Any) -> Dict[str, Any]:
    if not isinstance(blob, Mapping):
        return {
            "ok": True,
            "empty": True,
            "open_battles": [],
            "marches": {},
            "next_seq": 1,
            "last_aar": {},
        }
    battles = serialize_open_battles(list(blob.get("open_battles") or []))
    marches = serialize_marches(dict(blob.get("marches") or {}))
    try:
        nxt = max(1, int(blob.get("next_seq") or 1))
    except (TypeError, ValueError):
        nxt = 1
    aar = blob.get("last_aar") if isinstance(blob.get("last_aar"), Mapping) else {}
    return {
        "ok": True,
        "empty": len(battles) == 0 and len(marches) == 0,
        "open_battles": battles,
        "marches": marches,
        "next_seq": nxt,
        "last_aar": dict(aar),
        "version": int(blob.get("version") or LAND_WAR_VERSION),
    }


def roundtrip_land_war(
    *,
    battles: Optional[List[Any]] = None,
    marches: Optional[Mapping[str, Any]] = None,
    last_aar: Optional[Mapping[str, Any]] = None,
) -> Dict[str, Any]:
    blob = build_land_war_save_blob(
        battles=battles, marches=marches, next_seq=4, last_aar=last_aar
    )
    restored = apply_land_war_save_blob(blob)
    same_battles = restored.get("open_battles") == blob.get("open_battles")
    same_marches = restored.get("marches") == blob.get("marches")
    return {
        "ok": bool(restored.get("ok")) and same_battles and same_marches,
        "same_battles": same_battles,
        "same_marches": same_marches,
        "blob": blob,
        "restored": restored,
    }


def build_land_war_save_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []

    battle = {
        "id": "lb_1",
        "from_id": 710173,
        "to_id": 710739,
        "att_tag": "GER",
        "def_tag": "FRA",
        "att_fid": "ger_1",
        "def_fid": "fra_1",
        "att_org": 0.82,
        "def_org": 0.61,
        "days_elapsed": 2,
        "att_stance": "press",
        "terrain": "hills",
    }
    march = {
        "ger_2": {
            "formation_id": "ger_2",
            "country_tag": "GER",
            "path": [710173, 710180, 710185],
            "hop_index": 1,
            "progress": 0.4,
            "hop_cost": 1.0,
            "dest_id": 710185,
            "from_id": 710173,
            "order_type": "own_land_march",
        }
    }
    aar = {"winner": "attacker", "next_pid": 710740, "line": "Took Bas-Rhin"}
    rt = roundtrip_land_war(battles=[battle], marches=march, last_aar=aar)
    if rt.get("ok") and rt.get("same_battles") and rt.get("same_marches"):
        passes.append("roundtrip")
    else:
        fails.append("roundtrip")
    restored = rt.get("restored") or {}
    if (restored.get("last_aar") or {}).get("next_pid") == 710740:
        passes.append("aar_survives")
    else:
        fails.append("aar_survives")

    junk = apply_land_war_save_blob(
        {
            "open_battles": [{"id": "nope"}],
            "marches": {"x": {"path": [1]}},
        }
    )
    if junk.get("ok") and not junk.get("open_battles") and not junk.get("marches"):
        passes.append("rejects_partial")
    else:
        fails.append("rejects_partial")

    empty = apply_land_war_save_blob(None)
    if empty.get("ok") and empty.get("empty"):
        passes.append("legacy_missing_ok")
    else:
        fails.append("legacy_missing_ok")

    if not validate_saved_battle({"id": "lb", "to_id": 0}):
        passes.append("battle_required_keys")
    else:
        fails.append("battle_required_keys")

    bm = BM_GD.read_text(encoding="utf-8") if BM_GD.is_file() else ""
    fm = FM_GD.read_text(encoding="utf-8") if FM_GD.is_file() else ""
    sl = SL_GD.read_text(encoding="utf-8") if SL_GD.is_file() else ""
    if "func get_save_data" in bm and "func apply_save_data" in bm:
        passes.append("bm_save_api")
    else:
        fails.append("bm_save_api")
    if "func get_save_data" in fm and "func apply_save_data" in fm:
        passes.append("fm_save_api")
    else:
        fails.append("fm_save_api")
    if 'data["land_war"]' in sl or "data['land_war']" in sl:
        passes.append("sl_gather_land_war")
    else:
        fails.append("sl_gather_land_war")
    apply_body = extract_gd_func_body(sl, "_apply_save_data")
    if apply_body and "land_war" in apply_body:
        passes.append("sl_apply_land_war")
    else:
        fails.append("sl_apply_land_war")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "summary": "land_war_save · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "open_battles_and_marches_roundtrip",
    }


def land_war_save_integrity() -> Dict[str, Any]:
    p = build_land_war_save_product()
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
