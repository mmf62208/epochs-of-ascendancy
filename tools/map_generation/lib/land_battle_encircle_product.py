"""Encirclement + pocket supply SOT for multi-day land battles.

A side is connected if own-land BFS reaches capital.
Encircled = no path. Pocket = encircled and no friendly land neighbor.
Supply: 1.0 connected, 0.75 thin corridor (1 friend neighbor), 0.40 encircled, 0.15 pocket.
"""
from __future__ import annotations

from collections import deque
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Sequence, Set

ROOT = Path(__file__).resolve().parents[3]
BM_GD = ROOT / "scripts" / "combat" / "BattleManager.gd"
BUBBLE_GD = ROOT / "scripts" / "map" / "LandBattleBubbleLayer.gd"
STRIP_GD = ROOT / "scripts" / "ui" / "UnitCardCombatStrip.gd"

SUPPLY_CONNECTED = 1.0
SUPPLY_THIN = 0.75
SUPPLY_ENCIRCLED = 0.40
SUPPLY_POCKET = 0.15
ORG_DRAIN_ENC = 0.08
ORG_DRAIN_POCKET = 0.14


def friendly_neighbor_count(pid: int, tag: str, adj: Mapping[int, Sequence[int]], owner: Mapping[int, str]) -> int:
    t = str(tag or "").strip().upper()
    n = 0
    for nb in adj.get(int(pid), []):
        if str(owner.get(int(nb), "")).strip().upper() == t:
            n += 1
    return n


def has_own_path(
    start: int,
    goal: int,
    tag: str,
    adj: Mapping[int, Sequence[int]],
    owner: Mapping[int, str],
    *,
    limit: int = 40,
) -> bool:
    t = str(tag or "").strip().upper()
    if int(start) == int(goal):
        return True
    q: deque = deque([int(start)])
    seen: Set[int] = {int(start)}
    hops = {int(start): 0}
    while q:
        cur = q.popleft()
        if hops[cur] >= limit:
            continue
        for nb in adj.get(cur, []):
            xi = int(nb)
            if xi in seen:
                continue
            if str(owner.get(xi, "")).strip().upper() != t:
                continue
            if xi == int(goal):
                return True
            seen.add(xi)
            hops[xi] = hops[cur] + 1
            q.append(xi)
    return False


def supply_state(
    *,
    pid: int,
    tag: str,
    capital: int,
    adj: Mapping[int, Sequence[int]],
    owner: Mapping[int, str],
) -> Dict[str, Any]:
    friends = friendly_neighbor_count(pid, tag, adj, owner)
    at_capital = capital > 0 and int(pid) == int(capital)
    connected = at_capital or (capital > 0 and has_own_path(pid, capital, tag, adj, owner))
    if capital <= 0:
        connected = friends > 0
    pocket = (not connected) and friends == 0
    encircled = (not connected) or pocket
    if pocket:
        supply = SUPPLY_POCKET
        kind = "pocket"
    elif not connected:
        supply = SUPPLY_ENCIRCLED
        kind = "encircled"
    elif at_capital or friends >= 2:
        supply = SUPPLY_CONNECTED
        kind = "connected"
        encircled = False
    elif friends <= 1:
        supply = SUPPLY_THIN
        kind = "thin"
        encircled = False
    else:
        supply = SUPPLY_CONNECTED
        kind = "connected"
        encircled = False
    return {
        "encircled": bool(encircled),
        "pocket": bool(pocket),
        "kind": kind,
        "supply": float(supply),
        "friends": friends,
    }


def org_drain_extra(kind: str) -> float:
    if kind == "pocket":
        return ORG_DRAIN_POCKET
    if kind == "encircled":
        return ORG_DRAIN_ENC
    return 0.0


def build_land_battle_encircle_product() -> Dict[str, Any]:
    passes: List[str] = []
    fails: List[str] = []
    # Synthetic: C=1 capital GER, A=2 GER, P=3 GER pocket (only FRA neighbors), F=4 FRA
    adj = {
        1: [2],
        2: [1, 4],
        3: [4],
        4: [2, 3],
    }
    owner = {1: "GER", 2: "GER", 3: "GER", 4: "FRA"}
    cap = supply_state(pid=1, tag="GER", capital=1, adj=adj, owner=owner)
    front = supply_state(pid=2, tag="GER", capital=1, adj=adj, owner=owner)
    pocket = supply_state(pid=3, tag="GER", capital=1, adj=adj, owner=owner)
    if cap["kind"] == "connected" and cap["supply"] == SUPPLY_CONNECTED:
        passes.append("capital_connected")
    else:
        fails.append("capital_connected")
    if front["kind"] == "thin" and front["supply"] == SUPPLY_THIN:
        passes.append("corridor_thin")
    else:
        fails.append("corridor_thin")
    if pocket["pocket"] and pocket["supply"] == SUPPLY_POCKET and org_drain_extra("pocket") > org_drain_extra("encircled"):
        passes.append("pocket_starves")
    else:
        fails.append("pocket_starves")
    if org_drain_extra("connected") == 0.0:
        passes.append("connected_no_extra_drain")
    else:
        fails.append("connected_no_extra_drain")

    bm = BM_GD.read_text(encoding="utf-8") if BM_GD.is_file() else ""
    bub = BUBBLE_GD.read_text(encoding="utf-8") if BUBBLE_GD.is_file() else ""
    strip = STRIP_GD.read_text(encoding="utf-8") if STRIP_GD.is_file() else ""
    if "func _land_side_supply_state" in bm or "func land_side_supply_state" in bm:
        passes.append("bm_supply_state")
    else:
        fails.append("bm_supply_state")
    if "enc_att" in bm and "supply_att" in bm:
        passes.append("bm_stores_supply")
    else:
        fails.append("bm_stores_supply")
    if "ENC" in bub or "encircled" in bub.lower():
        passes.append("bubble_enc")
    else:
        fails.append("bubble_enc")
    if "Supply" in strip or "encircled" in strip.lower() or "last_supply" in strip:
        passes.append("card_supply")
    else:
        fails.append("card_supply")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
        "pass": passes,
        "fail": fails,
        "summary": "land_battle_encircle · %s · pass=%d fail=%d"
        % ("PASS" if ok else "FAIL", len(passes), len(fails)),
        "policy": "own_path_to_capital_or_pocket_starves",
        "fixtures": {"capital": cap, "front": front, "pocket": pocket},
    }


def land_battle_encircle_integrity() -> Dict[str, Any]:
    p = build_land_battle_encircle_product()
    return {
        "ok": bool(p.get("ok")),
        "status": p.get("status"),
        "fail": list(p.get("fail") or []),
        "summary": p.get("summary"),
    }
