#!/usr/bin/env python3
"""Fold GAP-CHINA (#124) onto the reconciled board.

Cherry-pick is not used: origin/grok/gap-china also carries Hawaii and IBS ids
this tip does not have. Shapely is not installed, so this copies rings already
baked on that branch (tip fc1138e3).

Unique names land at 906111–906138. Six #124 provinces are the same cities
#136 already has, so they do not get a second id. Their rings are bridged
onto the existing province (name, owners, population stay). The 22 CHI blobs
keep their ids and names. Only their rings move to the #124 boxes.

Shared-id changes (nothing else on an existing id is written):

- Geometry of the 22 CHI blobs 902487, 902491, 902493, 902496, 902504,
  902505, 902514, 902521, 902523, 902526, 902534, 902544, 902564, 902566,
  902568, 902569, 902590, 902598, 902601, 902633, 902634, 902646.
- Geometry of 906013 Chongqing, 906014 Guangzhou, 906015 Chengdu,
  906016 Fuzhou, 906018 Taiyuan, 906019 Guiyang (bridged #124 ring).
- City layer 902590: "Shanghai" becomes "Anking". Shanghai is the city of
  the new Jiangsu South province. 902590's ring is Anhui South.

Owners of those shared ids are not written. 1936 owner of every new id is
CHI. 2026 is PRC, matching the #136 China cities. Other eras copy the gap
branch (CHI). Population of new ids is 0 so they stay out of the HWY-3 hub
set. 905849–905908 and 950340–950342 are not copied.

The living CHI–JAP front is still 903981 → 902598. The #124 ring for 902598
is Hunan, so the source neighbor list drops Kinmen. That edge is put back
after the rewrite. Names and owners of both ids stay as they are.
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

# source id -> existing #136 id. Same city, so no second province.
DUP = {
    905862: 906018,  # Shanxi South (Taiyuan)
    905873: 906016,  # Fujian North (Foochow)
    905879: 906015,  # Sichuan West (Chengdu)
    905881: 906013,  # Sichuan East (Chungking)
    905882: 906019,  # Guizhou (capital Guiyang)
    905885: 906014,  # Guangdong Central (Canton)
}
# Unique #124 names, in source-id order. 2026 owner is PRC.
NEW = (
    (905855, 906111, "Urumqi-Turfan"),
    (905856, 906112, "U-Tsang (Lhasa)"),
    (905857, 906113, "Changtang (N. Tibet)"),
    (905858, 906114, "Xikang East (Kangding)"),
    (905859, 906115, "Qinghai East (Xining)"),
    (905860, 906116, "Ningxia"),
    (905861, 906117, "Shanxi North (Datong)"),
    (905863, 906118, "Shaanbei (Yanan)"),
    (905864, 906119, "Guanzhong (Xian)"),
    (905865, 906120, "Shaannan (Hanzhong)"),
    (905866, 906121, "Henan North (Kaifeng)"),
    (905867, 906122, "Henan South (Xinyang)"),
    (905868, 906123, "Jiangsu North (Xuzhou)"),
    (905869, 906124, "Jiangsu South (Shanghai-Nanking)"),
    (905870, 906125, "Anhui North (Bengbu)"),
    (905871, 906126, "Zhejiang North (Hangzhou)"),
    (905872, 906127, "Zhejiang South (Wenzhou)"),
    (905874, 906128, "Jiangxi North (Nanchang)"),
    (905875, 906129, "Jiangxi South (Ganzhou)"),
    (905876, 906130, "Hubei East (Wuhan)"),
    (905877, 906131, "Hubei West (Yichang)"),
    (905878, 906132, "Hunan South (Hengyang)"),
    (905880, 906133, "Sichuan North (Nanchong)"),
    (905883, 906134, "Yunnan West (Dali)"),
    (905884, 906135, "Guangxi West (Nanning)"),
    (905886, 906136, "Guangdong East (Swatow)"),
    (905887, 906137, "Guangdong West (Leizhou)"),
    (905888, 906138, "Hainan"),
)
CHI_BLOBS = (
    902487, 902491, 902493, 902496, 902504, 902505, 902514, 902521, 902523,
    902526, 902534, 902544, 902564, 902566, 902568, 902569, 902590, 902598,
    902601, 902633, 902634, 902646,
)
ID_MAP = {pid: pid for pid in CHI_BLOBS}
ID_MAP.update(DUP)
ID_MAP.update({src: dest for src, dest, _name in NEW})
STUB_EDGES = ((903534, 905809), (905807, 905809))
# Hardcoded living front. Source adjacency drops it when 902598 becomes Hunan.
FRONT_EDGE = (903981, 902598)
CLASH_LAND = set(range(905849, 905909))
CLASH_SEAS = {950340, 950341, 950342, 950343}
STATE_ID = 289
REGION_ID = 7
SUPER_ID = 3
ERAS = (1910, 1918, 1936, 1945, 2026)
GARRISON_TAGS = ("GER", "FRA", "ENG", "SOV", "ITA", "JAP", "USA", "POL", "CZE")
GARRISON_CAPITALS = {
    "GER": (710300,),
    "FRA": (710707,),
    "ENG": (711414,),
    "USA": (800792,),
    "SOV": (903534,),
    "ITA": (710963,),
    "JAP": (903995,),
    "POL": (711112, 711054),
    "CZE": (710146,),
}
FIRST_NEW = 906111


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _dump_ascii(path: Path, doc: dict) -> None:
    text = json.dumps(doc, indent=2, ensure_ascii=True) + "\n"
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


def _ring_area(ring):
    area = 0.0
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i][0], ring[i][1]
        x2, y2 = ring[(i + 1) % n][0], ring[(i + 1) % n][1]
        area += x1 * y2 - x2 * y1
    return area / 2.0


def _ensure_ccw(ring):
    pts = [(float(p[0]), float(p[1])) for p in ring]
    if _ring_area(pts) < 0:
        pts.reverse()
    return pts


def _open_ring(ring):
    if len(ring) >= 2 and ring[0] == ring[-1]:
        return list(ring[:-1])
    return list(ring)


def bridge_rings(rings):
    """There-and-back bridge, same construction as generate_gap_china.py."""
    parts = [_ensure_ccw(r) for r in rings if len(r) >= 3]
    parts.sort(key=lambda r: (-abs(_ring_area(r)), r[0][0], r[0][1]))
    if not parts:
        return []
    acc = list(parts[0])
    for nxt in parts[1:]:
        best = None
        bi = bj = 0
        for i, p in enumerate(acc):
            for j, q in enumerate(nxt):
                dist = (p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2
                if best is None or dist < best:
                    best = dist
                    bi, bj = i, j
        rotated = nxt[bj:] + nxt[:bj]
        acc = acc[: bi + 1] + rotated + [rotated[0], acc[bi]] + acc[bi + 1 :]
    opened = _open_ring(acc)
    return [[round(p[0], 6), round(p[1], 6)] for p in opened]


def _anchor_of(g):
    anchor = g.get("label_anchor") or []
    if len(anchor) >= 2:
        return float(anchor[0]), float(anchor[1])
    pts = g.get("points") or []
    if not pts:
        return 0.0, 0.0
    return (
        sum(float(p[0]) for p in pts) / len(pts),
        sum(float(p[1]) for p in pts) / len(pts),
    )


def _min_edge_dist2(ax, ay, pts):
    """Closest point on the ring boundary, not the label. Huge CHI blobs keep
    their label far from the Manchuria edge, so label distance picks Korea.
    """
    best = None
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        dx = x2 - x1
        dy = y2 - y1
        if dx == 0.0 and dy == 0.0:
            d = (ax - x1) * (ax - x1) + (ay - y1) * (ay - y1)
        else:
            t = ((ax - x1) * dx + (ay - y1) * dy) / (dx * dx + dy * dy)
            if t < 0.0:
                t = 0.0
            elif t > 1.0:
                t = 1.0
            px = x1 + t * dx
            py = y1 + t * dy
            d = (ax - px) * (ax - px) + (ay - py) * (ay - py)
        if best is None or d < best:
            best = d
    return best if best is not None else 1e300


def _garrison_targets(owners, adj):
    borders = {tag: set() for tag in GARRISON_TAGS}
    for pid_s, nbrs in adj.items():
        pid = int(pid_s)
        if pid <= 0 or pid >= 950000:
            continue
        owner = str(owners.get(str(pid)) or "")
        if owner not in borders:
            continue
        for n in nbrs:
            n = int(n)
            if n <= 0 or n >= 950000:
                continue
            other = str(owners.get(str(n)) or "")
            if other and other != owner:
                borders[owner].add(pid)
                break
    targets = {}
    for tag, caps in GARRISON_CAPITALS.items():
        got = set(borders[tag])
        for cap in caps:
            if str(owners.get(str(cap)) or "") == tag and cap < 950000:
                got.add(cap)
        targets[tag] = got
    return targets


def _indent_block(obj, spaces):
    raw = json.dumps(obj, indent=2, ensure_ascii=False)
    pad = " " * spaces
    return "\n".join(pad + line for line in raw.splitlines())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source-dir", type=Path, required=True)
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    src_dir = args.source_dir
    if not (src_dir / "provinces_base.json").is_file():
        src_dir = args.source_dir / "data" / "provinces_world_accurate"
    src_base = {int(p["id"]): p for p in _load(src_dir / "provinces_base.json")["provinces"]}
    our_doc = _load(BOARD / "provinces_base.json")
    our_rows = our_doc["provinces"]
    our_base = {int(p["id"]): p for p in our_rows}
    if FIRST_NEW in our_base:
        print("refuse: %s already on the board" % FIRST_NEW)
        return 2

    for src_pid, dest, name in NEW:
        if src_base[src_pid]["name"] != name:
            print("name mismatch", src_pid, src_base[src_pid]["name"], name)
            return 2
    for src_pid, dest in DUP.items():
        if dest not in our_base:
            print("dup dest missing", dest)
            return 2

    src_geo = {int(g["id"]): g for g in _load(src_dir / "provinces_geometry.json")["provinces"]}
    our_geo = {int(g["id"]): g for g in _load(BOARD / "provinces_geometry.json")["provinces"]}
    src_adj = _load(src_dir / "province_adjacency.json")["adjacency"]
    our_adj_doc = _load(BOARD / "province_adjacency.json")
    adj = {k: [int(n) for n in v] for k, v in our_adj_doc["adjacency"].items()}
    before_adj = {k: list(v) for k, v in adj.items()}

    new_dests = [dest for _s, dest, _n in NEW]
    result_ids = set(our_base) | set(new_dests)
    if result_ids & CLASH_LAND:
        print("clash land", sorted(result_ids & CLASH_LAND)[:12])
        return 2
    if result_ids & CLASH_SEAS:
        print("clash seas", sorted(result_ids & CLASH_SEAS))
        return 2
    if any(d in our_base for d in new_dests):
        print("new id collision")
        return 2

    # Owners of the 22 blobs must already match the gap branch. Do not write them.
    owner_diffs = []
    src_owners = {}
    our_owners = {}
    for year in ERAS:
        src_owners[year] = _load(src_dir / ("province_ownership_%s.json" % year))["owners"]
        our_owners[year] = _load(BOARD / ("province_ownership_%s.json" % year))["owners"]
        for pid in CHI_BLOBS:
            if our_owners[year].get(str(pid)) != src_owners[year].get(str(pid)):
                owner_diffs.append((year, pid, our_owners[year].get(str(pid)), src_owners[year].get(str(pid))))
    if owner_diffs:
        print("shared owner would change", owner_diffs[:12])
        return 2

    geo_replace = {}
    for pid in CHI_BLOBS:
        old = our_geo[pid]
        src = src_geo[pid]
        obj = dict(old)
        obj["points"] = src["points"]
        obj["label_anchor"] = src.get("label_anchor") or old.get("label_anchor")
        meta = dict(old.get("meta") or {})
        meta["gap_china2"] = "ring-from-%s" % src_base[pid]["name"]
        obj["meta"] = meta
        # Name on the geometry object stays. The province name stays.
        if "name" in old:
            obj["name"] = old["name"]
        geo_replace[pid] = obj
    for src_pid, dest in DUP.items():
        old = our_geo[dest]
        src = src_geo[src_pid]
        bridged = bridge_rings([src["points"], old["points"]])
        obj = dict(old)
        obj["points"] = bridged
        anchor = old.get("label_anchor") or src.get("label_anchor")
        if not _point_in_ring(float(anchor[0]), float(anchor[1]), bridged):
            anchor = src.get("label_anchor")
        obj["label_anchor"] = anchor
        meta = dict(old.get("meta") or {})
        meta["gap_china2"] = "upgraded-from-%s" % src_pid
        obj["meta"] = meta
        if "name" in old:
            obj["name"] = old["name"]
        geo_replace[dest] = obj
    new_geo = []
    for src_pid, dest, name in NEW:
        src = src_geo[src_pid]
        new_geo.append(
            {
                "id": dest,
                "points": src["points"],
                "label_anchor": src["label_anchor"],
                "meta": {
                    "source": "gap_china2",
                    "from_id": src_pid,
                    "adm0_a3": "CHN",
                    "level": "GAP",
                },
            }
        )

    planned = dict(our_geo)
    planned.update(geo_replace)
    for g in new_geo:
        planned[int(g["id"])] = g

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
        for oid, og in planned.items():
            if oid == spec.pid:
                continue
            opts = og.get("points") or []
            if len(opts) >= 3 and _point_in_ring(x, y, opts):
                city_fails.append("%s city also inside %s" % (spec.pid, oid))
                break
    for g in new_geo:
        anchor = g["label_anchor"]
        if not _point_in_ring(float(anchor[0]), float(anchor[1]), g["points"]):
            city_fails.append("%s new anchor outside own ring" % g["id"])
    if city_fails:
        print("CITY FAILS", len(city_fails))
        for line in city_fails[:40]:
            print(" ", line)
        return 2

    # Adjacency from the gap board for blobs, upgraded cities, and new ids.
    affected_src = list(CHI_BLOBS) + list(DUP.keys()) + [src for src, _d, _n in NEW]
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
        # A dest can be reached twice only if ID_MAP collides. It does not.
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
    for dest in new_dests:
        adj.setdefault(str(dest), [])
    for k in list(adj.keys()):
        adj[k] = [int(n) for n in adj[k] if int(n) in result_ids and int(n) != int(k)]

    # Anything the ring move unhooked gets the nearest remaining land province.
    # Snapshot the holes first. Linking one hole to another chained Harbin onto
    # Changchun and left both off the mainland.
    anchors = {pid: _anchor_of(g) for pid, g in planned.items()}
    rings = {}
    for pid, g in planned.items():
        pts = g.get("points") or []
        if len(pts) >= 2:
            rings[pid] = [(float(p[0]), float(p[1])) for p in pts]
    domains = {pid: str(row.get("domain") or "") for pid, row in our_base.items()}
    for dest in new_dests:
        domains[dest] = "land"
    land_ids = [pid for pid, domain in domains.items() if domain == "land"]
    holes = [pid for pid in domains if not adj.get(str(pid))]
    hole_set = set(holes)
    reattached = []
    for pid in holes:
        domain = domains.get(pid, "")
        pool = land_ids if domain == "land" else list(anchors)
        ax, ay = anchors.get(pid, (0.0, 0.0))
        best = None
        for other in pool:
            if other == pid or other in hole_set:
                continue
            pts = rings.get(other)
            if pts:
                dist = _min_edge_dist2(ax, ay, pts)
            elif other in anchors:
                bx, by = anchors[other]
                dist = (ax - bx) ** 2 + (ay - by) ** 2
            else:
                continue
            if best is None or dist < best[0]:
                best = (dist, other)
        if best is None:
            print("no neighbor candidate", pid)
            return 2
        other = best[1]
        adj.setdefault(str(pid), []).append(other)
        back = adj.setdefault(str(other), [])
        if pid not in back:
            back.append(pid)
        reattached.append((pid, other))

    for a, b in (FRONT_EDGE,):
        for x, y in ((a, b), (b, a)):
            lst = adj.setdefault(str(x), [])
            if y not in lst:
                lst.append(y)

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
            print("stub edge missing", a, b)
            return 2

    orphans = [pid for pid, domain in domains.items() if domain == "land" and not adj.get(str(pid))]
    if orphans:
        print("orphans", len(orphans), orphans[:20])
        return 2
    empty = [pid for pid in result_ids if not adj.get(str(pid))]
    if empty:
        print("degree 0", len(empty), empty[:20])
        return 2

    owner_plan = {}
    for src_pid, dest, _name in NEW:
        owners = {}
        for year in ERAS:
            owners[year] = src_owners[year][str(src_pid)]
        if owners[1936] != "CHI":
            print("1936 not CHI", dest, owners[1936])
            return 2
        if owners[1936] in ("UKR", "MDA", "PRC", "MAN"):
            print("1936 new tag", dest)
            return 2
        owners[2026] = "PRC"
        owner_plan[dest] = owners

    own_1936 = dict(our_owners[1936])
    for dest, plan in owner_plan.items():
        own_1936[str(dest)] = plan[1936]
    before_g = _garrison_targets(our_owners[1936], before_adj)
    after_g = _garrison_targets(own_1936, adj)
    print("garrison delta")
    total_before = 0
    total_after = 0
    for tag in GARRISON_TAGS:
        b = before_g[tag]
        a = after_g[tag]
        total_before += len(b)
        total_after += len(a)
        added = sorted(a - b)
        removed = sorted(b - a)
        if added or removed:
            print(" ", tag, "%s -> %s" % (len(b), len(a)), "added", added, "removed", removed)
    print("garrison total", total_before, "->", total_after, "delta", total_after - total_before)
    names = {pid: str(row.get("name") or "") for pid, row in our_base.items()}
    for _src, dest, name in NEW:
        names[dest] = name
    print("reattached", len(reattached))
    for pid, other in reattached:
        print(
            " ",
            pid,
            names.get(pid, ""),
            "->",
            other,
            names.get(other, ""),
            "owner",
            own_1936.get(str(other)),
        )
    print(
        "new",
        len(NEW),
        "board",
        len(our_base) + len(NEW),
        "land",
        sum(1 for d in domains.values() if d == "land"),
    )
    print("shared ownership unchanged", len(CHI_BLOBS), "blobs")
    print("city move 902590 Shanghai -> Anking")
    if not args.apply:
        print("dry-run only")
        return 0

    # Base rows. Append only, so existing unicode stays byte-stable.
    blocks = []
    for src_pid, dest, name in NEW:
        src = src_base[src_pid]
        terrain = src.get("terrain") or "plains"
        blocks.append(
            {
                "id": dest,
                "name": name,
                "terrain": terrain,
                "domain": "land",
                "core_for_tags": ["CHI"],
                "natural_resources": src.get("natural_resources") or {},
                "population_base": 0,
                "meta": {
                    "source": "gap_china2",
                    "from_id": src_pid,
                    "adm0_a3": "CHN",
                    "admin": "CHN",
                    "level": "GAP",
                },
            }
        )
    base_text = (BOARD / "provinces_base.json").read_text(encoding="utf-8")
    needle = "\n  ]\n}\n"
    at = base_text.rfind(needle)
    if at < 0:
        print("base tail missing")
        return 2
    extra = ",\n" + ",\n".join(_indent_block(row, 4) for row in blocks)
    (BOARD / "provinces_base.json").write_text(base_text[:at] + extra + base_text[at:], encoding="utf-8")

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
    pieces = []
    cursor = 0
    for start, end, pid in spans:
        pieces.append(raw_geo[cursor:start])
        if pid in geo_replace:
            pieces.append(json.dumps(geo_replace[pid], separators=(",", ":"), ensure_ascii=True))
        else:
            pieces.append(raw_geo[start:end])
        cursor = end
    extra_geo = ",".join(json.dumps(g, separators=(",", ":"), ensure_ascii=True) for g in new_geo)
    pieces.append("," + extra_geo)
    pieces.append(raw_geo[cursor:])
    geo_text = "".join(pieces)
    if not geo_text.endswith("\n"):
        geo_text += "\n"
    (BOARD / "provinces_geometry.json").write_text(geo_text, encoding="utf-8")
    check_geo = {int(g["id"]) for g in json.loads(geo_text)["provinces"]}
    if not set(new_dests) <= check_geo:
        print("geometry write missing new ids")
        return 2

    land_n = sum(1 for d in domains.values() if d == "land")
    our_adj_doc["adjacency"] = {k: adj[k] for k in adj}
    stats = our_adj_doc.get("stats") or {}
    degrees = [len(v) for v in adj.values()]
    stats["province_n"] = len(result_ids)
    stats["land_n"] = land_n
    stats["water_n"] = len(result_ids) - land_n
    stats["orphan_land_after"] = 0
    if degrees:
        stats["degree_min"] = min(degrees)
        stats["degree_max"] = max(degrees)
        stats["degree_mean"] = sum(degrees) / float(len(degrees))
    our_adj_doc["stats"] = stats
    _dump_ascii(BOARD / "province_adjacency.json", our_adj_doc)

    for year in ERAS:
        path = BOARD / ("province_ownership_%s.json" % year)
        doc = _load(path)
        owners = doc["owners"]
        for dest, plan in owner_plan.items():
            owners[str(dest)] = plan[year]
        _dump_ascii(path, doc)

    src_eco = _load(src_dir / "province_economy_layer.json")["provinces"]
    eco_doc = _load(BOARD / "province_economy_layer.json")
    for src_pid, dest, _name in NEW:
        src_row = src_eco.get(str(src_pid)) or {}
        eco_doc["provinces"][str(dest)] = {
            "population": 0,
            "factories": int(src_row.get("factories") or 0),
            "infrastructure": int(src_row.get("infrastructure") or 1),
            "development_level": int(src_row.get("development_level") or 1),
        }
    _dump_ascii(BOARD / "province_economy_layer.json", eco_doc)

    city_text = (BOARD / "province_city_layer.json").read_text(encoding="utf-8")
    old_city = '    "902590": {\n      "city_name": "Shanghai",\n      "tier": 2\n    },'
    new_city = '    "902590": {\n      "city_name": "Anking",\n      "tier": 2\n    },'
    if city_text.count(old_city) != 1:
        print("shanghai city span missing")
        return 2
    city_text = city_text.replace(old_city, new_city, 1)
    src_city = _load(src_dir / "province_city_layer.json")["provinces"]
    city_blocks = []
    for src_pid, dest, name in NEW:
        crow = src_city.get(str(src_pid)) or {}
        city_blocks.append(
            (
                dest,
                {
                    "city_name": crow.get("city_name") or name,
                    "tier": int(crow.get("tier") or 2),
                },
            )
        )
    city_extra_lines = []
    for dest, row in city_blocks:
        city_extra_lines.append('    "%s": %s' % (dest, json.dumps(row, ensure_ascii=False)))
    city_needle = '\n  },\n  "meta"'
    cat = city_text.rfind(city_needle)
    if cat < 0:
        print("city tail missing")
        return 2
    city_text = city_text[:cat] + ",\n" + ",\n".join(city_extra_lines) + city_text[cat:]
    (BOARD / "province_city_layer.json").write_text(city_text, encoding="utf-8")

    terrain_doc = _load(BOARD / "province_terrain_layer.json")
    src_terrain = _load(src_dir / "province_terrain_layer.json")["provinces"]
    res_doc = _load(BOARD / "province_resources_layer.json")
    src_res = _load(src_dir / "province_resources_layer.json")["provinces"]
    for src_pid, dest, _name in NEW:
        trow = src_terrain.get(str(src_pid)) or {}
        terrain_doc["provinces"][str(dest)] = {
            "terrain": trow.get("terrain") or "plains",
            "domain": "land",
        }
        rrow = src_res.get(str(src_pid)) or {}
        res_doc["provinces"][str(dest)] = rrow if rrow else {"coal": 0, "steel": 0}
    _dump_ascii(BOARD / "province_terrain_layer.json", terrain_doc)
    _dump_ascii(BOARD / "province_resources_layer.json", res_doc)

    for year in ERAS:
        path = BOARD / ("hierarchy_membership_%s.json" % year)
        doc = _load(path)
        for dest in new_dests:
            doc["province_to_region"][str(dest)] = REGION_ID
            doc["province_to_state"][str(dest)] = STATE_ID
            doc["province_to_super_region"][str(dest)] = SUPER_ID
        _dump_ascii(path, doc)
    scaf = _load(BOARD / "hierarchy_scaffold.json")
    for dest in new_dests:
        scaf["province_to_region"][str(dest)] = REGION_ID
        scaf["province_to_state"][str(dest)] = STATE_ID
        scaf["province_to_super_region"][str(dest)] = SUPER_ID
    _dump_ascii(BOARD / "hierarchy_scaffold.json", scaf)

    states = _load(BOARD / "province_states.json")
    for st in states["states"]:
        if int(st["id"]) == STATE_ID:
            have = {int(x) for x in st.get("province_ids") or []}
            for dest in new_dests:
                if dest not in have:
                    st["province_ids"].append(dest)
    _dump_ascii(BOARD / "province_states.json", states)
    regions = _load(BOARD / "strategic_regions.json")
    for reg in regions["regions"]:
        if int(reg["id"]) == REGION_ID:
            have = {int(x) for x in reg.get("province_ids") or []}
            for dest in new_dests:
                if dest not in have:
                    reg["province_ids"].append(dest)
    _dump_ascii(BOARD / "strategic_regions.json", regions)

    man = _load(BOARD / "manifest_world_accurate.json")
    man["stats"]["provinces"] = len(result_ids)
    man["stats"]["land"] = land_n
    gq = str(man.get("geometry_quality") or "")
    if "v1_gap_china2" not in gq:
        man["geometry_quality"] = gq + "+v1_gap_china2"
    _dump_ascii(BOARD / "manifest_world_accurate.json", man)
    print("applied", len(NEW), "board", len(result_ids), "land", land_n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
