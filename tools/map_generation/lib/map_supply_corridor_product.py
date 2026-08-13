"""M4 — supply corridor path product (pure).

BFS land path on province adjacency, optional owner filter and infra-aware
edge cost (prefer high infrastructure). Used to gate hub/capital → front
corridor readability on the accurate board.
"""
from __future__ import annotations

import heapq
import json
from collections import deque
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence, Set, Tuple

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"
DEFAULT_SCENARIO = ROOT / "data" / "scenarios" / "world_accurate.json"

WATER = frozenset({"sea", "ocean", "water", "lake", "strait"})

# GER Berlin capital → Baden-Baden (Maginot-facing hub edge)
GER_CAPITAL = 710300
GER_FRONT = 710173


def _is_water(p: Mapping[str, Any]) -> bool:
    terr = str(p.get("terrain", "")).lower()
    dom = str(p.get("domain", "land")).lower()
    return terr in WATER or dom in WATER or bool(p.get("is_sea"))


def bfs_land_path(
    adj: Mapping[str, Sequence[Any]],
    start: int,
    goal: int,
    *,
    land_only: Optional[Set[int]] = None,
    limit: int = 80,
) -> Optional[List[int]]:
    """Unweighted BFS on adjacency (province hop length)."""
    if start == goal:
        return [start]
    q: deque = deque([(start, [start])])
    seen = {start}
    while q:
        n, path = q.popleft()
        if len(path) > limit:
            continue
        for x in adj.get(str(n)) or []:
            xi = int(x)
            if xi in seen:
                continue
            if land_only is not None and xi not in land_only:
                continue
            np = path + [xi]
            if xi == goal:
                return np
            seen.add(xi)
            q.append((xi, np))
    return None


def infra_weighted_path(
    adj: Mapping[str, Sequence[Any]],
    start: int,
    goal: int,
    infra_by_pid: Mapping[int, float],
    *,
    land_only: Optional[Set[int]] = None,
    limit: int = 100,
) -> Optional[List[int]]:
    """Dijkstra preferring higher infrastructure (lower edge cost).

    Edge cost = 1.0 / (1.0 + 0.08 * min(infra_to, 20)) so high-infra spines win.
    """
    if start == goal:
        return [start]
    dist: Dict[int, float] = {start: 0.0}
    prev: Dict[int, int] = {}
    heap: List[Tuple[float, int, int]] = [(0.0, 0, start)]  # cost, hops, node
    hops_at: Dict[int, int] = {start: 0}
    while heap:
        cost, hops, n = heapq.heappop(heap)
        if n == goal:
            break
        if cost > dist.get(n, 1e18) or hops >= limit:
            continue
        for x in adj.get(str(n)) or []:
            xi = int(x)
            if land_only is not None and xi not in land_only:
                continue
            inf = float(infra_by_pid.get(xi, 0.0))
            edge = 1.0 / (1.0 + 0.08 * min(inf, 20.0))
            nc = cost + edge
            nh = hops + 1
            if nc < dist.get(xi, 1e18) and nh <= limit:
                dist[xi] = nc
                prev[xi] = n
                hops_at[xi] = nh
                heapq.heappush(heap, (nc, nh, xi))
    if goal not in dist:
        return None
    path = [goal]
    cur = goal
    while cur in prev:
        cur = prev[cur]
        path.append(cur)
    path.reverse()
    return path


def path_mean_infra(path: Sequence[int], infra_by_pid: Mapping[int, float]) -> float:
    if not path:
        return 0.0
    vals = [float(infra_by_pid.get(int(p), 0.0)) for p in path]
    return sum(vals) / max(1, len(vals))


def build_supply_corridor_product(
    board_dir: str = "",
    scenario_path: str = "",
) -> Dict[str, Any]:
    d = Path(board_dir) if board_dir else DEFAULT_DIR
    sc_path = Path(scenario_path) if scenario_path else DEFAULT_SCENARIO
    fails: List[str] = []
    passes: List[str] = []

    base = {
        int(p["id"]): p
        for p in json.loads((d / "provinces_base.json").read_text(encoding="utf-8"))["provinces"]
    }
    adj = (
        json.loads((d / "province_adjacency.json").read_text(encoding="utf-8")).get("adjacency")
        or {}
    )
    own = (
        json.loads((d / "province_ownership_1936.json").read_text(encoding="utf-8")).get("owners")
        or {}
    )
    eco = (
        json.loads((d / "province_economy_layer.json").read_text(encoding="utf-8")).get("provinces")
        or {}
    )
    sc = json.loads(sc_path.read_text(encoding="utf-8")) if sc_path.is_file() else {}

    ger_land = {
        pid
        for pid, p in base.items()
        if own.get(str(pid)) == "GER" and not _is_water(p)
    }
    infra = {
        int(k): float((eco.get(str(k)) or {}).get("infrastructure") or 0)
        for k in ger_land
    }
    # also index all for weighted
    for k, v in eco.items():
        infra[int(k)] = float((v or {}).get("infrastructure") or 0)

    # Capital from scenario when present
    capital = GER_CAPITAL
    for c in sc.get("countries") or []:
        if str(c.get("tag") or "") == "GER":
            capital = int(c.get("capital_province_id") or GER_CAPITAL)
            break
    front = GER_FRONT

    bfs = bfs_land_path(adj, capital, front, land_only=ger_land, limit=40)
    weighted = infra_weighted_path(
        adj, capital, front, infra, land_only=ger_land, limit=60
    )

    if bfs and len(bfs) >= 2:
        mean_i = path_mean_infra(bfs, infra)
        passes.append("ger_bfs_len=%d" % len(bfs))
        passes.append("ger_bfs_mean_infra=%.1f" % mean_i)
    else:
        fails.append("ger_bfs_missing")

    if weighted and len(weighted) >= 2:
        mean_w = path_mean_infra(weighted, infra)
        passes.append("ger_weighted_len=%d" % len(weighted))
        passes.append("ger_weighted_mean_infra=%.1f" % mean_w)
        # Weighted should not be absurdly longer than BFS
        if bfs and len(weighted) > len(bfs) * 3:
            fails.append("weighted_too_long")
        else:
            passes.append("weighted_reasonable")
    else:
        fails.append("ger_weighted_missing")

    # Distinct from trivial self-path
    if capital == front:
        fails.append("capital_eq_front")
    else:
        passes.append("capital_ne_front")

    ok = len(fails) == 0
    return {
        "ok": ok,
        "empty": False,
        "status": "PASS" if ok else "FAIL",
        "capital": capital,
        "front": front,
        "bfs_path": bfs,
        "weighted_path": weighted,
        "bfs_len": len(bfs or []),
        "weighted_len": len(weighted or []),
        "pass": passes,
        "fail": fails,
        "summary": "Supply corridor (capital→front) %s · bfs=%s"
        % ("PASS" if ok else "FAIL", len(bfs or [])),
        "integration": [
            "map_supply_corridor_product",
            "m4",
            "supply",
            "corridor",
            "world_accurate",
        ],
    }


def supply_corridor_integrity_from_board(board_dir: str = "") -> Dict[str, Any]:
    p = build_supply_corridor_product(board_dir=board_dir)
    return {
        "ok": bool(p.get("ok")),
        "fail": p.get("fail") or [],
        "pass": p.get("pass") or [],
        "bfs_len": p.get("bfs_len"),
        "summary": p.get("summary"),
        "empty": False,
    }
