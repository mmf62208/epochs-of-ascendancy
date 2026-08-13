"""Director multi-front map product — real major borders on world_accurate.

HOI-style campaign needs named fronts with real province edges, not abstract
west/east labels alone. Builds front rows from ownership + adjacency:

  Rhineland / Maginot (GER–FRA)
  Polish Corridor / East (GER–POL)
  Alps (FRA–ITA / GER–ITA if any)
  Baltic / East (POL–SOV)
  Asia (CHI–JAP sample)

Gates min edge counts so densify renumber does not erase playable fronts.
"""
from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_accurate"
DEFAULT_SCENARIO = ROOT / "data" / "scenarios" / "world_accurate.json"

# Canonical assault edge (D2.1)
GER_FRA_EDGE = (710173, 710739)

# Named HOI-ish fronts → (tag_a, tag_b, min_edges, must_include_edge or None)
FRONT_SPECS: List[Dict[str, Any]] = [
    {
        "id": "rhineland_maginot",
        "name": "Rhineland / Maginot",
        "theater": "west",
        "tags": ("GER", "FRA"),
        "min_edges": 8,
        "must_edge": GER_FRA_EDGE,
        "priority": 10,
    },
    {
        "id": "polish_border",
        "name": "Polish Border",
        "theater": "east",
        "tags": ("GER", "POL"),
        "min_edges": 6,
        "must_edge": None,
        "priority": 9,
    },
    {
        "id": "alps",
        "name": "Alpine Front",
        "theater": "south",
        "tags": ("FRA", "ITA"),
        "min_edges": 8,
        "must_edge": None,
        "priority": 7,
    },
    {
        "id": "baltic_east",
        "name": "Baltic / East",
        "theater": "east",
        "tags": ("POL", "SOV"),
        "min_edges": 3,
        "must_edge": None,
        "priority": 8,
    },
    {
        "id": "china_japan",
        "name": "China–Japan",
        "theater": "asia",
        "tags": ("CHI", "JAP"),
        "min_edges": 5,
        "must_edge": None,
        "priority": 6,
    },
]


def _load(board_dir: Path) -> Tuple[Dict[str, List[int]], Dict[str, str], Dict[int, dict]]:
    adj_raw = json.loads((board_dir / "province_adjacency.json").read_text(encoding="utf-8")).get(
        "adjacency"
    ) or {}
    adj: Dict[str, List[int]] = {
        str(k): [int(x) for x in (v or [])] for k, v in adj_raw.items()
    }
    own = (
        json.loads((board_dir / "province_ownership_1936.json").read_text(encoding="utf-8")).get(
            "owners"
        )
        or {}
    )
    owners = {str(k): str(v).upper() for k, v in own.items()}
    base = {
        int(p["id"]): p
        for p in json.loads((board_dir / "provinces_base.json").read_text(encoding="utf-8"))[
            "provinces"
        ]
    }
    return adj, owners, base


def collect_border_edges(
    adj: Dict[str, List[int]],
    owners: Dict[str, str],
    tag_a: str,
    tag_b: str,
) -> List[Tuple[int, int]]:
    """Undirected unique land edges between tag_a and tag_b."""
    a = str(tag_a).upper()
    b = str(tag_b).upper()
    seen = set()
    edges: List[Tuple[int, int]] = []
    for pid_s, nbrs in adj.items():
        oa = owners.get(str(pid_s), "")
        if oa not in (a, b):
            continue
        pid = int(pid_s)
        for n in nbrs:
            ob = owners.get(str(n), "")
            if ob not in (a, b) or ob == oa:
                continue
            lo, hi = (pid, int(n)) if pid < int(n) else (int(n), pid)
            key = (lo, hi)
            if key in seen:
                continue
            seen.add(key)
            edges.append(key)
    return edges


def border_provinces_for_tag(
    adj: Dict[str, List[int]],
    owners: Dict[str, str],
    tag: str,
    *,
    foreign_tags: Optional[Sequence[str]] = None,
) -> List[int]:
    """Owned land province ids that touch a foreign owner (optionally filtered)."""
    t = str(tag).upper()
    foreign = {str(x).upper() for x in (foreign_tags or [])} if foreign_tags else None
    out: List[int] = []
    for pid_s, nbrs in adj.items():
        if owners.get(str(pid_s), "") != t:
            continue
        pid = int(pid_s)
        for n in nbrs:
            ob = owners.get(str(n), "")
            if not ob or ob == t:
                continue
            if foreign is not None and ob not in foreign:
                continue
            out.append(pid)
            break
    return sorted(set(out))


