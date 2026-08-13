"""Map hierarchy scaffold: province → state → strategic region (world_full)."""
from __future__ import annotations
from pathlib import Path
from typing import Any, Dict, List, Tuple
import json
from collections import defaultdict

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DIR = ROOT / "data" / "provinces_world_full"

# Sparse theaters get fewer, larger states
DENSE_THEATERS = frozenset({"europe_core", "far_east", "north_america"})
SPARSE_THEATERS = frozenset({"central_asia", "africa", "oceania", "pacific", "south_america", "mena_africa"})

PRODUCT_STEPS = ("states", "regions", "bindings", "integrity")


def _floor(s: float, lo: float = 0.35) -> float:
    try:
        x = float(s)
    except Exception:
        x = 0.5
    if x > 2:
        x /= 100.0
    return max(lo, min(1.0, x))


def load_board(data_dir: Path = DEFAULT_DIR) -> Dict[str, Any]:
    base = json.loads((data_dir / "provinces_base.json").read_text(encoding="utf-8"))
    geom = json.loads((data_dir / "provinces_geometry.json").read_text(encoding="utf-8"))
    own_path = data_dir / "province_ownership_1936.json"
    owners = {}
    if own_path.is_file():
        owners = (json.loads(own_path.read_text(encoding="utf-8")).get("owners") or {})
    return {
        "provinces": base.get("provinces") or [],
        "geometry": geom.get("provinces") or [],
        "owners": owners,
    }


def build_hierarchy_scaffold(data_dir: Path = DEFAULT_DIR) -> Dict[str, Any]:
    """Group land provinces into states by (theater, owner), regions by theater."""
    from state_name_gazetteer import assign_state_name  # type: ignore

    board = load_board(data_dir)
    provinces = board["provinces"]
    owners = board["owners"]

    # region_id by theater name
    theaters: Dict[str, List[int]] = defaultdict(list)
    land_n = 0
    for p in provinces:
        pid = int(p["id"])
        domain = str(p.get("domain") or "land")
        if domain in ("sea", "strait", "lake"):
            continue
        land_n += 1
        th = str(p.get("theater") or "europe_core")
        theaters[th].append(pid)

    # States: bucket by theater+owner with size caps — real place names (not Area N).
    states: List[Dict[str, Any]] = []
    province_to_state: Dict[str, int] = {}
    state_id = 1
    for th, pids in sorted(theaters.items()):
        # subgroup by owner
        by_own: Dict[str, List[int]] = defaultdict(list)
        for pid in pids:
            tag = str(owners.get(str(pid)) or owners.get(pid) or "NEU").upper() or "NEU"
            by_own[tag].append(pid)
        # denser → smaller chunks
        chunk = 12 if th in DENSE_THEATERS else (28 if th in SPARSE_THEATERS else 18)
        th_name_idx = 0
        for tag, ids in sorted(by_own.items()):
            ids = sorted(ids)
            for i in range(0, len(ids), chunk):
                chunk_ids = ids[i : i + chunk]
                name = assign_state_name(th, th_name_idx, owner_hint=tag)
                th_name_idx += 1
                st = {
                    "id": state_id,
                    "name": name,
                    "theater": th,
                    "owner_hint": tag,
                    "province_ids": chunk_ids,
                    "province_n": len(chunk_ids),
                }
                states.append(st)
                for pid in chunk_ids:
                    province_to_state[str(pid)] = state_id
                state_id += 1

    # Regions: one strategic region per theater (+ split dense if huge)
    regions: List[Dict[str, Any]] = []
    province_to_region: Dict[str, int] = {}
    rid = 1
    for th, pids in sorted(theaters.items()):
        # split dense theaters into ~3 subregions by id order
        parts = 3 if th in DENSE_THEATERS and len(pids) > 80 else 1
        pids = sorted(pids)
        n = len(pids)
        for pi in range(parts):
            a = (pi * n) // parts
            b = ((pi + 1) * n) // parts
            sub = pids[a:b]
            if not sub:
                continue
            rname = th.replace("_", " ").title() if parts == 1 else "%s %d" % (th.replace("_", " ").title(), pi + 1)
            regions.append({
                "id": rid,
                "name": rname,
                "theater": th,
                "province_ids": sub,
                "province_n": len(sub),
            })
            for pid in sub:
                province_to_region[str(pid)] = rid
            rid += 1

    score = _floor(0.4 + 0.2 * min(1.0, len(states) / 200.0) + 0.2 * min(1.0, len(regions) / 20.0) + 0.2 * min(1.0, land_n / 2000.0))
    return {
        "states": states,
        "regions": regions,
        "province_to_state": province_to_state,
        "province_to_region": province_to_region,
        "land_n": land_n,
        "state_n": len(states),
        "region_n": len(regions),
        "score": score,
        "empty": False,
        "summary": "Hierarchy scaffold · land %d · states %d · regions %d · score %.2f"
        % (land_n, len(states), len(regions), score),
        "integration": ["map_hierarchy", "states", "regions", "world_class_map"],
    }


