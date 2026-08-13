"""Year multi-AI campaign plan — pure product.

Plans a 1-year (default 365 day) test where every land-owning nation is an AI
agent. Does not run Godot; the live path is GameData.apply_year_multi_ai_campaign_live
+ HeadlessYearMultiAiCampaignTest.gd.
"""
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"
DEFAULT_OWN = "province_ownership_1936.json"
DEFAULT_SCENARIO = ROOT / "data" / "scenarios" / "world_accurate.json"

WATER = frozenset({"sea", "ocean", "water", "lake", "strait"})
MAJOR_TAGS = ("GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP", "POL")


def _is_water(p: dict) -> bool:
    terr = str(p.get("terrain", "")).lower()
    dom = str(p.get("domain", "land")).lower()
    return terr in WATER or dom in WATER


def collect_owner_tags(board_dir: str = "", *, land_only: bool = True) -> List[str]:
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    base = {
        int(p["id"]): p
        for p in json.loads((d / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
    }
    own = (
        json.loads((d / DEFAULT_OWN).read_text(encoding="utf-8")).get("owners") or {}
    )
    counts: Counter = Counter()
    for pid_s, tag in own.items():
        pid = int(pid_s)
        t = str(tag or "").strip().upper()
        if not t:
            continue
        if land_only and pid in base and _is_water(base[pid]):
            continue
        counts[t] += 1
    # majors first, then rest by size
    ordered: List[str] = []
    for m in MAJOR_TAGS:
        if m in counts and m not in ordered:
            ordered.append(m)
    for t, _n in counts.most_common():
        if t not in ordered:
            ordered.append(t)
    return ordered


def build_year_multi_ai_campaign_product(
    board_dir: str = "",
    *,
    days: int = 365,
    majors_only: bool = False,
    max_factions: int = 0,
) -> Dict[str, Any]:
    """Plan product: faction list all-AI, day budget, wiring checks."""
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    fails: List[str] = []
    passes: List[str] = []

    tags = collect_owner_tags(str(d))
    if majors_only:
        tags = [t for t in tags if t in MAJOR_TAGS]
    if max_factions > 0:
        tags = tags[: int(max_factions)]

    if len(tags) < 4:
        fails.append("too_few_factions=%d" % len(tags))
    else:
        passes.append("factions_n=%d" % len(tags))

    day_n = max(1, int(days))
    if day_n < 30:
        passes.append("short_smoke_days=%d" % day_n)
    elif day_n >= 365:
        passes.append("full_year_days=%d" % day_n)
    else:
        passes.append("partial_year_days=%d" % day_n)

    # Estimate AI apply volume (factions × days) — informational
    est_ai_tag_days = len(tags) * day_n
    passes.append("est_ai_tag_days=%d" % est_ai_tag_days)

    # Wiring: GameData year API + SessionPlayers all AI + headless harness
    gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
    sp = (ROOT / "scripts" / "autoload" / "SessionPlayers.gd").read_text(encoding="utf-8")
    mm = (ROOT / "scripts" / "map" / "MapManager.gd").read_text(encoding="utf-8")
    headless = ROOT / "scripts" / "core" / "HeadlessYearMultiAiCampaignTest.gd"
    shell = ROOT / "tools" / "eoa_year_multi_ai_test.sh"
    if "func apply_year_multi_ai_campaign_live" in gd:
        passes.append("gamedata_year_api")
    else:
        fails.append("missing_apply_year_multi_ai_campaign_live")
    if "major_apply_sum" in gd:
        passes.append("gamedata_tracks_major_apply")
    else:
        fails.append("missing_major_apply_sum")
    if "func setup_all_ai" in sp:
        passes.append("sessionplayers_setup_all_ai")
    else:
        fails.append("missing_setup_all_ai")
    if "EOA_YEAR_MULTI_AI" in mm:
        passes.append("mapmanager_year_lean_gate")
    else:
        fails.append("missing_EOA_YEAR_MULTI_AI_gate")
    if headless.is_file():
        passes.append("headless_harness")
        ht = headless.read_text(encoding="utf-8")
        if "apply_year_multi_ai_campaign_live" in ht:
            passes.append("headless_calls_year_api")
        else:
            fails.append("headless_missing_year_call")
        if "major_apply_sum" in ht:
            passes.append("headless_checks_major_apply")
        else:
            fails.append("headless_missing_major_apply_check")
        if "year_multi_ai_campaign_evidence" in ht:
            passes.append("headless_writes_evidence")
        else:
            fails.append("headless_missing_evidence_write")
    else:
        fails.append("missing_headless_harness")
    if shell.is_file():
        sh = shell.read_text(encoding="utf-8")
        if "SCRIPT ERROR" in sh and "end ok=true" in sh:
            passes.append("shell_fail_closed")
        else:
            fails.append("shell_missing_fail_closed")
    else:
        fails.append("missing_shell")

    factions = [{"tag": t, "control": "ai"} for t in tags]
    ok = len(fails) == 0
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "days": day_n,
        "factions": factions,
        "faction_tags": tags,
        "factions_n": len(tags),
        "majors_only": majors_only,
        "est_ai_tag_days": est_ai_tag_days,
        "all_ai": True,
        "pass": passes,
        "fail": fails,
        "summary": (
            "Year multi-AI plan · days=%d · factions=%d · all_ai · est_tag_days=%d · %s"
            % (day_n, len(tags), est_ai_tag_days, "PASS" if ok else "FAIL")
        ),
        "run_cmd": (
            "tools/eoa_year_multi_ai_test.sh --days %d%s"
            % (day_n, " --majors-only" if majors_only else "")
        ),
        "integration": [
            "year_multi_ai_campaign_product",
            "multi_faction_ai_daily",
            "SessionPlayers.setup_all_ai",
            "world_accurate",
        ],
    }


def year_multi_ai_campaign_integrity(
    board_dir: str = "",
    *,
    days: int = 365,
) -> Dict[str, Any]:
    p = build_year_multi_ai_campaign_product(board_dir=board_dir, days=days)
    return {
        "ok": bool(p.get("ok")),
        "days": p.get("days"),
        "factions_n": p.get("factions_n"),
        "fail": p.get("fail") or [],
        "summary": p.get("summary"),
        "empty": False,
    }
