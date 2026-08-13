#!/usr/bin/env python3
"""Assign approximate 1936 political ownership for provinces_world_full.

Produces a deterministic owner_tag map for land provinces (≥95% coverage),
keeps sea/strait/lake unowned, seeds scenario capitals, and applies theater
bias so majors are not piled on one continent.

Usage:
  python3 tools/map_generation/scripts/assign_world_ownership_1936.py \\
      --dir data/provinces_world_full --scenario data/scenarios/world_full.json --write
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple

ROOT = Path(__file__).resolve().parents[3]

WATER_DOMAINS = frozenset({"sea", "strait", "lake"})

# Capitals: real named province ids on the world_full board (validated against base).
# NLD/BEL use Low Countries proxies where exact city tiles are missing.
DEFAULT_CAPITALS: Dict[str, int] = {
    "GER": 9287,  # Berlin
    "FRA": 9281,  # Paris
    "ENG": 9275,  # London
    "USA": 40005,  # Washington DC Theater
    "SOV": 9269,  # Moscow
    "ITA": 21,  # Rome
    "JAP": 20061,  # Tokyo Theater
    "POL": 19,  # Warsaw
    "FIN": 9221,  # Helsinki
    "NOR": 9042,  # Oslo
    "SWE": 9074,  # Stockholm
    "DNK": 9357,  # Copenhagen
    "NLD": 9302,  # Rotterdam
    "BEL": 9277,  # Lille (Flanders edge proxy)
}

# Theater → eligible owners (sphere of influence, approximate 1936 play map).
THEATER_TAGS: Dict[str, List[str]] = {
    "europe_core": [
        "GER",
        "FRA",
        "ENG",
        "SOV",
        "ITA",
        "POL",
        "FIN",
        "NOR",
        "SWE",
        "DNK",
        "NLD",
        "BEL",
    ],
    "mena_africa": ["ENG", "FRA", "ITA", "SOV"],
    "africa": ["ENG", "FRA", "ITA", "BEL"],
    "far_east": ["JAP", "SOV", "ENG", "USA", "FRA"],
    "north_america": ["USA", "ENG"],
    "south_america": ["USA", "ENG", "FRA"],
    "central_asia": ["SOV", "ENG"],
    "pacific": ["JAP", "USA", "ENG"],
    "oceania": ["ENG", "USA"],
    "sea": [],
}

MAJORS = ("GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP")

# Preferred theater weight for major bias checks / seed boosts.
MAJOR_HOME_THEATERS: Dict[str, Set[str]] = {
    "GER": {"europe_core"},
    "FRA": {"europe_core", "mena_africa", "africa"},
    "ENG": {"europe_core", "mena_africa", "africa", "far_east", "oceania", "pacific"},
    "USA": {"north_america", "pacific", "far_east"},
    "SOV": {"europe_core", "central_asia", "far_east"},
    "ITA": {"europe_core", "mena_africa", "africa"},
    "JAP": {"far_east", "pacific"},
}

# Extra anchor province ids (named cities) so Voronoi spheres are multi-polar, not one capital per continent.
EXTRA_ANCHORS: Dict[str, List[int]] = {
    "GER": [3, 9287],  # Ruhr + Berlin
    "FRA": [9281, 9364, 9194],  # Paris, Marseille, Bordeaux
    "ENG": [9275, 9424],  # London, Liverpool
    "SOV": [9269, 9167, 9067],  # Moscow, Kiev, Odessa
    "ITA": [21, 9245],  # Rome, Milan
    "USA": [40005, 40000],  # Washington, New York
    "JAP": [20061, 20063],  # Tokyo, Seoul theater
    "POL": [19],
    "FIN": [9221],
    "NOR": [9042],
    "SWE": [9074],
    "DNK": [9357],
    "NLD": [9302, 9298],  # Rotterdam, Haarlem
    "BEL": [9277, 9278],  # Lille, Charleville
    # Colonial / overseas anchors
    "ENG_OVERSEAS": [20000, 20055, 20074, 20054],  # Cairo, Singapore, Sydney, Manila-adjacent ENG sphere
    "FRA_OVERSEAS": [9049, 20000],  # Algiers (+ Cairo shared pressure)
    "ITA_OVERSEAS": [9035],  # Tunis
}


def centroid(points: Sequence[Sequence[float]]) -> Tuple[float, float]:
    if not points:
        return 0.0, 0.0
    return (
        sum(float(p[0]) for p in points) / len(points),
        sum(float(p[1]) for p in points) / len(points),
    )


def is_water(prov: Dict[str, Any]) -> bool:
    return str(prov.get("domain") or "land") in WATER_DOMAINS


def load_provinces(data_dir: Path) -> Tuple[List[Dict[str, Any]], Dict[int, Tuple[float, float]]]:
    base = json.loads((data_dir / "provinces_base.json").read_text(encoding="utf-8"))
    geom = json.loads((data_dir / "provinces_geometry.json").read_text(encoding="utf-8"))
    provinces = list(base["provinces"])
    cents: Dict[int, Tuple[float, float]] = {}
    for g in geom["provinces"]:
        cents[int(g["id"])] = centroid(g.get("points") or [])
    return provinces, cents


def assign_ownership(
    provinces: List[Dict[str, Any]],
    centroids: Dict[int, Tuple[float, float]],
    capitals: Dict[str, int],
    tags: Sequence[str],
) -> Dict[str, Any]:
    """Return ownership map id(str)->owner_tag and quality stats.

    Pure: does not write files. Water → empty owner. Land → tag from nearest
    eligible capital (theater-filtered), with capital seeds forced.
    """
    tag_set = {str(t).strip().upper() for t in tags if str(t).strip()}
    caps = {str(k).upper(): int(v) for k, v in capitals.items() if str(k).upper() in tag_set}

    # Validate capitals exist and are land
    by_id = {int(p["id"]): p for p in provinces}
    for tag, pid in list(caps.items()):
        if pid not in by_id or is_water(by_id[pid]):
            raise ValueError(f"Capital for {tag} id={pid} missing or water")

    # Multi-anchor points per tag (capitals + EXTRA_ANCHORS that exist on this board).
    anchors: Dict[str, List[Tuple[float, float]]] = {}
    for tag, pid in caps.items():
        pts: List[Tuple[float, float]] = [centroids.get(pid, (0.0, 0.0))]
        for aid in EXTRA_ANCHORS.get(tag, []):
            if aid in by_id and not is_water(by_id[aid]):
                pts.append(centroids.get(aid, (0.0, 0.0)))
        anchors[tag] = pts

    # Overseas colonial anchors attached to majors for non-europe theaters
    overseas_map = {
        "ENG": EXTRA_ANCHORS.get("ENG_OVERSEAS", []),
        "FRA": EXTRA_ANCHORS.get("FRA_OVERSEAS", []),
        "ITA": EXTRA_ANCHORS.get("ITA_OVERSEAS", []),
    }
    for tag, aids in overseas_map.items():
        if tag not in anchors:
            continue
        for aid in aids:
            if aid in by_id and not is_water(by_id[aid]):
                anchors[tag].append(centroids.get(aid, (0.0, 0.0)))

    owners: Dict[int, str] = {}
    # Force capitals first (never overwritten by secondary anchors).
    capital_pids = set(caps.values())
    for tag, pid in caps.items():
        owners[pid] = tag
    # Force extra land anchors to their tag when eligible and not another capital
    for tag, aids in EXTRA_ANCHORS.items():
        if tag.endswith("_OVERSEAS"):
            continue
        if tag not in caps:
            continue
        for aid in aids:
            if aid in capital_pids and caps.get(tag) != aid:
                continue
            if aid in by_id and not is_water(by_id[aid]):
                owners[aid] = tag

    land_ids = [int(p["id"]) for p in provinces if not is_water(p)]
    water_ids = [int(p["id"]) for p in provinces if is_water(p)]

    def nearest_tag(cx: float, cy: float, eligible: List[str], theater: str) -> str:
        best_tag = eligible[0]
        best_d = float("inf")
        for tag in eligible:
            for tx, ty in anchors.get(tag, []):
                mult = 0.80 if theater in MAJOR_HOME_THEATERS.get(tag, set()) else 1.0
                # Prevent ITA/JAP runaway: slight penalty when far from home theaters
                if tag == "ITA" and theater in ("africa", "mena_africa"):
                    mult *= 1.15
                if tag == "JAP" and theater not in ("far_east", "pacific"):
                    mult *= 1.25
                d = ((cx - tx) ** 2 + (cy - ty) ** 2) * mult
                if d < best_d:
                    best_d = d
                    best_tag = tag
        return best_tag

    for p in provinces:
        pid = int(p["id"])
        if pid in owners:
            continue
        if is_water(p):
            owners[pid] = ""
            continue
        theater = str(p.get("theater") or "europe_core")
        eligible = [t for t in (THEATER_TAGS.get(theater) or list(tag_set)) if t in caps]
        if not eligible:
            eligible = [t for t in tag_set if t in caps]
        cx, cy = centroids.get(pid, (0.0, 0.0))
        owners[pid] = nearest_tag(cx, cy, eligible, theater)

    # Europe-core rebalance: re-assign only europe_core land among Europe-eligible tags
    # using multi-anchors (stops ENG/ITA runaway on the densest theater).
    europe_tags = [t for t in (THEATER_TAGS.get("europe_core") or []) if t in caps]
    for pid in land_ids:
        p = by_id[pid]
        if str(p.get("theater") or "") != "europe_core":
            continue
        if pid in caps.values():
            continue
        cx, cy = centroids.get(pid, (0.0, 0.0))
        owners[pid] = nearest_tag(cx, cy, europe_tags, "europe_core")

    # Central Asia: prefer SOV strongly
    if "SOV" in caps:
        for pid in land_ids:
            p = by_id[pid]
            if str(p.get("theater") or "") != "central_asia":
                continue
            if pid == caps.get("SOV"):
                continue
            cx, cy = centroids.get(pid, (0.0, 0.0))
            # Only SOV/ENG eligible; weight SOV
            best = "SOV"
            best_d = float("inf")
            for tag in ("SOV", "ENG"):
                if tag not in anchors:
                    continue
                for tx, ty in anchors[tag]:
                    mult = 0.55 if tag == "SOV" else 1.35
                    d = ((cx - tx) ** 2 + (cy - ty) ** 2) * mult
                    if d < best_d:
                        best_d = d
                        best = tag
            owners[pid] = best

    # Far East: give JAP plurality, not ENG monopoly
    if "JAP" in caps:
        for pid in land_ids:
            p = by_id[pid]
            if str(p.get("theater") or "") != "far_east":
                continue
            cx, cy = centroids.get(pid, (0.0, 0.0))
            eligible_fe = [t for t in (THEATER_TAGS.get("far_east") or []) if t in caps]
            best = "JAP"
            best_d = float("inf")
            for tag in eligible_fe:
                for tx, ty in anchors.get(tag, []):
                    mult = 0.65 if tag == "JAP" else (0.9 if tag == "SOV" else 1.2)
                    d = ((cx - tx) ** 2 + (cy - ty) ** 2) * mult
                    if d < best_d:
                        best_d = d
                        best = tag
            owners[pid] = best

    # Ensure majors have ≥5 land by stealing nearest land in home theaters
    land_by_tag: Dict[str, List[int]] = {t: [] for t in tag_set}
    for pid, tag in owners.items():
        if tag and not is_water(by_id[pid]):
            land_by_tag.setdefault(tag, []).append(pid)

    for major in MAJORS:
        if major not in tag_set:
            continue
        need = 5 - len(land_by_tag.get(major, []))
        if need <= 0:
            continue
        home = MAJOR_HOME_THEATERS.get(major, {"europe_core"})
        ax = anchors.get(major) or [(0.0, 0.0)]
        mx, my = ax[0]
        candidates: List[Tuple[float, int]] = []
        for pid in land_ids:
            if owners.get(pid) == major:
                continue
            p = by_id[pid]
            if str(p.get("theater") or "") not in home:
                continue
            cur = owners.get(pid, "")
            if cur in MAJORS and len(land_by_tag.get(cur, [])) <= 5:
                continue
            if cur in caps and pid == caps[cur]:
                continue
            cx, cy = centroids.get(pid, (0.0, 0.0))
            candidates.append(((cx - mx) ** 2 + (cy - my) ** 2, pid))
        candidates.sort()
        for _, pid in candidates[: max(0, need)]:
            old = owners.get(pid, "")
            if old in land_by_tag and pid in land_by_tag[old]:
                land_by_tag[old].remove(pid)
            owners[pid] = major
            land_by_tag.setdefault(major, []).append(pid)

    def _recompute_land_by_tag() -> Dict[str, List[int]]:
        m: Dict[str, List[int]] = {t: [] for t in tag_set}
        for pid, tag in owners.items():
            if tag and not is_water(by_id[pid]):
                m.setdefault(tag, []).append(pid)
        return m

    land_by_tag = _recompute_land_by_tag()

    # Floor targets so majors look like real powers on large boards (skip tiny fixtures).
    FLOOR_TARGETS: Dict[str, int] = {
        "GER": 55,
        "FRA": 50,
        "ENG": 40,
        "SOV": 55,
        "ITA": 35,
        "POL": 12,
        "USA": 80,  # mostly NA already
        "JAP": 80,
    }
    if len(land_ids) >= 200:
        for tag, floor in FLOOR_TARGETS.items():
            if tag not in caps:
                continue
            land_by_tag = _recompute_land_by_tag()
            have = len(land_by_tag.get(tag, []))
            need = floor - have
            if need <= 0:
                continue
            home = MAJOR_HOME_THEATERS.get(tag, {"europe_core"})
            mx, my = (anchors.get(tag) or [(0.0, 0.0)])[0]
            cands2: List[Tuple[float, int]] = []
            for pid in land_ids:
                if owners.get(pid) == tag:
                    continue
                th = str(by_id[pid].get("theater") or "")
                if th not in home and tag not in ("USA", "JAP", "ENG"):
                    continue
                cur = owners.get(pid, "")
                if cur in caps and pid == caps[cur]:
                    continue
                if cur in FLOOR_TARGETS and len(land_by_tag.get(cur, [])) <= FLOOR_TARGETS[cur]:
                    continue
                if cur in MAJORS and len(land_by_tag.get(cur, [])) <= 5:
                    continue
                cx, cy = centroids.get(pid, (0.0, 0.0))
                dmin = min(
                    (cx - tx) ** 2 + (cy - ty) ** 2 for tx, ty in (anchors.get(tag) or [(mx, my)])
                )
                cands2.append((dmin, pid))
            cands2.sort()
            for _, pid in cands2[:need]:
                owners[pid] = tag

    land_by_tag = _recompute_land_by_tag()

    # Minors with capital must keep ≥3 europe land when possible (playable minors)
    if len(land_ids) >= 200:
        for minor in ("POL", "FIN", "NOR", "SWE", "DNK", "NLD", "BEL"):
            if minor not in caps:
                continue
            land_by_tag = _recompute_land_by_tag()
            have = len(
                [
                    pid
                    for pid in land_by_tag.get(minor, [])
                    if str(by_id[pid].get("theater")) == "europe_core"
                ]
            )
            need = 3 - have
            if need <= 0:
                continue
            mx, my = (anchors.get(minor) or [(0.0, 0.0)])[0]
            cands: List[Tuple[float, int]] = []
            for pid in land_ids:
                if str(by_id[pid].get("theater")) != "europe_core":
                    continue
                cur = owners.get(pid, "")
                if cur == minor or (cur in caps and pid == caps[cur]):
                    continue
                if cur in FLOOR_TARGETS and len(land_by_tag.get(cur, [])) <= FLOOR_TARGETS[cur]:
                    continue
                if cur in MAJORS and len(land_by_tag.get(cur, [])) <= 8:
                    continue
                cx, cy = centroids.get(pid, (0.0, 0.0))
                cands.append(((cx - mx) ** 2 + (cy - my) ** 2, pid))
            cands.sort()
            for _, pid in cands[:need]:
                owners[pid] = minor

    # Recompute counts
    land_owned = sum(1 for pid in land_ids if owners.get(pid))
    water_owned = sum(1 for pid in water_ids if owners.get(pid))
    by_tag_land: Dict[str, int] = {}
    theater_tag_land: Dict[str, Dict[str, int]] = {}
    for pid in land_ids:
        tag = owners.get(pid) or ""
        if not tag:
            continue
        by_tag_land[tag] = by_tag_land.get(tag, 0) + 1
        th = str(by_id[pid].get("theater") or "")
        theater_tag_land.setdefault(th, {})
        theater_tag_land[th][tag] = theater_tag_land[th].get(tag, 0) + 1

    land_cov = land_owned / max(1, len(land_ids))
    return {
        "owners": {str(k): v for k, v in owners.items()},
        "capitals": caps,
        "stats": {
            "province_count": len(provinces),
            "land_count": len(land_ids),
            "water_count": len(water_ids),
            "land_owned": land_owned,
            "land_coverage": land_cov,
            "water_owned": water_owned,
            "by_tag_land": by_tag_land,
            "theater_tag_land": theater_tag_land,
        },
    }


def quality_gates(result: Dict[str, Any], tags: Sequence[str], provinces: List[Dict[str, Any]]) -> Dict[str, Any]:
    stats = result["stats"]
    owners = result["owners"]
    caps = result["capitals"]
    by_id = {int(p["id"]): p for p in provinces}
    tag_set = {str(t).upper() for t in tags}

    capital_ok = all(owners.get(str(caps[t])) == t for t in caps if t in tag_set)
    # Every scenario tag ≥1 land; majors ≥5
    every_tag = all(stats["by_tag_land"].get(t, 0) >= 1 for t in tag_set)
    majors_ok = all(stats["by_tag_land"].get(m, 0) >= 5 for m in MAJORS if m in tag_set)

    # Theater bias: primary home theater should hold plurality or solid share for each major
    bias_ok = True
    bias_detail: Dict[str, Any] = {}
    for m in MAJORS:
        if m not in tag_set:
            continue
        homes = MAJOR_HOME_THEATERS.get(m, set())
        home_count = 0
        total = stats["by_tag_land"].get(m, 0)
        for th in homes:
            home_count += stats["theater_tag_land"].get(th, {}).get(m, 0)
        share = home_count / max(1, total)
        bias_detail[m] = {"home_count": home_count, "total": total, "home_share": share}
        if total >= 5 and share < 0.35:
            bias_ok = False

    water_clean = stats["water_owned"] == 0
    land_cov_ok = stats["land_coverage"] >= 0.95

    return {
        "land_coverage_ok": land_cov_ok,
        "land_coverage": stats["land_coverage"],
        "water_unowned_ok": water_clean,
        "water_owned": stats["water_owned"],
        "capitals_ok": capital_ok,
        "every_tag_has_land": every_tag,
        "majors_ge_5": majors_ok,
        "theater_bias_ok": bias_ok,
        "bias_detail": bias_detail,
        "by_tag_land": stats["by_tag_land"],
        "pass": land_cov_ok
        and water_clean
        and capital_ok
        and every_tag
        and majors_ok
        and bias_ok,
    }


def build_scenario_province_overrides(
    owners: Dict[str, str],
    provinces: List[Dict[str, Any]],
    capitals: Dict[str, int],
) -> List[Dict[str, Any]]:
    """ScenarioLoader expects an array of {id, owner_tag, ...} overrides."""
    by_id = {int(p["id"]): p for p in provinces}
    cap_ids = set(capitals.values())
    out: List[Dict[str, Any]] = []
    for pid_s, tag in sorted(owners.items(), key=lambda kv: int(kv[0])):
        pid = int(pid_s)
        p = by_id.get(pid)
        if p is None:
            continue
        if is_water(p):
            # Explicit empty for documentation; loader can set empty
            continue
        if not tag:
            continue
        entry: Dict[str, Any] = {
            "id": pid,
            "owner_tag": tag,
            "controller_tag": tag,
        }
        if pid in cap_ids:
            entry["special_features"] = ["capital"]
            entry["victory_points"] = 20
            entry["development_level"] = 5
            entry["infrastructure"] = 4
            entry["factories"] = 3
        else:
            # Light defaults for playability (factories only on denser/home-ish tiles)
            pop = int(p.get("population_base") or 0)
            if pop >= 500000 or p.get("hotspot_densify"):
                entry["factories"] = 1
                entry["development_level"] = 2
                entry["infrastructure"] = 2
        out.append(entry)
    return out


def apply_to_scenario(
    scenario_path: Path,
    overrides: List[Dict[str, Any]],
    capitals: Dict[str, int],
) -> Dict[str, Any]:
    scen = json.loads(scenario_path.read_text(encoding="utf-8"))
    scen["provinces"] = overrides
    # Fix capital_province_id + key_provinces on countries
    for c in scen.get("countries") or []:
        tag = str(c.get("tag") or "").upper()
        if tag in capitals:
            c["capital_province_id"] = capitals[tag]
            c["key_provinces"] = [capitals[tag]]
    return scen


def run(
    data_dir: Path,
    scenario_path: Path,
    write: bool = False,
    write_payload: bool = True,
) -> Dict[str, Any]:
    provinces, cents = load_provinces(data_dir)
    scen = json.loads(scenario_path.read_text(encoding="utf-8"))
    tags = [str(c["tag"]).upper() for c in scen.get("countries") or []]
    # Prefer capitals from DEFAULT that exist; allow scenario to override later
    capitals = dict(DEFAULT_CAPITALS)
    # Drop tags not in scenario
    capitals = {t: pid for t, pid in capitals.items() if t in tags}

    result = assign_ownership(provinces, cents, capitals, tags)
    gates = quality_gates(result, tags, provinces)
    overrides = build_scenario_province_overrides(
        result["owners"], provinces, result["capitals"]
    )
    payload = {
        "meta": {
            "source": "assign_world_ownership_1936.py",
            "geometry_space": "world",
            "notes": "Approximate 1936 spheres for playability; sea unowned; capitals forced.",
            "water_owned_exceptions": [],
        },
        "capitals": result["capitals"],
        "owners": result["owners"],
        "stats": result["stats"],
        "gates": gates,
    }

    out: Dict[str, Any] = {
        "stats": result["stats"],
        "gates": gates,
        "override_count": len(overrides),
        "capitals": result["capitals"],
        "wrote": False,
    }

    if write:
        if write_payload:
            pay_path = data_dir / "province_ownership_1936.json"
            # Compact owners for size: only non-empty land entries
            compact_owners = {k: v for k, v in result["owners"].items() if v}
            payload["owners"] = compact_owners
            pay_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            out["payload_path"] = str(pay_path)

        scen_out = apply_to_scenario(scenario_path, overrides, result["capitals"])
        scenario_path.write_text(json.dumps(scen_out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        out["scenario_path"] = str(scenario_path)
        out["wrote"] = True

    return out


def main(argv: Optional[Sequence[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", default="data/provinces_world_full")
    ap.add_argument("--scenario", default="data/scenarios/world_full.json")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)
    data_dir = Path(args.dir)
    if not data_dir.is_absolute():
        data_dir = ROOT / data_dir
    scen = Path(args.scenario)
    if not scen.is_absolute():
        scen = ROOT / scen
    write = bool(args.write) and not args.dry_run
    out = run(data_dir, scen, write=write)
    print(("[WROTE]" if write else "[DRY-RUN]"), {k: out[k] for k in out if k != "gates"})
    print("gates:", out["gates"])
    ok = bool(out["gates"].get("pass"))
    print("PASS world ownership" if ok else "FAIL world ownership", file=sys.stdout if ok else sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