def build_world_accurate_multi_front_product(
    board_dir: Optional[Path] = None,
    *,
    sample_edges_n: int = 3,
) -> Dict[str, Any]:
    """Main entry: named multi-front board from accurate ownership graph."""
    d = Path(board_dir or DEFAULT_DIR)
    adj, owners, base = _load(d)
    fails: List[str] = []
    passes: List[str] = []
    fronts: List[Dict[str, Any]] = []

    for spec in FRONT_SPECS:
        ta, tb = spec["tags"]
        edges = collect_border_edges(adj, owners, ta, tb)
        min_e = int(spec["min_edges"])
        must = spec.get("must_edge")
        samples = []
        for lo, hi in edges[: max(1, int(sample_edges_n))]:
            samples.append(
                {
                    "a": lo,
                    "b": hi,
                    "name_a": str((base.get(lo) or {}).get("name") or lo),
                    "name_b": str((base.get(hi) or {}).get("name") or hi),
                    "owner_a": owners.get(str(lo), ""),
                    "owner_b": owners.get(str(hi), ""),
                }
            )
        ok_edges = len(edges) >= min_e
        ok_must = True
        if must:
            ma, mb = int(must[0]), int(must[1])
            lo, hi = (ma, mb) if ma < mb else (mb, ma)
            ok_must = (lo, hi) in edges or any(
                (e[0] == ma and e[1] == mb) or (e[0] == mb and e[1] == ma) for e in edges
            )
            # also accept undirected membership
            ok_must = any(
                {e[0], e[1]} == {ma, mb} for e in edges
            )
        row = {
            "id": spec["id"],
            "name": spec["name"],
            "theater": spec["theater"],
            "tags": list(spec["tags"]),
            "edge_n": len(edges),
            "min_edges": min_e,
            "priority": int(spec["priority"]),
            "active": ok_edges and ok_must,
            "sample_edges": samples,
            "must_edge_ok": ok_must,
        }
        fronts.append(row)
        if ok_edges and ok_must:
            passes.append("%s edges=%d" % (spec["id"], len(edges)))
        else:
            fails.append(
                "%s edges=%d need>=%d must=%s" % (spec["id"], len(edges), min_e, ok_must)
            )

    fronts.sort(key=lambda r: (-int(r.get("priority") or 0), str(r.get("id"))))
    active_n = sum(1 for f in fronts if f.get("active"))
    if active_n < 4:
        fails.append("active_fronts=%d need>=4" % active_n)
    else:
        passes.append("active_fronts=%d" % active_n)

    # Deploy stations sample: GER capital + Rhineland border + Polish border
    ger_border_w = border_provinces_for_tag(adj, owners, "GER", foreign_tags=["FRA"])
    ger_border_e = border_provinces_for_tag(adj, owners, "GER", foreign_tags=["POL"])
    deploy = {
        "GER": {
            "west_border_n": len(ger_border_w),
            "east_border_n": len(ger_border_e),
            "west_sample": ger_border_w[:5],
            "east_sample": ger_border_e[:5],
        }
    }
    if 710173 in ger_border_w or 710173 in border_provinces_for_tag(adj, owners, "GER"):
        passes.append("ger_baden_border")
    if len(ger_border_w) >= 3:
        passes.append("ger_west_border=%d" % len(ger_border_w))
    else:
        fails.append("ger_west_border_thin=%d" % len(ger_border_w))

    ok = len(fails) == 0
    score = max(0.0, min(1.0, active_n / max(1, len(FRONT_SPECS))))
    if ok:
        score = max(score, 0.88)
    label = (
        "Accurate multi-front · active=%d/%d · GER-FRA edges=%d · %s"
        % (
            active_n,
            len(FRONT_SPECS),
            next((f["edge_n"] for f in fronts if f["id"] == "rhineland_maginot"), 0),
            "PASS" if ok else "FAIL",
        )
    )
    return {
        "ok": ok,
        "empty": False,
        "score": score,
        "status": "PASS" if ok else "FAIL",
        "fronts": fronts,
        "active_n": active_n,
        "deploy": deploy,
        "pass": passes,
        "fail": fails,
        "summary": label,
        "plain": label + ("\nFAIL: " + " | ".join(fails) if fails else ""),
        "integration": [
            "world_accurate_multi_front_product",
            "multi_front",
            "world_accurate",
            "hoi_fronts",
        ],
    }


def world_accurate_multi_front_integrity() -> Dict[str, Any]:
    p = build_world_accurate_multi_front_product()
    return {
        "ok": bool(p.get("ok")),
        "active_n": p.get("active_n"),
        "fail": p.get("fail") or [],
        "summary": p.get("summary"),
        "empty": False,
    }
