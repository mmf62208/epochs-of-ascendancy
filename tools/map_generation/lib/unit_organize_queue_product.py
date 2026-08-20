"""Organize / recruit queue — existing template vs new, train time, priority.

Existing template on fielded units: equipment transit days; org/rdy/str dip
until ready. New units: train/organize days before combat-ready. Priority
splits a daily equipment budget between fielded and new. Deploy only on
core (or owned-if-no-cores) provinces. Multi-recruit = N jobs.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Sequence

ROOT = Path(__file__).resolve().parents[3]
LEADER = ROOT / "scripts" / "leaders" / "LeaderManager.gd"
POPUP = ROOT / "scripts" / "ui" / "DomainDesignPopup.gd"
TM = ROOT / "scripts" / "autoload" / "TimeManager.gd"
GATES = ROOT / "tools" / "eoa_full_test_gates.sh"
HARNESS = ROOT / "scripts" / "core" / "HeadlessWorldAccurateUnitOrderLoopTest.gd"

NEW_TRAIN_DAYS = 14
EXISTING_TRAIN_DAYS = 10
REFIT_DAYS = 7

REFIT_ORG = 0.65
REFIT_RDY = 0.55
REFIT_STR = 0.85

TRAIN_ORG = 0.40
TRAIN_RDY = 0.35
TRAIN_STR = 0.50

PRIORITY_FIELD = "field"
PRIORITY_NEW = "new"


def clamp01(v: float, lo: float = 0.0, hi: float = 1.0) -> float:
    try:
        x = float(v)
    except (TypeError, ValueError):
        return lo
    return max(lo, min(hi, x))


def is_core_deploy(pid: int, cores: Sequence[int]) -> bool:
    try:
        p = int(pid)
    except (TypeError, ValueError):
        return False
    if p <= 0:
        return False
    return p in {int(x) for x in (cores or [])}


def train_days(*, mode: str, existing_template: bool) -> int:
    m = str(mode or "").strip().lower()
    if m in ("refit", "convert", "existing_field"):
        return REFIT_DAYS
    if existing_template or m == "existing":
        return EXISTING_TRAIN_DAYS
    return NEW_TRAIN_DAYS


def start_stats(*, mode: str) -> Dict[str, float]:
    m = str(mode or "").strip().lower()
    if m in ("refit", "convert", "existing_field"):
        return {
            "organization": REFIT_ORG,
            "readiness": REFIT_RDY,
            "strength": REFIT_STR,
            "combat_ready": False,
        }
    return {
        "organization": TRAIN_ORG,
        "readiness": TRAIN_RDY,
        "strength": TRAIN_STR,
        "combat_ready": False,
    }


def tick_stats(job: Dict[str, Any], days: float = 1.0) -> Dict[str, Any]:
    out = dict(job or {})
    left = float(out.get("days_left", out.get("train_days", 0))) - float(days)
    out["days_left"] = max(0.0, left)
    if out["days_left"] <= 0.0:
        out["organization"] = 1.0
        out["readiness"] = 1.0
        out["strength"] = clamp01(float(out.get("target_strength", 1.0)), 0.4, 1.0)
        out["combat_ready"] = True
        out["is_training"] = False
    else:
        total = max(1.0, float(out.get("train_days", 1.0)))
        t = 1.0 - (out["days_left"] / total)
        start = start_stats(mode=str(out.get("mode", "new")))
        tgt = clamp01(float(out.get("target_strength", 1.0)), 0.4, 1.0)
        out["organization"] = start["organization"] + (1.0 - start["organization"]) * t
        out["readiness"] = start["readiness"] + (1.0 - start["readiness"]) * t
        out["strength"] = start["strength"] + (tgt - start["strength"]) * t
        out["combat_ready"] = False
        out["is_training"] = True
    return out


def split_equip_budget(
    budget: float,
    field_demand: float,
    new_demand: float,
    priority: str = PRIORITY_FIELD,
) -> Dict[str, float]:
    b = max(0.0, float(budget))
    fd = max(0.0, float(field_demand))
    nd = max(0.0, float(new_demand))
    pri = str(priority or PRIORITY_FIELD).strip().lower()
    if pri == PRIORITY_NEW:
        to_new = min(nd, b)
        to_field = min(fd, b - to_new)
    else:
        to_field = min(fd, b)
        to_new = min(nd, b - to_field)
    return {
        "field": to_field,
        "new": to_new,
        "leftover": max(0.0, b - to_field - to_new),
        "priority": PRIORITY_NEW if pri == PRIORITY_NEW else PRIORITY_FIELD,
    }


def plan_organize(
    *,
    mode: str = "new",
    template_id: str = "panzer_iii_j_medium",
    count: int = 1,
    deploy_pid: int = 710173,
    cores: Sequence[int] = (710173, 710300),
    priority: str = PRIORITY_FIELD,
    existing_template: bool = False,
    target_strength: float = 1.0,
) -> Dict[str, Any]:
    n = max(1, min(8, int(count or 1)))
    pid = int(deploy_pid)
    if not is_core_deploy(pid, cores):
        return {
            "ok": False,
            "error": "not_core",
            "deploy_pid": pid,
            "cores": list(cores),
        }
    m = str(mode or "new").strip().lower()
    if m in ("existing", "existing_new"):
        m = "existing"
        existing_template = True
    if m in ("refit", "convert"):
        m = "refit"
    days = train_days(mode=m, existing_template=existing_template)
    stats = start_stats(mode=m)
    jobs: List[Dict[str, Any]] = []
    for i in range(n):
        jobs.append(
            {
                "mode": m,
                "template_id": str(template_id or ""),
                "deploy_pid": pid,
                "train_days": days,
                "days_left": float(days),
                "target_strength": clamp01(target_strength, 0.4, 1.0),
                "is_training": True,
                "combat_ready": False,
                "organization": stats["organization"],
                "readiness": stats["readiness"],
                "strength": stats["strength"],
                "index": i,
            }
        )
    return {
        "ok": True,
        "mode": m,
        "count": n,
        "deploy_pid": pid,
        "priority": PRIORITY_NEW if str(priority).strip().lower() == PRIORITY_NEW else PRIORITY_FIELD,
        "jobs": jobs,
        "train_days": days,
        "existing_template": bool(existing_template or m in ("existing", "refit")),
    }


def build_unit_organize_queue_product(*, check_wiring: bool = True) -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    wiring: Dict[str, bool] = {}

    p = plan_organize(mode="new", count=3, deploy_pid=710173, cores=[710173, 710300])
    if p.get("ok") and int(p.get("count", 0)) == 3 and int(p.get("train_days", 0)) == NEW_TRAIN_DAYS:
        passes.append("multi_new")
    else:
        fails.append("multi_new")

    ex = plan_organize(
        mode="existing",
        existing_template=True,
        count=2,
        deploy_pid=710173,
        cores=[710173],
    )
    if ex.get("ok") and int(ex.get("train_days", 0)) == EXISTING_TRAIN_DAYS:
        passes.append("existing_train")
    else:
        fails.append("existing_train")

    rf = plan_organize(mode="refit", count=1, deploy_pid=710173, cores=[710173])
    if rf.get("ok") and int(rf.get("train_days", 0)) == REFIT_DAYS:
        passes.append("refit_days")
    else:
        fails.append("refit_days")

    bad = plan_organize(mode="new", deploy_pid=1, cores=[710173])
    if not bad.get("ok") and str(bad.get("error", "")) == "not_core":
        passes.append("core_gate")
    else:
        fails.append("core_gate")

    job = dict((p.get("jobs") or [{}])[0])
    mid = tick_stats(job, days=NEW_TRAIN_DAYS / 2.0)
    done = tick_stats(job, days=float(NEW_TRAIN_DAYS))
    if (not mid.get("combat_ready")) and done.get("combat_ready") and float(done.get("organization", 0)) >= 0.99:
        passes.append("train_tick")
    else:
        fails.append("train_tick")

    split_f = split_equip_budget(10.0, 8.0, 8.0, PRIORITY_FIELD)
    split_n = split_equip_budget(10.0, 8.0, 8.0, PRIORITY_NEW)
    if split_f.get("field") == 8.0 and split_f.get("new") == 2.0 and split_n.get("new") == 8.0:
        passes.append("priority_split")
    else:
        fails.append("priority_split")

    if check_wiring:
        lm = LEADER.read_text(encoding="utf-8") if LEADER.is_file() else ""
        pop = POPUP.read_text(encoding="utf-8") if POPUP.is_file() else ""
        tm = TM.read_text(encoding="utf-8") if TM.is_file() else ""
        gates = GATES.read_text(encoding="utf-8") if GATES.is_file() else ""
        harness = HARNESS.read_text(encoding="utf-8") if HARNESS.is_file() else ""

        def _ok(name: str, cond: bool) -> None:
            wiring[name] = cond
            (passes if cond else fails).append(name)

        _ok("enqueue_api", "func enqueue_organize" in lm)
        _ok("tick_api", "func tick_organize_day" in lm)
        _ok("core_list_api", "func list_core_deploy_pids" in lm)
        _ok("popup_mode", "_mode_existing" in pop or "Existing template" in pop)
        _ok("popup_count", "_count_spin" in pop)
        _ok("popup_priority", "_priority_option" in pop)
        _ok("popup_deploy", "_deploy_option" in pop)
        _ok("tm_tick", "tick_organize_day" in tm)
        _ok("on_official_quick", "test_unit_organize_queue_product" in gates)
        _ok("harness_organize", "enqueue_organize" in harness and "tick_organize_day" in harness)

    ok = len(fails) == 0
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "wiring": wiring,
        "pass": passes,
        "fail": fails,
        "new_train_days": NEW_TRAIN_DAYS,
        "existing_train_days": EXISTING_TRAIN_DAYS,
        "refit_days": REFIT_DAYS,
        "summary": "unit_organize_queue · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "existing_vs_new_train_refit_priority_core_multi",
    }


def unit_organize_queue_integrity(**kwargs: Any) -> Dict[str, Any]:
    p = build_unit_organize_queue_product(**kwargs)
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
