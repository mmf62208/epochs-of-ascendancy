#!/usr/bin/env python3
"""Assign unique human-readable names to hotspot-densified world provinces.

Replaces bare numbered hub labels ("China North China Plain 1") with gazetteer
place names unique across the full provinces_world_full dataset.

Usage:
  python3 tools/map_generation/scripts/assign_world_hotspot_names.py \\
      --dir data/provinces_world_full [--write]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]

NUMBERED_HUB_RE = re.compile(r"^(?P<hub>.+?)\s+(?P<n>\d+)\s*$")
PLACEHOLDER_RE = re.compile(r"^(Province\s+\d+|New Settlement)$", re.I)

# Per-hub place pools (human-readable; enough for current densify wave sizes).
# Keys match densify name prefixes (without trailing index).
HUB_GAZETTEERS: Dict[str, List[str]] = {
    # China
    "China North China Plain": [
        "Baoding", "Cangzhou", "Langfang", "Hengshui", "Dezhou", "Binzhou", "Liaocheng", "Xingtai",
        "Handan", "Anyang",
    ],
    "China Yangtze Corridor": [
        "Zhenjiang", "Yangzhou", "Wuhu", "Maanshan", "Tongling", "Anqing", "Jiujiang", "Huanggang",
        "Yueyang", "Jingzhou",
    ],
    "China Pearl River": [
        "Foshan", "Dongguan", "Zhongshan", "Jiangmen", "Zhaoqing", "Huizhou", "Qingyuan", "Shaoguan",
    ],
    "China Sichuan Basin": [
        "Mianyang", "Deyang", "Nanchong", "Yibin", "Luzhou", "Neijiang", "Zigong", "Suining",
    ],
    "China Manchuria": [
        "Qiqihar", "Jiamusi", "Mudanjiang", "Jilin City", "Tonghua", "Anshan", "Fushun", "Benxi",
    ],
    # India
    "India Gangetic Plain": [
        "Kanpur", "Lucknow", "Allahabad", "Varanasi", "Patna", "Gaya", "Gorakhpur", "Agra",
        "Mathura", "Bareilly",
    ],
    "India Deccan": [
        "Nagpur", "Aurangabad", "Solapur", "Warangal", "Gulbarga", "Hubli", "Belgaum", "Nanded",
    ],
    "India Punjab": [
        "Amritsar", "Ludhiana", "Jalandhar", "Patiala", "Bathinda", "Firozpur", "Hoshiarpur",
    ],
    "India Bengal": [
        "Howrah", "Asansol", "Durgapur", "Siliguri", "Malda", "Krishnanagar", "Bardhaman",
    ],
    "India South Coast": [
        "Coimbatore", "Madurai", "Tiruchirappalli", "Mangalore", "Kozhikode", "Thoothukudi",
    ],
    # USA
    "USA Northeast Corridor": [
        "Newark Industrial", "Trenton Corridor", "Bridgeport Shore", "New Haven Belt",
        "Providence Belt", "Worcester Hills", "Hartford Valley", "Stamford Reach",
        "Jersey City Flats", "White Plains Ridge",
    ],
    "USA Midwest Industrial": [
        "Gary Works", "South Bend Belt", "Fort Wayne Flats", "Toledo Works",
        "Dayton Corridor", "Youngstown Belt", "Akron Valley", "Flint Corridor",
    ],
    "USA South Atlantic": [
        "Savannah Lowcountry", "Charleston Harbor Belt", "Wilmington Cape Fear",
        "Columbia Piedmont", "Augusta Fall Line", "Macon Plateau", "Jacksonville Approach",
    ],
    "USA Great Lakes": [
        "Erie Shore", "Buffalo Lakeside", "Rochester Canal", "Syracuse Valley",
        "Cleveland Shore", "Detroit River Bend",
    ],
    # Brazil
    "Brazil Southeast": [
        "Campinas Plateau", "Santos Shore", "Ribeirao Preto", "Sao Jose dos Campos",
        "Sorocaba Belt", "Juiz de Fora", "Belo Horizonte Belt", "Vitoria Coast",
    ],
    "Brazil Northeast": [
        "Recife Coast", "Fortaleza Shore", "Natal Dunes", "Maceio Lagoon",
        "Joao Pessoa Coast", "Aracaju Shore",
    ],
    "Brazil Interior": [
        "Goiania Plateau", "Brasilia Outskirts", "Uberlandia Cerrado", "Campo Grande Pantanal Edge",
        "Cuiaba Lowlands", "Anapolis Ridge",
    ],
    # Africa
    "Africa Nigeria Coast": [
        "Lagos Island Belt", "Ibadan Yoruba Hills", "Port Harcourt Delta", "Benin City Lowlands",
        "Warri Oil Shore", "Calabar Estuary", "Enugu Plateau", "Onitsha River",
        "Abeokuta Corridor", "Aba Market Belt",
    ],
    "Africa Gold Coast": [
        "Accra Coast", "Kumasi Ashanti", "Takoradi Harbor", "Cape Coast Fort",
        "Tamale Savanna", "Tema Port Belt", "Sekondi Shore",
    ],
    "Africa Senegal Corridor": [
        "Dakar Cap Vert", "Saint-Louis River", "Thies Plateau", "Kaolack Groundnut",
        "Ziguinchor Casamance", "Tambacounda East",
    ],
    "Africa Sahel Belt": [
        "Niamey Niger Bend", "Bamako River", "Ouagadougou Plateau", "Gao Desert Gate",
        "Agadez Caravan", "Kano Savanna", "Sokoto Caliphate", "Maradi Corridor",
        "Zinder Oasis Edge", "Dosso Sahel",
    ],
    "Africa Congo Basin": [
        "Kinshasa Pool", "Brazzaville Shore", "Kisangani River", "Mbandaka Forest",
        "Kananga Kasai", "Mbuji-Mayi Mines", "Bukavu Kivu", "Goma Volcanic",
        "Matadi Estuary", "Bandundu Wetlands",
    ],
    "Africa Katanga": [
        "Lubumbashi Copper", "Kolwezi Mines", "Likasi Belt", "Kipushi Hills",
        "Sakania Border", "Fungurume Ore", "Tenke Fungurume",
    ],
    "Africa Kenya Highlands": [
        "Nairobi Plateau", "Mombasa Coast", "Nakuru Rift", "Eldoret Highlands",
        "Kisumu Lake", "Nyeri Ridge", "Thika Corridor", "Malindi Shore",
        "Lamu Archipelago Edge",
    ],
    "Africa Ethiopia Plateau": [
        "Addis Ababa Highlands", "Dire Dawa Corridor", "Harar Hills", "Gondar Plateau",
        "Mekelle Tigray", "Bahir Dar Lake", "Jimma Highlands", "Awasa Rift",
    ],
    "Africa Mozambique Corridor": [
        "Maputo Bay", "Beira Corridor", "Nampula Plateau", "Quelimane Coast",
        "Tete Zambezi", "Pemba North Coast", "Inhambane Shore",
    ],
    "Africa South Africa Highveld": [
        "Johannesburg Reef", "Pretoria Highveld", "Bloemfontein Plain", "Kimberley Diamond",
        "Polokwane North", "Nelspruit Lowveld Edge", "Rustenburg Platinum", "Vereeniging Vaal",
        "Witbank Coal", "East Rand Belt",
    ],
    "Africa Cape Approaches": [
        "Cape Town Table", "Port Elizabeth Algoa", "East London Buffalo", "Stellenbosch Winelands",
        "George Garden Route", "Saldanha Bay",
    ],
    "Africa Angola Coast": [
        "Luanda Bay", "Lobito Harbor", "Benguela Coast", "Namibe Shore",
        "Cabinda Enclave", "Huambo Plateau", "Lubango Hills",
    ],
    "Africa Rhodesia Plateau": [
        "Harare Plateau", "Bulawayo Matabele", "Mutare Eastern Highlands", "Gweru Midlands",
        "Victoria Falls Corridor", "Kwekwe Mining",
    ],
    "Africa Cameroons": [
        "Douala Port", "Yaounde Hills", "Bamenda Highlands", "Garoua North",
        "Buea Volcanic", "Limbe Shore", "Maroua Sahel Edge",
    ],
    # SE Asia
    "SE Asia Indochina": [
        "Hanoi Red River", "Haiphong Port", "Hue Imperial", "Da Nang Coast",
        "Vinh Corridor", "Nha Trang Shore", "Can Tho Mekong Edge", "Phnom Penh Basin",
        "Siem Reap Plain", "Vientiane Mekong",
    ],
    "SE Asia Mekong Delta": [
        "My Tho Delta", "Can Tho Heartland", "Long Xuyen Floodplain", "Rach Gia Coast",
        "Ca Mau Tip", "Soc Trang Wetlands", "Ben Tre Orchards", "Tra Vinh Shore",
    ],
    "SE Asia Malaya": [
        "Kuala Lumpur Valley", "Penang Island Edge", "Ipoh Tin Hills", "Johor Bahru Strait",
        "Malacca Coast", "Kota Bharu East", "Kuantan Shore", "Seremban Corridor",
    ],
    "SE Asia Sumatra": [
        "Medan Lowlands", "Palembang Musi", "Padang Highlands", "Pekanbaru Riau",
        "Bandar Lampung", "Jambi River", "Bengkulu Coast", "Aceh North Shore",
    ],
    "SE Asia Java": [
        "Jakarta Batavia", "Surabaya East Java", "Bandung Highlands", "Semarang Coast",
        "Yogyakarta Court", "Solo Valley", "Malang Hills", "Cirebon Shore",
    ],
    "SE Asia Borneo": [
        "Pontianak Equator", "Banjarmasin River", "Samarinda Mahakam", "Balikpapan Bay",
        "Kuching Sarawak", "Kota Kinabalu", "Tarakan Oil Shore", "Palangkaraya Interior",
    ],
    "SE Asia Philippines Luzon": [
        "Manila Bay", "Quezon City Belt", "Baguio Cordillera", "Clark Central Plain",
        "Subic Harbor", "Batangas Coast", "Legazpi Bicol", "Laoag Ilocos",
        "Cabanatuan Plain",
    ],
    "SE Asia Philippines Visayas": [
        "Cebu Harbor", "Iloilo Shore", "Bacolod Negros", "Tacloban Leyte",
        "Tagbilaran Bohol", "Roxas Capiz", "Dumaguete Coast",
    ],
    "SE Asia Burma Corridor": [
        "Rangoon Irrawaddy", "Mandalay Plain", "Pegu Corridor", "Moulmein Coast",
        "Bassein Delta", "Taunggyi Shan", "Meiktila Dry Zone", "Sittwe Arakan",
    ],
    "SE Asia Thailand Plain": [
        "Bangkok Chao Phraya", "Ayutthaya Ruins", "Nakhon Ratchasima", "Chiang Mai Valley",
        "Hat Yai South", "Khon Kaen Plateau", "Udon Thani North",
    ],
    "SE Asia Celebes": [
        "Makassar Harbor", "Manado North", "Palu Valley", "Kendari Southeast",
        "Gorontalo Coast", "Parepare Shore",
    ],
    # Pacific
    "Pacific Marianas": [
        "Saipan Lagoon", "Tinian Airfield Belt", "Rota Shore", "Guam Apra Harbor",
        "Garapan Coast", "Marpi Point", "Orote Peninsula",
    ],
    "Pacific Carolines": [
        "Truk Lagoon", "Ponape Uplands", "Yap Outer Reef", "Kosrae Shore",
        "Woleai Atoll", "Ulithi Anchorage", "Palau Babeldaob Edge",
    ],
    "Pacific Marshalls": [
        "Kwajalein Atoll", "Majuro Lagoon", "Eniwetok Ring", "Bikini Atoll",
        "Jaluit Harbor", "Wotje Reef", "Mili Atoll",
    ],
    "Pacific Solomons": [
        "Guadalcanal North", "Tulagi Harbor", "Bougainville Coast", "New Georgia Sound",
        "Malaita Hills", "Santa Isabel Shore", "Choiseul Coast", "Russell Islands",
    ],
    "Pacific New Guinea North": [
        "Wewak Coast", "Madang Harbor", "Lae Markham", "Rabaul Blanche Bay",
        "Aitape Shore", "Hollandia Harbor", "Wau Highlands", "Finschhafen Tip",
        "Buna Beachhead",
    ],
    "Pacific New Guinea South": [
        "Port Moresby Harbor", "Milne Bay", "Kerema Gulf", "Daru Strait",
        "Fly River Mouth", "Oro Bay", "Gona Coast",
    ],
    "Pacific Gilberts": [
        "Tarawa Atoll", "Makin Islands", "Abemama Lagoon", "Butaritari Reef",
        "Nonouti Atoll", "Tabiteuea Shore",
    ],
    "Pacific Fiji Cluster": [
        "Suva Harbor", "Nadi Coast", "Lautoka Cane", "Labasa Vanua",
        "Levuka Ovalau", "Savusavu Bay", "Sigatoka Valley",
    ],
    "Pacific New Britain": [
        "Rabaul Caldera", "Kokopo Shore", "Kimbe Bay", "Gasmata Coast",
        "Cape Gloucester", "Jacquinot Bay",
    ],
    # Oceania
    "Oceania SE Australia": [
        "Sydney Harbor Belt", "Newcastle Hunter", "Wollongong Illawarra", "Gosford Coast",
        "Blue Mountains Edge", "Parramatta River", "Port Kembla Works", "Central Coast Ridge",
    ],
    "Oceania Victoria": [
        "Melbourne Port", "Geelong Bay", "Ballarat Goldfields", "Bendigo Diggings",
        "Latrobe Valley", "Shepparton Irrigation", "Mildura Murray", "Warrnambool Coast",
    ],
    "Oceania Queensland Coast": [
        "Brisbane River", "Gold Coast Strip", "Sunshine Coast", "Townsville Harbor",
        "Cairns Tropical", "Rockhampton Capricorn", "Mackay Cane", "Gladstone Port",
    ],
    "Oceania NZ North": [
        "Auckland Isthmus", "Wellington Harbor", "Hamilton Waikato", "Tauranga Bay",
        "Rotorua Thermal", "Napier Hawke Bay", "Palmerston North",
    ],
    "Oceania NZ South": [
        "Christchurch Plains", "Dunedin Harbor", "Invercargill Southland", "Queenstown Lakes",
        "Nelson Tasman", "Timaru Coast",
    ],
    "Oceania Tasmania": [
        "Hobart Derwent", "Launceston Tamar", "Devonport North", "Burnie Coast",
        "Queenstown West",
    ],
    "Oceania Perth Coast": [
        "Perth Swan", "Fremantle Port", "Geraldton Mid West", "Bunbury Southwest",
        "Kalgoorlie Goldfields", "Albany Great Southern",
    ],
    # South America
    "SA Argentina Pampas": [
        "Buenos Aires Pampa", "Rosario Parana", "La Plata Shore", "Mar del Plata Coast",
        "Bahia Blanca Port", "Santa Fe River", "Cordoba Sierras Edge", "Tucuman North",
        "Mendoza Foothills Edge", "Parana Entre Rios",
    ],
    "SA Argentina Northwest": [
        "Salta Valley", "Jujuy Quebrada", "Catamarca Desert", "La Rioja Foothills",
        "Santiago del Estero", "Tucuman Cane", "Oran Border",
    ],
    "SA Chile Central": [
        "Santiago Central Valley", "Valparaiso Harbor", "Concepcion Bio Bio", "Vina del Mar Coast",
        "Rancagua Copper Edge", "Talca Maule", "Temuco Araucania", "Antofagasta North Edge",
    ],
    "SA Peru Coast": [
        "Lima Callao", "Arequipa Volcanic", "Trujillo North Coast", "Chiclayo Lambayeque",
        "Ica Desert", "Piura North", "Cusco Highland Edge", "Pisco Coast",
    ],
    "SA Colombia Andes": [
        "Bogota Sabana", "Medellin Aburra", "Cali Cauca", "Barranquilla Caribbean",
        "Cartagena Forts", "Bucaramanga Plateau", "Pereira Coffee", "Manizales Cordillera",
    ],
    "SA Venezuela Coast": [
        "Caracas Valley", "Maracaibo Oil Shore", "Valencia Lake", "Barcelona Anzoategui",
        "Puerto La Cruz", "Cumana East", "Barquisimeto Hills",
    ],
    "SA Uruguay": [
        "Montevideo Harbor", "Salto Uruguay River", "Paysandu Shore", "Maldonado Coast",
        "Rivera Border", "Colonia del Sacramento",
    ],
    "SA Bolivia Altiplano": [
        "La Paz Bowl", "El Alto Ridge", "Oruro Mining", "Potosi Silver",
        "Cochabamba Valley", "Santa Cruz Lowlands Edge", "Sucre Highlands",
    ],
    "SA Paraguay": [
        "Asuncion Bay", "Ciudad del Este", "Encarnacion South", "Concepcion North",
        "Villarrica Hills", "Pedro Juan Caballero",
    ],
    # Central Asia
    "CA Kazakhstan Steppe": [
        "Almaty Foothills", "Astana Steppe", "Karaganda Coal", "Shymkent Oasis",
        "Atyrau Caspian", "Aktobe West", "Pavlodar Irtysh", "Semey East",
        "Kostanay Grain",
    ],
    "CA Uzbekistan Oasis": [
        "Tashkent Oasis", "Samarkand Silk", "Bukhara Desert Edge", "Khiva Khorezm",
        "Andijan Fergana", "Namangan Valley", "Nukus Aral Edge", "Termez Amu",
    ],
    "CA Turkmen Corridor": [
        "Ashgabat Kopet Dag", "Turkmenbashi Port", "Mary Oasis", "Dashoguz North",
        "Balkanabat Oil", "Tejen Corridor",
    ],
    "CA Xinjiang West": [
        "Urumqi Basin", "Kashgar Oasis", "Turpan Depression", "Yining Ili",
        "Hotan Desert Edge", "Aksu Tarim", "Korla Corridor", "Hami Gateway",
    ],
    "CA Afghanistan Hindu Kush": [
        "Kabul Basin", "Kandahar Oasis", "Herat West", "Mazar-i-Sharif",
        "Jalalabad Corridor", "Kunduz North", "Ghazni Plateau", "Bamyan Highlands",
    ],
    "CA Mongolia Steppe": [
        "Ulaanbaatar Basin", "Darkhan North", "Erdenet Mining", "Choibalsan East",
        "Khovd West", "Murun North", "Dalanzadgad South", "Bayankhongor Steppe",
    ],
    "CA Tajik Pamirs": [
        "Dushanbe Valley", "Khujand Fergana Edge", "Khorog Pamir", "Kulob South",
        "Qurghonteppa Lowland", "Isfara Border",
    ],
}

# Extra descriptors if a hub pool is exhausted.
_EXTRA_DESCRIPTORS = [
    "North Reach", "South Reach", "East Spur", "West Spur", "Central Basin",
    "Upland Ridge", "Coastal Belt", "River Bend", "Plateau Edge", "Lowland Flats",
    "Mining District", "Harbor Approaches", "Interior Corridor", "Frontier March",
    "Trade Crossroads", "Agricultural Heart", "Industrial Belt", "Highland Pass",
]


def strip_numbered_hub(name: str) -> Optional[str]:
    m = NUMBERED_HUB_RE.match(str(name).strip())
    if not m:
        return None
    return m.group("hub").strip()


def is_numbered_hub_label(name: str) -> bool:
    return strip_numbered_hub(name) is not None


def is_placeholder_name(name: str) -> bool:
    n = str(name or "").strip()
    return not n or bool(PLACEHOLDER_RE.match(n))


def _next_unique(candidate: str, used: set) -> str:
    base = candidate.strip()
    if not base:
        base = "Unnamed District"
    if base not in used and base.lower() not in {u.lower() for u in used}:
        return base
    # Case-insensitive uniqueness
    lower_used = {u.lower() for u in used}
    if base.lower() not in lower_used:
        return base
    i = 2
    while True:
        # Prefer geographic lettered sectors over bare digits alone
        cand = f"{base} Sector {chr(64 + min(i, 26))}" if i <= 26 else f"{base} District {i}"
        if cand.lower() not in lower_used:
            return cand
        i += 1


def assign_hotspot_names(
    provinces: List[Dict[str, Any]],
    *,
    only_hotspot: bool = True,
) -> Dict[str, Any]:
    """Return rename stats and mutate province name fields in-place.

    Only renames hotspot_densify provinces whose names match numbered hub pattern
    (or placeholders). All resulting names are unique across the full list.
    """
    used: set = set()
    for p in provinces:
        n = str(p.get("name") or "").strip()
        if n and not (p.get("hotspot_densify") and is_numbered_hub_label(n)):
            if not is_placeholder_name(n):
                used.add(n)

    renamed = 0
    skipped = 0
    by_hub: Dict[str, int] = {}
    hub_counters: Dict[str, int] = {}

    for p in provinces:
        if only_hotspot and not p.get("hotspot_densify"):
            continue
        old = str(p.get("name") or "").strip()
        hub = strip_numbered_hub(old)
        if hub is None and not is_placeholder_name(old):
            # Already human-readable densify name
            if old:
                used.add(old)
            skipped += 1
            continue

        hub_key = hub or "Unplaced Densify"
        pool = list(HUB_GAZETTEERS.get(hub_key) or [])
        idx = hub_counters.get(hub_key, 0)
        hub_counters[hub_key] = idx + 1

        if idx < len(pool):
            candidate = pool[idx]
        else:
            # Exhausted pool: compose human-readable name from hub + descriptor
            desc_i = idx - len(pool)
            if desc_i < len(_EXTRA_DESCRIPTORS):
                short = hub_key.split()[-2:] if hub_key else ["District"]
                candidate = f"{' '.join(short)} {_EXTRA_DESCRIPTORS[desc_i]}"
            else:
                candidate = f"{hub_key} {_EXTRA_DESCRIPTORS[desc_i % len(_EXTRA_DESCRIPTORS)]} {desc_i + 1}"

        new_name = _next_unique(candidate, used)
        if new_name != old:
            p["name"] = new_name
            p["hotspot_name_source"] = "assign_world_hotspot_names"
            p["hotspot_hub"] = hub_key
            renamed += 1
            by_hub[hub_key] = by_hub.get(hub_key, 0) + 1
        used.add(new_name)

    # Global uniqueness pass (case-insensitive): rename densify satellites on clash.
    collisions_fixed = 0
    occupied: set = set()
    for p in provinces:
        n = str(p.get("name") or "").strip()
        if not n:
            n = _next_unique(f"Unnamed {p.get('id')}", occupied)
            p["name"] = n
            collisions_fixed += 1
        key = n.lower()
        if key in occupied:
            if p.get("hotspot_densify") or is_placeholder_name(n):
                n = _next_unique(n, occupied)
                p["name"] = n
                collisions_fixed += 1
            else:
                # Rare non-hotspot collision: still uniquify to satisfy dataset gate
                n = _next_unique(n, occupied)
                p["name"] = n
                collisions_fixed += 1
        occupied.add(n.lower())

    names = [str(p.get("name") or "") for p in provinces]
    unique = len({n.lower() for n in names}) == len(names)
    numbered_left = sum(
        1
        for p in provinces
        if p.get("hotspot_densify") and is_numbered_hub_label(str(p.get("name") or ""))
    )
    placeholders = sum(1 for p in provinces if is_placeholder_name(str(p.get("name") or "")))

    return {
        "renamed": renamed,
        "skipped": skipped,
        "by_hub": by_hub,
        "collisions_fixed": collisions_fixed,
        "unique": unique,
        "numbered_hub_remaining": numbered_left,
        "placeholders": placeholders,
        "province_count": len(provinces),
    }


def quality_gates(provinces: List[Dict[str, Any]]) -> Dict[str, Any]:
    names = [str(p.get("name") or "").strip() for p in provinces]
    lower = [n.lower() for n in names]
    hot = [p for p in provinces if p.get("hotspot_densify")]
    return {
        "all_unique": len(set(lower)) == len(lower),
        "no_empty": all(bool(n) for n in names),
        "no_placeholders": all(not is_placeholder_name(n) for n in names),
        "hotspot_no_numbered_hub": all(
            not is_numbered_hub_label(str(p.get("name") or "")) for p in hot
        ),
        "hotspot_count": len(hot),
    }


def run_on_dir(data_dir: Path, write: bool = False) -> Dict[str, Any]:
    base_path = data_dir / "provinces_base.json"
    base = json.loads(base_path.read_text(encoding="utf-8"))
    provinces = list(base["provinces"])
    stats = assign_hotspot_names(provinces)
    gates = quality_gates(provinces)
    stats["gates"] = gates
    if not write:
        stats["wrote"] = False
        return stats
    base["provinces"] = provinces
    meta = dict(base.get("meta") or {})
    meta["hotspot_names_assigned"] = stats["renamed"]
    meta["hotspot_names_unique"] = gates["all_unique"]
    base["meta"] = meta
    base_path.write_text(json.dumps(base, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    stats["wrote"] = True
    return stats


def main(argv: Optional[Sequence[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", default="data/provinces_world_full")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)
    data_dir = Path(args.dir)
    if not data_dir.is_absolute():
        data_dir = ROOT / data_dir
    write = bool(args.write) and not args.dry_run
    stats = run_on_dir(data_dir, write=write)
    print(("[WROTE]" if write else "[DRY-RUN]"), stats)
    gates = stats.get("gates") or {}
    ok = (
        gates.get("all_unique")
        and gates.get("no_placeholders")
        and gates.get("hotspot_no_numbered_hub")
        and stats.get("renamed", 0) + (0 if write else 1) >= 0
    )
    # On already-named board, renamed may be 0 but gates must pass
    ok = bool(gates.get("all_unique") and gates.get("no_placeholders") and gates.get("hotspot_no_numbered_hub"))
    print("PASS hotspot names" if ok else "FAIL hotspot names", file=sys.stdout if ok else sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
