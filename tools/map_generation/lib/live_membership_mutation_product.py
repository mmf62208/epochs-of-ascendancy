"""Live hierarchy membership mutation product (pure bind math + policy gates).

Mirrors ScenarioLoader/GameData live API shapes so pure tests drive the same
province/state IDs from shipped hierarchy_membership_*.json boards.
Year-tick reapply remains hard-false (player agency).
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence

ROOT = Path(__file__).resolve().parents[3]
WORLD = ROOT / "data" / "provinces_world_full"

PRODUCT_STEPS = ("reassign", "create_state", "transfer_state", "agency_policy")


def load_membership_snapshot(data_dir: Path | str = WORLD, year: int = 1936) -> Dict[str, Any]:
    data_dir = Path(data_dir)
    path = data_dir / ("hierarchy_membership_%d.json" % int(year))
    if not path.is_file():
        # fallback scaffold-derived empty
        return {"mode": "missing", "province_to_state": {}, "province_to_region": {}, "province_to_super_region": {}, "states": []}
    return json.loads(path.read_text(encoding="utf-8"))


def snapshot_to_runtime(snap: Dict[str, Any]) -> Dict[str, Any]:
    """Runtime maps matching ScenarioLoader fields."""
    p2s = {int(k): int(v) for k, v in (snap.get("province_to_state") or {}).items()}
    p2r = {int(k): int(v) for k, v in (snap.get("province_to_region") or {}).items()}
    p2sr = {int(k): int(v) for k, v in (snap.get("province_to_super_region") or {}).items()}
    names = {}
    for s in snap.get("states") or []:
        names[int(s.get("id") or 0)] = str(s.get("name") or "")
    return {
        "province_state_by_id": p2s,
        "province_region_by_id": p2r,
        "province_super_by_id": p2sr,
        "province_state_names": names,
        "membership_live_mutation_count": 0,
        "membership_seed_applied": True,
        "membership_reapply_on_year_tick": False,
    }


def get_hierarchy(rt: Dict[str, Any], province_id: int) -> Dict[str, Any]:
    pid = int(province_id)
    sid = int(rt["province_state_by_id"].get(pid, 0))
    rid = int(rt["province_region_by_id"].get(pid, 0))
    srid = int(rt["province_super_by_id"].get(pid, 0))
    names = rt.get("province_state_names") or {}
    return {
        "province_id": pid,
        "state_id": sid,
        "state_name": names.get(sid, "State %d" % sid if sid else ""),
        "region_id": rid,
        "super_region_id": srid,
        "empty": sid <= 0 and rid <= 0 and srid <= 0,
    }


def _infer_region_for_state(rt: Dict[str, Any], state_id: int, exclude_pids: Optional[Sequence[int]] = None) -> int:
    """Region from existing destination peers only — never from movers (exclude_pids)."""
    exclude = {int(p) for p in (exclude_pids or [])}
    for pid, sid in rt["province_state_by_id"].items():
        if int(pid) in exclude:
            continue
        if int(sid) == int(state_id):
            rid = int(rt["province_region_by_id"].get(int(pid), 0))
            if rid > 0:
                return rid
    return 0


def _infer_super_for_region(rt: Dict[str, Any], region_id: int) -> int:
    if int(region_id) <= 0:
        return 0
    for pid, rid in rt["province_region_by_id"].items():
        if int(rid) == int(region_id):
            srid = int(rt["province_super_by_id"].get(int(pid), 0))
            if srid > 0:
                return srid
    return 0


def reassign_province_membership(
    rt: Dict[str, Any],
    province_id: int,
    new_state_id: int,
    new_region_id: int = -1,
    new_super_region_id: int = -1,
    new_state_name: str = "",
) -> Dict[str, Any]:
    """Same contract as ScenarioLoader.reassign_province_membership."""
    before = get_hierarchy(rt, province_id)
    pid, nsid = int(province_id), int(new_state_id)
    if pid <= 0 or nsid <= 0:
        return {"ok": False, "error": "invalid_ids", "live": True}
    # Resolve destination peers BEFORE mutating this province's state.
    dest_rid = int(new_region_id) if int(new_region_id) > 0 else _infer_region_for_state(rt, nsid, [pid])
    dest_srid = int(new_super_region_id) if int(new_super_region_id) > 0 else _infer_super_for_region(rt, dest_rid)
    rt["province_state_by_id"][pid] = nsid
    if new_state_name:
        rt["province_state_names"][nsid] = str(new_state_name)
    if dest_rid > 0:
        rt["province_region_by_id"][pid] = dest_rid
    if dest_srid > 0:
        rt["province_super_by_id"][pid] = dest_srid
    rt["membership_live_mutation_count"] = int(rt.get("membership_live_mutation_count") or 0) + 1
    after = get_hierarchy(rt, province_id)
    return {
        "ok": True,
        "live": True,
        "change_type": "reassign_province",
        "province_id": pid,
        "before": before,
        "after": after,
        "dest_region_id": dest_rid,
        "dest_super_region_id": dest_srid,
        "mutation_count": rt["membership_live_mutation_count"],
        "seed_only_policy": True,
        "reapply_on_year_tick": bool(rt.get("membership_reapply_on_year_tick")),
    }


def create_state_membership(
    rt: Dict[str, Any],
    province_ids: Sequence[int],
    state_name: str,
    region_id: int = 0,
    super_region_id: int = 0,
) -> Dict[str, Any]:
    pids = [int(p) for p in province_ids if int(p) > 0]
    if not pids:
        return {"ok": False, "error": "empty_province_ids", "live": True}
    new_sid = 900000000 + int(rt.get("membership_live_mutation_count") or 0) + 1
    while new_sid in (rt.get("province_state_names") or {}):
        new_sid += 1
    name = str(state_name or ("New State %d" % new_sid)).strip()
    rt["province_state_names"][new_sid] = name
    rid = int(region_id) or int(rt["province_region_by_id"].get(pids[0], 0))
    srid = int(super_region_id) or int(rt["province_super_by_id"].get(pids[0], 0))
    for pid in pids:
        rt["province_state_by_id"][pid] = new_sid
        if rid > 0:
            rt["province_region_by_id"][pid] = rid
        if srid > 0:
            rt["province_super_by_id"][pid] = srid
    rt["membership_live_mutation_count"] = int(rt.get("membership_live_mutation_count") or 0) + 1
    return {
        "ok": True,
        "live": True,
        "change_type": "create_state",
        "state_id": new_sid,
        "state_name": name,
        "province_ids": pids,
        "sample_hierarchy": get_hierarchy(rt, pids[0]),
        "mutation_count": rt["membership_live_mutation_count"],
        "seed_only_policy": True,
        "reapply_on_year_tick": False,
    }


def transfer_state_membership(rt: Dict[str, Any], from_state_id: int, to_state_id: int) -> Dict[str, Any]:
    fs, ts = int(from_state_id), int(to_state_id)
    if fs <= 0 or ts <= 0 or fs == ts:
        return {"ok": False, "error": "invalid_state_ids", "live": True}
    moved = [pid for pid, sid in rt["province_state_by_id"].items() if int(sid) == fs]
    if not moved:
        return {"ok": False, "error": "from_state_empty", "live": True}
    # Destination region/super from existing to_state peers only (before move).
    dest_rid = _infer_region_for_state(rt, ts, moved)
    dest_srid = _infer_super_for_region(rt, dest_rid)
    for pid in moved:
        rt["province_state_by_id"][pid] = ts
        if dest_rid > 0:
            rt["province_region_by_id"][pid] = dest_rid
        if dest_srid > 0:
            rt["province_super_by_id"][pid] = dest_srid
    rt["membership_live_mutation_count"] = int(rt.get("membership_live_mutation_count") or 0) + 1
    return {
        "ok": True,
        "live": True,
        "change_type": "transfer_state",
        "from_state_id": fs,
        "to_state_id": ts,
        "province_ids": moved,
        "province_n": len(moved),
        "dest_region_id": dest_rid,
        "dest_super_region_id": dest_srid,
        "sample_hierarchy": get_hierarchy(rt, moved[0]),
        "mutation_count": rt["membership_live_mutation_count"],
        "seed_only_policy": True,
        "reapply_on_year_tick": False,
    }


def find_cross_region_state_pair(rt: Dict[str, Any]) -> Dict[str, Any]:
    """Pick two real states with different region_ids from shipped runtime maps."""
    # state -> representative province + region
    state_info: Dict[int, Dict[str, int]] = {}
    for pid, sid in rt["province_state_by_id"].items():
        sid = int(sid)
        if sid <= 0 or sid in state_info:
            continue
        rid = int(rt["province_region_by_id"].get(int(pid), 0))
        srid = int(rt["province_super_by_id"].get(int(pid), 0))
        if rid > 0:
            state_info[sid] = {"province_id": int(pid), "region_id": rid, "super_region_id": srid}
    sids = list(state_info.keys())
    for i, a in enumerate(sids):
        for b in sids[i + 1 :]:
            if state_info[a]["region_id"] != state_info[b]["region_id"]:
                return {
                    "ok": True,
                    "from_state": a,
                    "to_state": b,
                    "from_region": state_info[a]["region_id"],
                    "to_region": state_info[b]["region_id"],
                    "from_super": state_info[a]["super_region_id"],
                    "to_super": state_info[b]["super_region_id"],
                    "from_province": state_info[a]["province_id"],
                    "to_province": state_info[b]["province_id"],
                }
    return {"ok": False, "error": "no_cross_region_pair"}


def exercise_cross_region_transfer(year: int = 1936) -> Dict[str, Any]:
    """Transfer full from_state → to_state across different regions; assert dest region/super."""
    snap = load_membership_snapshot(WORLD, year)
    assert str(snap.get("mode")) == "full"
    rt = snapshot_to_runtime(snap)
    pair = find_cross_region_state_pair(rt)
    if not pair.get("ok"):
        return {"ok": False, "error": "no_pair", "pair": pair}
    fs = int(pair["from_state"])
    ts = int(pair["to_state"])
    want_rid = int(pair["to_region"])
    want_srid = int(pair["to_super"])
    # Collect movers before transfer
    movers = [pid for pid, sid in rt["province_state_by_id"].items() if int(sid) == fs]
    assert movers
    # Source region should differ
    src_rids = {int(rt["province_region_by_id"].get(pid, 0)) for pid in movers}
    assert want_rid not in src_rids or len(src_rids) == 1  # typically all same region != dest
    tr = transfer_state_membership(rt, fs, ts)
    assert tr.get("ok")
    bad = []
    for pid in movers:
        h = get_hierarchy(rt, pid)
        if int(h.get("state_id") or 0) != ts:
            bad.append((pid, "state", h.get("state_id")))
        if int(h.get("region_id") or 0) != want_rid:
            bad.append((pid, "region", h.get("region_id"), want_rid))
        if want_srid > 0 and int(h.get("super_region_id") or 0) != want_srid:
            bad.append((pid, "super", h.get("super_region_id"), want_srid))
    ok = tr.get("ok") and not bad and int(tr.get("dest_region_id") or 0) == want_rid
    return {
        "ok": ok,
        "pair": pair,
        "moved_n": len(movers),
        "dest_region_id": tr.get("dest_region_id"),
        "dest_super_region_id": tr.get("dest_super_region_id"),
        "bad": bad[:8],
        "summary": "Cross-region transfer %s · %s→%s region %s"
        % ("PASS" if ok else "FAIL", fs, ts, want_rid),
    }


def agency_policy_ok() -> Dict[str, Any]:
    """Static + product policy: membership never reapplied on year tick."""
    sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
    gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
    tm = (ROOT / "scripts" / "autoload" / "TimeManager.gd").read_text(encoding="utf-8")
    ok = (
        "reassign_province_membership" in sl
        and "create_state_membership" in sl
        and "transfer_state_membership" in sl
        and "membership_reapply_on_year_tick" in sl
        and "reassign_province_membership_live" in gd
        and "create_state_membership_live" in gd
        and "transfer_state_membership_live" in gd
        and "apply_membership_mutation_live" in gd
        and "_apply_era_membership_seed" not in tm
        and "reapply_on_year_tick=0" in sl
        and "membership_live_mut=1" in sl
    )
    return {
        "ok": ok,
        "scenario_loader_apis": True,
        "gamedata_apis": "reassign_province_membership_live" in gd,
        "time_manager_no_reseed": "_apply_era_membership_seed" not in tm,
        "summary": "Live membership policy %s" % ("PASS" if ok else "FAIL"),
    }


def exercise_world_full_mutation(year: int = 1936) -> Dict[str, Any]:
    """Drive reassign/create/transfer on real shipped membership IDs."""
    snap = load_membership_snapshot(WORLD, year)
    assert str(snap.get("mode")) == "full"
    rt = snapshot_to_runtime(snap)
    p2s = rt["province_state_by_id"]
    assert p2s
    # two provinces different states
    pid_a = 0
    sid_a = 0
    sid_b = 0
    for pid, sid in p2s.items():
        if sid_a <= 0:
            pid_a, sid_a = int(pid), int(sid)
        elif int(sid) != sid_a:
            sid_b = int(sid)
            break
    assert pid_a > 0 and sid_a > 0 and sid_b > 0
    before = get_hierarchy(rt, pid_a)
    re = reassign_province_membership(rt, pid_a, sid_b)
    after = get_hierarchy(rt, pid_a)
    cr = create_state_membership(rt, [pid_a], "Pure Test Enclave", after.get("region_id") or 0, after.get("super_region_id") or 0)
    new_sid = int(cr.get("state_id") or 0)
    tr = transfer_state_membership(rt, new_sid, sid_b)
    ok = (
        bool(re.get("ok"))
        and int(after.get("state_id") or 0) == sid_b
        and int(before.get("state_id") or 0) == sid_a
        and sid_a != sid_b
        and bool(cr.get("ok"))
        and bool(tr.get("ok"))
        and rt["membership_reapply_on_year_tick"] is False
    )
    return {
        "ok": ok,
        "pid": pid_a,
        "from_state": sid_a,
        "to_state": sid_b,
        "before": before,
        "after_reassign": after,
        "create": {"state_id": new_sid, "ok": cr.get("ok")},
        "transfer": {"ok": tr.get("ok"), "province_n": tr.get("province_n")},
        "mutation_count": rt["membership_live_mutation_count"],
        "summary": "World membership mutation %s · pid %s %s→%s"
        % ("PASS" if ok else "FAIL", pid_a, sid_a, sid_b),
    }


def membership_save_roundtrip(rt: Dict[str, Any]) -> Dict[str, Any]:
    """Pure mirror of ScenarioLoader get/apply membership save data."""
    p2s = {str(k): int(v) for k, v in rt["province_state_by_id"].items()}
    p2r = {str(k): int(v) for k, v in rt["province_region_by_id"].items()}
    p2sr = {str(k): int(v) for k, v in rt["province_super_by_id"].items()}
    names = {str(k): str(v) for k, v in (rt.get("province_state_names") or {}).items()}
    blob = {
        "version": 1,
        "live": True,
        "mutation_count": int(rt.get("membership_live_mutation_count") or 0),
        "province_to_state": p2s,
        "province_to_region": p2r,
        "province_to_super_region": p2sr,
        "state_names": names,
        "reapply_on_year_tick": False,
    }
    # Restore into fresh runtime
    rt2 = {
        "province_state_by_id": {int(k): int(v) for k, v in p2s.items()},
        "province_region_by_id": {int(k): int(v) for k, v in p2r.items()},
        "province_super_by_id": {int(k): int(v) for k, v in p2sr.items()},
        "province_state_names": {int(k): str(v) for k, v in names.items()},
        "membership_live_mutation_count": blob["mutation_count"],
        "membership_reapply_on_year_tick": False,
    }
    ok = rt2["province_state_by_id"] == rt["province_state_by_id"]
    return {"ok": ok, "bound": len(rt2["province_state_by_id"]), "mutation_count": blob["mutation_count"]}


def peace_annex_membership(rt: Dict[str, Any], province_id: int, winner_tag: str = "GER") -> Dict[str, Any]:
    """Peace annex creates a winner occupation state for the province (mirrors GameData)."""
    h = get_hierarchy(rt, province_id)
    cr = create_state_membership(
        rt,
        [int(province_id)],
        "%s Occupied Zone" % winner_tag,
        int(h.get("region_id") or 0),
        int(h.get("super_region_id") or 0),
    )
    after = get_hierarchy(rt, province_id)
    ok = bool(cr.get("ok")) and int(after.get("state_id") or 0) == int(cr.get("state_id") or 0)
    return {
        "ok": ok,
        "create": cr,
        "after": after,
        "winner_tag": winner_tag,
        "province_id": int(province_id),
    }


def live_membership_integrity() -> Dict[str, Any]:
    pol = agency_policy_ok()
    # Extend policy checks for saveload + peace wiring
    sl = (ROOT / "scripts" / "core" / "ScenarioLoader.gd").read_text(encoding="utf-8")
    gd = (ROOT / "scripts" / "autoload" / "GameData.gd").read_text(encoding="utf-8")
    pol["saveload_api"] = "get_membership_save_data" in sl and "apply_membership_save_data" in sl
    pol["gamedata_saveload"] = "hierarchy_membership_live" in gd and "apply_membership_save_data" in gd
    pol["peace_membership"] = "membership_create_state" in gd or "Occupied Zone" in gd
    pol["ok"] = bool(pol.get("ok")) and pol["saveload_api"] and pol["gamedata_saveload"] and pol["peace_membership"]
    ex = exercise_world_full_mutation(1936)
    xfer = exercise_cross_region_transfer(1936)
    snap = load_membership_snapshot(WORLD, 1936)
    rt = snapshot_to_runtime(snap)
    pid = next(iter(rt["province_state_by_id"].keys()))
    reassign_province_membership(rt, pid, next(s for p, s in rt["province_state_by_id"].items() if int(s) != int(rt["province_state_by_id"][pid])))
    pe = peace_annex_membership(rt, pid, "GER")
    save_rt = membership_save_roundtrip(rt)
    ok = bool(pol.get("ok")) and bool(ex.get("ok")) and bool(xfer.get("ok")) and bool(pe.get("ok")) and bool(save_rt.get("ok"))
    return {
        "ok": ok,
        "policy": pol,
        "exercise": ex,
        "cross_region_transfer": xfer,
        "peace_annex": pe,
        "save_roundtrip": save_rt,
        "summary": "Live membership product %s · cross-region %s · peace %s · saveload %s"
        % (
            "PASS" if ok else "FAIL",
            "ok" if xfer.get("ok") else "FAIL",
            "ok" if pe.get("ok") else "FAIL",
            "ok" if save_rt.get("ok") else "FAIL",
        ),
        "empty": False,
        "integration": ["membership_live", "four_tier", "player_agency", "peace", "saveload", "world_class_map"],
    }
