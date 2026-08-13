"""Multi-era ownership tables — scenario seed only (player agency).

Historical ownership JSON is applied once at scenario load from start_date.
It is NEVER reapplied on year ticks, conquest, or autosave. Live owner_tag on
provinces is the source of truth after the seed.
"""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple
import json

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DATA_DIR = ROOT / "data" / "provinces_world_full"

# Canonical era tables shipped with world_full.
ERA_YEARS: Tuple[int, ...] = (1910, 1918, 1936, 1945, 2026)


def player_agency_policy() -> Dict[str, Any]:
    return {
        "seed_on_scenario_load": True,
        "reapply_on_year_tick": False,
        "reapply_on_daily_tick": False,
        "reapply_on_save_load": False,  # save carries live owners
        "scenario_overrides_win": True,  # scenario JSON province.owner_tag beats table
        "event_forced_only": True,  # only explicit content/events may mass-reassign
        "player_conquest_preserved": True,
        "summary": "Ownership tables seed start map only; player agency owns the rest.",
        "empty": False,
    }


def resolve_ownership_era(start_year: int, eras: Sequence[int] = ERA_YEARS) -> int:
    """Largest era year <= start_year; if before all eras, use earliest."""
    try:
        y = int(start_year)
    except (TypeError, ValueError):
        y = 1936
    ordered = sorted(int(e) for e in eras)
    chosen = ordered[0]
    for e in ordered:
        if e <= y:
            chosen = e
        else:
            break
    return chosen


def ownership_table_filename(era_year: int) -> str:
    return "province_ownership_%d.json" % int(era_year)


def ownership_table_path(data_dir: Path | str, era_year: int) -> Path:
    return Path(data_dir) / ownership_table_filename(era_year)


def load_ownership_table(path: Path | str) -> Dict[str, Any]:
    p = Path(path)
    if not p.is_file():
        return {"owners": {}, "capitals": {}, "meta": {}, "empty": True, "ok": False}
    data = json.loads(p.read_text(encoding="utf-8"))
    owners = data.get("owners") or {}
    # normalize keys to str
    owners = {str(k): str(v).upper() if v else "" for k, v in owners.items()}
    return {
        "owners": owners,
        "capitals": {str(k).upper(): int(v) for k, v in (data.get("capitals") or {}).items()},
        "meta": data.get("meta") or {},
        "stats": data.get("stats") or {},
        "gates": data.get("gates") or {},
        "empty": len(owners) == 0,
        "ok": len(owners) > 0,
        "path": str(p),
        "era_year": int((data.get("meta") or {}).get("era_year") or 0),
    }


def list_available_eras(data_dir: Path | str = DEFAULT_DATA_DIR) -> List[int]:
    d = Path(data_dir)
    found = []
    for y in ERA_YEARS:
        if ownership_table_path(d, y).is_file():
            found.append(y)
    # also scan for any province_ownership_YYYY.json
    for f in d.glob("province_ownership_*.json"):
        stem = f.stem.replace("province_ownership_", "")
        if stem.isdigit():
            yi = int(stem)
            if yi not in found:
                found.append(yi)
    return sorted(found)


def build_era_index(data_dir: Path | str = DEFAULT_DATA_DIR) -> Dict[str, Any]:
    d = Path(data_dir)
    eras = []
    for y in list_available_eras(d):
        p = ownership_table_path(d, y)
        tab = load_ownership_table(p)
        eras.append({
            "year": y,
            "path": p.name,
            "owner_n": len(tab.get("owners") or {}),
            "ok": bool(tab.get("ok")),
        })
    return {
        "version": 1,
        "policy": player_agency_policy(),
        "eras": eras,
        "resolve_note": "Use largest era year <= scenario start_year",
        "empty": False,
    }


def write_era_index(data_dir: Path | str = DEFAULT_DATA_DIR) -> Path:
    d = Path(data_dir)
    idx = build_era_index(d)
    out = d / "ownership_era_index.json"
    out.write_text(json.dumps(idx, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return out


def ownership_era_integrity(data_dir: Path | str = DEFAULT_DATA_DIR) -> Dict[str, Any]:
    d = Path(data_dir)
    policy = player_agency_policy()
    eras = list_available_eras(d)
    has_2026 = 2026 in eras
    has_1936 = 1936 in eras
    t2026 = load_ownership_table(ownership_table_path(d, 2026)) if has_2026 else {}
    ok = (
        has_1936
        and has_2026
        and bool(t2026.get("ok"))
        and policy.get("reapply_on_year_tick") is False
        and resolve_ownership_era(2026) == 2026
        and resolve_ownership_era(2020) in eras
    )
    return {
        "ok": ok,
        "eras": eras,
        "has_2026": has_2026,
        "owner_n_2026": len((t2026.get("owners") or {})),
        "policy": policy,
        "summary": "Ownership era integrity %s · eras %s · 2026 owners %d"
        % ("PASS" if ok else "FAIL", eras, len((t2026.get("owners") or {}))),
        "empty": False,
    }
