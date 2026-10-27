#!/usr/bin/env python3
"""Fold GAP-USSR-WEST + GAP-WEST-UKR baked rings onto the nation-tags board.

Cherry-pick is not used: those branches also carry Hawaii, IBS, and China ids
this tip does not have. Shapely is not installed, so this copies rings already
baked on origin/grok/gap-west-ukr (tip of #128, which includes the #126 carve
and the Belarus re-ring that carve was cut against).

Unique names land at 906100–906110. Names that #136 already has (Kiev, Odessa,
Kharkiv, Dnipropetrovsk, Crimea, Lviv, Lutsk, Chernivtsi, Chisinau) keep ids
906000–906008, owners, adm0, and population 0. Only their rings are upgraded.

In-place geometry (not owners, not names) is replaced for the parent blobs and
Belarus placeholders the carve re-ringed, plus Black Sea zones 950006, 950123,
and 950124. No new sea id. 905849–905908 and 950340–950342 are not copied.

New-province population stays 0 so a tier-2 gap city cannot enter the HWY-3
hub set (that is what zeroed the Moscow stub). Factories, infrastructure, and
development are copied. 2026 owner is UKR for the Ukrainian names and RUS for
Smolensk, Kursk, and Tula. Other eras are copied from the gap branch.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BOARD = ROOT / "data" / "provinces_world_accurate"
sys.path.insert(0, str(ROOT / "tools" / "map_generation" / "lib"))

from nation_tags1_product import GAPS, _point_in_ring  # noqa: E402
from ne_full_geometry_align import lonlat_to_canvas  # noqa: E402

# source id -> dest id. Duplicates of #136 stay on 906000–906008.
DUP = {
    905889: 906000,  # Kiev
    905894: 906001,  # Odessa
    905892: 906002,  # Kharkiv
    905893: 906003,  # Dnipropetrovsk
    905896: 906004,  # Crimean ASSR
    905900: 906005,  # Lviv
    905901: 906006,  # Lutsk
    905908: 906007,  # Chernivtsi
    905904: 906008,  # Chisinau
}
# Unique names. adm0/2026 is the modern tag, not the 1936 owner.
NEW = (
    (905890, 906100, "Vinnytsia", "UKR"),
    (905891, 906101, "Chernihiv", "UKR"),
    (905895, 906102, "Donetsk", "UKR"),
    (905897, 906103, "Smolensk", "RUS"),
    (905898, 906104, "Kursk", "RUS"),
    (905899, 906105, "Tula", "RUS"),
    (905902, 906106, "Stanislawow", "UKR"),
    (905903, 906107, "Tarnopol", "UKR"),
    (905905, 906108, "Rovno", "UKR"),
    (905906, 906109, "Drohobych", "UKR"),
    (905907, 906110, "Kovel", "UKR"),
)
ID_MAP = dict(DUP)
ID_MAP.update({src: dest for src, dest, _name, _adm in NEW})
REWRITE_GEO = (
    [903492, 903493, 903532, 903534]
    + list(range(905807, 905827))
    + [950006, 950123, 950124]
)
STUB_EDGES = ((903534, 905809), (905807, 905809))
CLASH_LAND = set(range(905849, 905909))
CLASH_SEAS = {950340, 950341, 950342, 950343}
STATE_ID = 388
REGION_ID = 5
SUPER_ID = 3
ERAS = (1910, 1918, 1936, 1945, 2026)


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _dump(path: Path, doc: dict, ensure_ascii: bool) -> None:
    text = json.dumps(doc, indent=2, ensure_ascii=ensure_ascii) + "\n"
    # Keep the one pre-existing escape so the diff stays on the fold.
    if "\\u00f4" in path.read_text(encoding="utf-8"):
        text = text.replace("Haute-Saône", "Haute-Sa\\u00f4ne")
        text = text.replace("Haute-Saone", "Haute-Sa\\u00f4ne")
    path.write_text(text, encoding="utf-8")


def _dedupe(ids):
    out = []
    seen = set()
    for n in ids:
        n = int(n)
        if n in seen:
            continue
        seen.add(n)
        out.append(n)
    return out


def _map_id(pid: int) -> int:
    return int(ID_MAP.get(int(pid), pid))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source-dir", type=Path, required=True)
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    src_dir = args.source_dir / "data" / "provinces_world_accurate"
    if not (src_dir / "provinces_base.json").is_file():
        src_dir = args.source_dir
    src_base = {int(p["id"]): p for p in _load(src_dir / "provinces_base.json")["provinces"]}
    our_doc = _load(BOARD / "provinces_base.json")
    our_rows = our_doc["provinces"]
    our_base = {int(p["id"]): p for p in our_rows}
    if 906100 in our_base and not args.apply:
        print("906100 already present")
    if 906100 in our_base and args.apply:
        print("refuse: 906100 already on the board")
        return 2

    src_geo = {int(g["id"]): g for g in _load(src_dir / "provinces_geometry.json")["provinces"]}
    our_geo_doc = _load(BOARD / "provinces_geometry.json")
    our_geo = {int(g["id"]): g for g in our_geo_doc["provinces"]}
    src_adj = _load(src_dir / "province_adjacency.json")["adjacency"]
    our_adj_doc = _load(BOARD / "province_adjacency.json")
    adj = {k: [int(n) for n in v] for k, v in our_adj_doc["adjacency"].items()}

    new_dests = [dest for _s, dest, _n, _a in NEW]
    result_ids = set(our_base) | set(new_dests)
    if result_ids & CLASH_LAND:
        print("clash land already on board", sorted(result_ids & CLASH_LAND)[:20])
        return 2
    if result_ids & CLASH_SEAS:
        print("clash seas on board", sorted(result_ids & CLASH_SEAS))
        return 2

    # Geometry plan: copy points + label_anchor. Keep our meta, tag the fold.
    geo_replace = {}
    for src_pid in REWRITE_GEO:
        old = our_geo[src_pid]
        src = src_geo[src_pid]
        obj = dict(old)
        obj["points"] = src["points"]
        obj["label_anchor"] = src.get("label_anchor") or old.get("label_anchor")
        meta = dict(old.get("meta") or {})
        meta["map_reconcile1"] = "gap-west-ukr-ring"
        obj["meta"] = meta
        geo_replace[src_pid] = obj
    for src_pid, dest in DUP.items():
        old = our_geo[dest]
        src = src_geo[src_pid]
        obj = dict(old)
        obj["points"] = src["points"]
        obj["label_anchor"] = src.get("label_anchor") or old.get("label_anchor")
        meta = dict(old.get("meta") or {})
        meta["map_reconcile1"] = "upgraded-from-%s" % src_pid
        obj["meta"] = meta
        geo_replace[dest] = obj
    new_geo = []
    for src_pid, dest, name, adm0 in NEW:
        src = src_geo[src_pid]
        new_geo.append(
            {
                "id": dest,
                "points": src["points"],
                "label_anchor": src["label_anchor"],
                "meta": {
                    "source": "map_reconcile1",
                    "from_id": src_pid,
                    "adm0_a3": adm0,
                    "level": "GAP",
                },
            }
        )

    # City-in-ring for the 21 nation-tag gaps against the planned rings.
    planned = dict(our_geo)
    planned.update(geo_replace)
    for g in new_geo:
        planned[int(g["id"])] = g
    rings = []
    for gid, g in planned.items():
        pts = g.get("points") or []
        if len(pts) >= 3:
            rings.append((gid, pts))
    city_fails = []
    for spec in GAPS:
        g = planned.get(spec.pid) or {}
        pts = g.get("points") or []
        x, y = lonlat_to_canvas(spec.lon, spec.lat)
        if not _point_in_ring(x, y, pts):
            city_fails.append("%s city not inside own ring" % spec.pid)
            continue
        anchor = g.get("label_anchor") or []
        if len(anchor) < 2 or not _point_in_ring(float(anchor[0]), float(anchor[1]), pts):
            city_fails.append("%s anchor outside" % spec.pid)
        for oid, opts in rings:
            if oid == spec.pid:
                continue
            if _point_in_ring(x, y, opts):
                city_fails.append("%s city also inside %s" % (spec.pid, oid))
                break
    for g in new_geo:
        anchor = g["label_anchor"]
        ax, ay = float(anchor[0]), float(anchor[1])
        if not _point_in_ring(ax, ay, g["points"]):
            city_fails.append("%s new anchor outside own ring" % g["id"])
        for oid, opts in rings:
            if oid == g["id"]:
                continue
            if _point_in_ring(ax, ay, opts):
                city_fails.append("%s new anchor also inside %s" % (g["id"], oid))
                break
    if city_fails:
        print("CITY FAILS", len(city_fails))
        for line in city_fails[:40]:
            print(" ", line)
        return 2

    # Adjacency: replace affected lists from the gap board, remap, mirror.
    affected_src = list(REWRITE_GEO) + list(DUP.keys()) + [src for src, _d, _n, _a in NEW]
    new_lists = {}
    for src_pid in affected_src:
        dest = _map_id(src_pid)
        nbrs = []
        for n in src_adj.get(str(src_pid), []):
            m = _map_id(int(n))
            if m == dest or m not in result_ids:
                continue
            if m in CLASH_LAND or m in CLASH_SEAS:
                continue
            nbrs.append(m)
        new_lists[dest] = _dedupe(nbrs)
    for dest, nbrs in new_lists.items():
        old = [int(n) for n in adj.get(str(dest), [])]
        adj[str(dest)] = list(nbrs)
        for o in old:
            if o in nbrs:
                continue
            back = adj.get(str(o))
            if back and dest in back:
                adj[str(o)] = [x for x in back if int(x) != dest]
        for n in nbrs:
            back = adj.setdefault(str(n), [])
            if dest not in back:
                back.append(dest)
    # Drop any neighbor that is not on the result board.
    for k in list(adj.keys()):
        adj[k] = [int(n) for n in adj[k] if int(n) in result_ids and int(n) != int(k)]

    asym = []
    for k, nbrs in adj.items():
        pid = int(k)
        for n in nbrs:
            if pid not in adj.get(str(n), []):
                asym.append((pid, n))
    if asym:
        print("asymmetric", len(asym), asym[:12])
        return 2
    for a, b in STUB_EDGES:
        if b not in adj.get(str(a), []) or a not in adj.get(str(b), []):
            print("stub edge missing", a, b, adj.get(str(a)), adj.get(str(b)))
            return 2

    domains = {pid: str(row.get("domain") or "") for pid, row in our_base.items()}
    for _s, dest, _n, _a in NEW:
        domains[dest] = "land"
    orphans = []
    for pid, domain in domains.items():
        if domain != "land":
            continue
        if not adj.get(str(pid)):
            orphans.append(pid)
    if orphans:
        print("orphans", len(orphans), orphans[:30])
        return 2

    # Owners for the 11. 2026 follows adm0. Other eras copy the gap branch.
    src_owners = {year: _load(src_dir / ("province_ownership_%s.json" % year))["owners"] for year in ERAS}
    owner_plan = {}
    pol_factory = 0
    src_eco = _load(src_dir / "province_economy_layer.json")["provinces"]
    for src_pid, dest, name, adm0 in NEW:
        if src_base[src_pid]["name"] != name:
            print("name mismatch", src_pid, src_base[src_pid]["name"], name)
            return 2
        owners = {}
        for year in ERAS:
            owners[year] = src_owners[year][str(src_pid)]
        owners[2026] = adm0
        if owners[1936] in ("UKR", "MDA", "PRC", "MAN"):
            print("1936 new tag", dest, owners[1936])
            return 2
        owner_plan[dest] = owners
        fac = int((src_eco.get(str(src_pid)) or {}).get("factories") or 0)
        if owners[1936] == "POL":
            pol_factory += 1 + fac
    print("new", len(NEW), "board", len(our_base) + len(NEW), "land", sum(1 for d in domains.values() if d == "land"))
    print("pol_1936_weight_add", pol_factory, "stub", [list(e) for e in STUB_EDGES])
    print("moscow_nbr", adj["903534"])
    print("haradok_nbr", adj["905809"])
    print("city_ok gaps", len(GAPS), "new", len(new_geo))
    if not args.apply:
        print("dry-run only")
        return 0

    # Base rows.
    for src_pid, dest, name, adm0 in NEW:
        src = src_base[src_pid]
        cores = [str(t) for t in (src.get("core_for_tags") or []) if str(t) not in ("UKR", "MDA", "PRC", "MAN")]
        our_rows.append(
            {
                "id": dest,
                "name": name,
                "terrain": src.get("terrain") or "plains",
                "domain": "land",
                "core_for_tags": cores or ["SOV"],
                "natural_resources": src.get("natural_resources") or {},
                "population_base": 0,
                "meta": {
                    "source": "map_reconcile1",
                    "from_id": src_pid,
                    "adm0_a3": adm0,
                    "admin": adm0,
                    "level": "GAP",
                },
            }
        )
    _dump(BOARD / "provinces_base.json", our_doc, ensure_ascii=False)

    # Geometry: surgical replace + append. File is compact.
    raw_geo = (BOARD / "provinces_geometry.json").read_text(encoding="utf-8")
    dec = json.JSONDecoder()
    pos = raw_geo.find("[")
    if pos < 0:
        print("geometry array missing")
        return 2
    pos += 1
    spans = []
    n = len(raw_geo)
    while pos < n:
        while pos < n and raw_geo[pos] in " \n\r\t,":
            pos += 1
        if pos >= n or raw_geo[pos] == "]":
            break
        _obj, end = dec.raw_decode(raw_geo, pos)
        spans.append((pos, end, int(_obj["id"])))
        pos = end
    if not spans:
        print("no geometry spans")
        return 2
    pieces = []
    cursor = 0
    for start, end, pid in spans:
        pieces.append(raw_geo[cursor:start])
        if pid in geo_replace:
            pieces.append(json.dumps(geo_replace[pid], separators=(",", ":"), ensure_ascii=True))
        else:
            pieces.append(raw_geo[start:end])
        cursor = end
    # cursor is end of last object. Keep through the closing bracket by appending new objs first.
    extra = ",".join(json.dumps(g, separators=(",", ":"), ensure_ascii=True) for g in new_geo)
    pieces.append("," + extra)
    pieces.append(raw_geo[cursor:])
    geo_text = "".join(pieces)
    if not geo_text.endswith("\n"):
        geo_text += "\n"
    (BOARD / "provinces_geometry.json").write_text(geo_text, encoding="utf-8")
    # Prove the file still parses and contains the new ids.
    check_geo = {int(g["id"]) for g in json.loads(geo_text)["provinces"]}
    if not set(new_dests) <= check_geo:
        print("geometry write missing new ids")
        return 2

    # Adjacency stats.
    land_n = sum(1 for d in domains.values() if d == "land")
    our_adj_doc["adjacency"] = {k: adj[k] for k in adj}
    stats = our_adj_doc.get("stats") or {}
    stats["province_n"] = len(result_ids)
    stats["land_n"] = land_n
    stats["orphan_land_after"] = 0
    our_adj_doc["stats"] = stats
    _dump(BOARD / "province_adjacency.json", our_adj_doc, ensure_ascii=True)

    # Owners.
    for year in ERAS:
        path = BOARD / ("province_ownership_%s.json" % year)
        doc = _load(path)
        owners = doc["owners"]
        for dest, plan in owner_plan.items():
            owners[str(dest)] = plan[year]
        _dump(path, doc, ensure_ascii=True)

    # Economy: population 0. Other fields copied.
    eco_doc = _load(BOARD / "province_economy_layer.json")
    for src_pid, dest, _name, _adm in NEW:
        src_row = src_eco.get(str(src_pid)) or {}
        eco_doc["provinces"][str(dest)] = {
            "population": 0,
            "factories": int(src_row.get("factories") or 0),
            "infrastructure": int(src_row.get("infrastructure") or 1),
            "development_level": int(src_row.get("development_level") or 1),
        }
    _dump(BOARD / "province_economy_layer.json", eco_doc, ensure_ascii=True)

    # City, terrain, resources.
    city_doc = _load(BOARD / "province_city_layer.json")
    src_city = _load(src_dir / "province_city_layer.json")["provinces"]
    terrain_doc = _load(BOARD / "province_terrain_layer.json")
    src_terrain = _load(src_dir / "province_terrain_layer.json")["provinces"]
    res_doc = _load(BOARD / "province_resources_layer.json")
    src_res = _load(src_dir / "province_resources_layer.json")["provinces"]
    for src_pid, dest, name, _adm in NEW:
        crow = src_city.get(str(src_pid)) or {}
        city_doc["provinces"][str(dest)] = {
            "city_name": crow.get("city_name") or name,
            "tier": int(crow.get("tier") or 2),
        }
        trow = src_terrain.get(str(src_pid)) or {}
        terrain_doc["provinces"][str(dest)] = {
            "terrain": trow.get("terrain") or "plains",
            "domain": "land",
        }
        rrow = src_res.get(str(src_pid)) or {}
        if rrow:
            res_doc["provinces"][str(dest)] = rrow
        else:
            res_doc["provinces"][str(dest)] = {"coal": 0, "steel": 0}
    _dump(BOARD / "province_city_layer.json", city_doc, ensure_ascii=False)
    _dump(BOARD / "province_terrain_layer.json", terrain_doc, ensure_ascii=True)
    _dump(BOARD / "province_resources_layer.json", res_doc, ensure_ascii=True)

    # Membership + scaffold maps. Do not touch scaffold province_n / land_n.
    for year in ERAS:
        path = BOARD / ("hierarchy_membership_%s.json" % year)
        doc = _load(path)
        for dest in new_dests:
            doc["province_to_region"][str(dest)] = REGION_ID
            doc["province_to_state"][str(dest)] = STATE_ID
            doc["province_to_super_region"][str(dest)] = SUPER_ID
        _dump(path, doc, ensure_ascii=True)
    scaf_path = BOARD / "hierarchy_scaffold.json"
    scaf = _load(scaf_path)
    for dest in new_dests:
        scaf["province_to_region"][str(dest)] = REGION_ID
        scaf["province_to_state"][str(dest)] = STATE_ID
        scaf["province_to_super_region"][str(dest)] = SUPER_ID
    _dump(scaf_path, scaf, ensure_ascii=True)

    states = _load(BOARD / "province_states.json")
    for st in states["states"]:
        if int(st["id"]) == STATE_ID:
            have = {int(x) for x in st.get("province_ids") or []}
            for dest in new_dests:
                if dest not in have:
                    st["province_ids"].append(dest)
    _dump(BOARD / "province_states.json", states, ensure_ascii=True)
    regions = _load(BOARD / "strategic_regions.json")
    for reg in regions["regions"]:
        if int(reg["id"]) == REGION_ID:
            have = {int(x) for x in reg.get("province_ids") or []}
            for dest in new_dests:
                if dest not in have:
                    reg["province_ids"].append(dest)
    _dump(BOARD / "strategic_regions.json", regions, ensure_ascii=True)

    man_path = BOARD / "manifest_world_accurate.json"
    man = _load(man_path)
    man["stats"]["provinces"] = len(result_ids)
    man["stats"]["land"] = land_n
    gq = str(man.get("geometry_quality") or "")
    if "v1_map_reconcile1_west" not in gq:
        man["geometry_quality"] = gq + "+v1_map_reconcile1_west"
    _dump(man_path, man, ensure_ascii=True)
    print("applied", len(NEW), "board", len(result_ids), "land", land_n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