def hierarchy_integrity(data_dir: Path = DEFAULT_DIR) -> Dict[str, Any]:
    from state_name_gazetteer import assert_names_shippable  # type: ignore

    # Prefer shipped files when present (honest gate of on-disk product).
    states_path = Path(data_dir) / "province_states.json"
    if states_path.is_file():
        st = json.loads(states_path.read_text(encoding="utf-8"))
        names = [str(s.get("name", "")) for s in (st.get("states") or [])]
        name_gate = assert_names_shippable(names)
        state_n = len(names)
        hs_path = Path(data_dir) / "hierarchy_scaffold.json"
        hs = json.loads(hs_path.read_text(encoding="utf-8")) if hs_path.is_file() else {}
        p2s = hs.get("province_to_state") or {}
        region_n = int(hs.get("region_n") or 0)
        land_n = int(hs.get("land_n") or len(p2s))
        has_super = bool(hs.get("province_to_super_region"))
        ok = (
            state_n >= 40
            and region_n >= 8
            and land_n >= 1000
            and len(p2s) >= 1000
            and bool(name_gate.get("ok"))
            and has_super
        )
        return {
            "ok": ok,
            "state_n": state_n,
            "region_n": region_n,
            "land_n": land_n,
            "name_gate": name_gate,
            "has_super_bind": has_super,
            "summary": "Hierarchy integrity %s · states %s · regions %s · placeholders %s"
            % ("PASS" if ok else "FAIL", state_n, region_n, name_gate.get("placeholder_n")),
            "empty": False,
        }
    h = build_hierarchy_scaffold(data_dir)
    names = [str(s.get("name", "")) for s in (h.get("states") or [])]
    name_gate = assert_names_shippable(names)
    ok = (
        int(h.get("state_n", 0)) >= 40
        and int(h.get("region_n", 0)) >= 8
        and int(h.get("land_n", 0)) >= 1000
        and len(h.get("province_to_state") or {}) >= 1000
        and bool(name_gate.get("ok"))
    )
    return {
        "ok": ok,
        "state_n": h.get("state_n"),
        "region_n": h.get("region_n"),
        "land_n": h.get("land_n"),
        "name_gate": name_gate,
        "summary": "Hierarchy integrity %s · states %s · regions %s"
        % ("PASS" if ok else "FAIL", h.get("state_n"), h.get("region_n")),
        "empty": False,
    }


def write_hierarchy_files(data_dir: Path = DEFAULT_DIR) -> Dict[str, Any]:
    h = build_hierarchy_scaffold(data_dir)
    # Theater → super-region from shipped super_regions.json when present.
    super_by_theater: Dict[str, int] = {}
    super_path = Path(data_dir) / "super_regions.json"
    if super_path.is_file():
        sdata = json.loads(super_path.read_text(encoding="utf-8"))
        for sr in sdata.get("super_regions") or []:
            srid = int(sr.get("id") or 0)
            for th in sr.get("theaters") or []:
                super_by_theater[str(th)] = srid
    # Fallback theater map if super file missing/empty.
    if not super_by_theater:
        super_by_theater = {
            "europe_core": 1,
            "mena_africa": 2,
            "africa": 2,
            "far_east": 3,
            "central_asia": 3,
            "north_america": 4,
            "south_america": 4,
            "pacific": 5,
            "oceania": 5,
        }
    # Build province→super via province→region→theater
    region_theater = {int(r["id"]): str(r.get("theater") or "") for r in h["regions"]}
    p2super: Dict[str, int] = {}
    for pid_s, rid in (h.get("province_to_region") or {}).items():
        th = region_theater.get(int(rid), "")
        srid = int(super_by_theater.get(th) or 0)
        if srid > 0:
            p2super[str(pid_s)] = srid

    states_payload = {
        "version": 3,
        "source": "build_hierarchy_scaffold.py",
        "naming": "state_name_gazetteer",
        "states": [
            {
                "id": s["id"],
                "name": s["name"],
                "theater": s["theater"],
                "owner_hint": s["owner_hint"],
                "province_ids": s["province_ids"],
            }
            for s in h["states"]
        ],
    }
    (data_dir / "province_states.json").write_text(
        json.dumps(states_payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    # hierarchy_scaffold.json bindings
    bind = {
        "version": 2,
        "source": "map_hierarchy_product",
        "province_to_state": h["province_to_state"],
        "province_to_region": h["province_to_region"],
        "province_to_super_region": p2super,
        "state_n": h["state_n"],
        "region_n": h["region_n"],
        "super_region_n": len(set(p2super.values())),
        "land_n": h["land_n"],
        "four_tier": True,
        "sparse_rule": {
            "dense_theaters": list(DENSE_THEATERS),
            "sparse_theaters": list(SPARSE_THEATERS),
            "dense_chunk": 12,
            "sparse_chunk": 28,
        },
    }
    (data_dir / "hierarchy_scaffold.json").write_text(
        json.dumps(bind, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    # Also write strategic regions scaffold (does not delete existing curated if preferred — write side file)
    reg_payload = {
        "version": 4,
        "source": "map_hierarchy_product scaffold",
        "k": h["region_n"],
        "regions": h["regions"],
    }
    (data_dir / "strategic_regions_scaffold.json").write_text(
        json.dumps(reg_payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return {"ok": True, "state_n": h["state_n"], "region_n": h["region_n"], "land_n": h["land_n"]}
