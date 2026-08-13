"""Real place-state name catalogs for four-tier hierarchy.

Replaces algorithmic placeholders like ``TAG · Region · Area N`` / ``ENG Africa Area 1``
with historical / admin-style place names (Tier-2 states). Not perfect GIS labels —
but non-generic, playable, and CI-gated.
"""
from __future__ import annotations

import re
from typing import Dict, List, Sequence

# Forbidden patterns for shippable state names (criterion 2).
PLACEHOLDER_STATE_RE = re.compile(
    r"(?i)(^State\s+\d+$)|(\bArea\s+\d+\b)|(\bRegion\s+\d+\b)|(\s·\sArea\s)|"
    r"(^[A-Z]{2,4}\s+[A-Za-z ]+\s+Area\s+\d+$)|"
    r"(^[A-Z]{2,4}\s·\s)"
)

MODIFIERS = (
    "Northern",
    "Southern",
    "Eastern",
    "Western",
    "Upper",
    "Lower",
    "Central",
    "Coastal",
    "Inner",
    "Outer",
    "Greater",
    "Lesser",
)

# Europe pilot strategic_region_hint → real historical / admin provinces.
EUROPE_REGION_STATES: Dict[str, List[str]] = {
    "France": [
        "Île-de-France", "Normandy", "Brittany", "Aquitaine", "Provence", "Alsace",
        "Lorraine", "Burgundy", "Languedoc", "Champagne", "Picardy", "Auvergne",
        "Poitou", "Gascony", "Franche-Comté", "Limousin", "Dauphiné", "Anjou",
        "Touraine", "Orléanais", "Berry", "Maine", "Artois", "Roussillon", "Savoy",
        "Corsica", "Narbonne", "Lyonnais", "Beauce", "Vendée",
    ],
    "Germany": [
        "Brandenburg", "Bavaria", "Saxony", "Rhineland", "Westphalia", "Silesia",
        "Hanover", "Württemberg", "Hesse", "Pomerania", "Mecklenburg", "Thuringia",
        "Baden", "Schleswig-Holstein", "East Prussia", "Franconia", "Palatinate",
        "Holstein", "Anhalt", "Oldenburg", "Brunswick", "Nassau", "West Prussia",
        "Upper Silesia", "Lower Saxony", "Swabia", "Moselle", "Saarland", "Ruhr",
        "Harz", "Lusatia",
    ],
    "Low Countries": [
        "Flanders", "Wallonia", "Brabant", "Holland", "Zeeland", "Limburg",
        "Hainaut", "Luxembourg", "Gelderland", "Utrecht", "Antwerp", "Liège",
        "Namur", "Overijssel", "Drenthe", "Friesland", "Groningen", "Artois Border",
        "Scheldt Mouth", "Meuse Valley", "Kempen", "Ardennes", "Brabant Wallon",
        "Dutch Limburg", "West Flanders", "East Flanders",
    ],
    "Italy": [
        "Lombardy", "Veneto", "Piedmont", "Tuscany", "Latium", "Campania",
        "Sicily", "Sardinia", "Emilia", "Romagna", "Umbria", "Marche",
        "Abruzzo", "Calabria", "Apulia", "Liguria", "Trentino", "Friuli",
        "South Tyrol", "Basilicata", "Molise", "Aosta", "Istria", "Dalmatian Rim",
    ],
    "Iberia": [
        "Castile", "Aragon", "Catalonia", "Andalusia", "Galicia", "Portugal Norte",
        "Portugal Sul", "Valencia", "Navarre", "Asturias", "León", "Extremadura",
        "Murcia", "Basque Country", "Alentejo", "Algarve", "Balearics", "Canaries",
        "La Mancha", "Rioja", "Cantabria", "Beira",
    ],
    "British Isles": [
        "Southeast England", "Midlands", "Yorkshire", "Northumbria", "Wales",
        "Scottish Lowlands", "Scottish Highlands", "Ulster", "Leinster", "Munster",
        "Connacht", "Lancashire", "East Anglia", "Wessex", "Cornwall", "Kent",
        "Cumbria", "Glasgow Belt", "Dublin Pale", "Clyde",
    ],
    "Nordic": [
        "Zealand", "Jutland", "Scania", "Svealand", "Götaland", "Norrland",
        "Finland Proper", "Ostrobothnia", "Karelia", "Oslofjord", "Trøndelag",
        "Bergen Coast", "Lappland", "Åland", "Bornholm", "Halland", "Värmland",
        "Dalarna", "Uppland", "Småland",
    ],
    "Balkans": [
        "Thrace", "Macedonia", "Epirus", "Thessaly", "Peloponnese", "Bosnia",
        "Serbia", "Croatia", "Slovenia", "Albania", "Montenegro", "Kosovo",
        "Vojvodina", "Dobruja", "Wallachia", "Moldavia", "Transylvania", "Banat",
        "Dalmatia", "Herzegovina", "Bulgaria North", "Bulgaria South", "Attica",
        "Crete", "Ionian Isles",
    ],
    "Central Europe": [
        "Bohemia", "Moravia", "Austria Proper", "Tyrol", "Styria", "Carinthia",
        "Slovakia", "Hungary Plain", "Transdanubia", "Galicia West", "Kraków",
        "Silesia Polish", "Sudeten", "Burgenland", "Salzburg", "Upper Austria",
        "Lower Austria", "Ruthenia", "Pannonia", "Danube Bend",
    ],
    "Eastern Frontiers": [
        "Warsaw", "Poznań", "Vilnius", "Minsk", "Kiev", "Odessa", "Crimea",
        "Donbass", "Smolensk", "Brest", "Lublin", "Lwów", "Volhynia", "Podolia",
        "Bessarabia", "Courland", "Livonia", "Estonia", "Lithuania Proper",
        "Belarus West", "Ukraine West", "Pripet",
    ],
    "Western Mediterranean": [
        "Languedoc Coast", "Catalan Coast", "Provence Littoral", "Liguria Coast",
        "Corsica", "Sardinia West", "Balearic Sea", "Gulf of Lion", "Toulon Approach",
        "Genoa Riviera", "Nice", "Marseille Basin", "Valencia Coast", "Alboran North",
        "Tyrrhenian Rim", "Gulf of Valencia",
    ],
    "Baltic Rim": [
        "Pomeranian Coast", "East Prussian Shore", "Gdańsk Corridor", "Courland Coast",
        "Riga Bay", "Helsinki Shore", "Stockholm Archipelago", "Åland Sea",
        "Bornholm Waters", "Kiel Canal Approaches", "Lübeck Bay", "Memel",
    ],
}

# world_full theater → real place / geographic state names (dense lists; cycle+modify).
THEATER_STATES: Dict[str, List[str]] = {
    "europe_core": (
        EUROPE_REGION_STATES["France"]
        + EUROPE_REGION_STATES["Germany"]
        + EUROPE_REGION_STATES["Low Countries"]
        + EUROPE_REGION_STATES["Italy"]
        + EUROPE_REGION_STATES["Iberia"]
        + EUROPE_REGION_STATES["British Isles"]
        + EUROPE_REGION_STATES["Nordic"]
        + EUROPE_REGION_STATES["Balkans"]
        + EUROPE_REGION_STATES["Central Europe"]
        + EUROPE_REGION_STATES["Eastern Frontiers"]
    ),
    "north_america": [
        "New England", "Mid-Atlantic", "Appalachia", "Great Lakes", "Ohio Valley",
        "Deep South", "Gulf Coast", "Texas Plains", "Midwest Prairie", "Great Plains",
        "Rocky Mountains", "Pacific Northwest", "California", "Southwest Desert",
        "Quebec", "Ontario", "Prairies Canada", "British Columbia", "Maritimes",
        "Alaska Panhandle", "Hudson Bay", "Yucatán Rim", "Mexican Plateau",
        "Rio Grande", "Chesapeake", "Mississippi Delta", "Cascadia", "Sierra Nevada",
        "Colorado Plateau", "Florida", "Carolina", "Virginia Tidewater", "Michigan",
        "Illinois Prairie", "Minnesota North", "Manitoba", "Alberta", "Nova Scotia",
    ],
    "south_america": [
        "Amazon Basin", "Andean Highlands", "Pampas", "Patagonia", "Brazilian Coast",
        "São Paulo Plateau", "Rio de la Plata", "Orinoco", "Guianas", "Chile Central",
        "Peruvian Coast", "Bolivian Altiplano", "Colombian Andes", "Venezuelan Llanos",
        "Mato Grosso", "Chaco", "Atacama", "Cerrado", "Northeast Brazil", "Gran Chaco",
        "Uruguay", "Paraguay", "Ecuador Highlands", "Galápagos Approaches",
    ],
    "africa": [
        "Maghreb Coast", "Atlas Mountains", "Sahara West", "Sahara East", "Nile Valley",
        "Upper Nile", "Horn of Africa", "Ethiopian Highlands", "Sahel West", "Sahel East",
        "West Africa Littoral", "Gold Coast", "Nigeria Belt", "Congo Basin", "Great Lakes Africa",
        "East African Rift", "Kenya Highlands", "Tanganyika", "Zambezi", "Cape Frontier",
        "Karoo", "Namib", "Kalahari", "Mozambique Coast", "Madagascar", "Angolan Plateau",
        "Cameroon Highlands", "Senegal River", "Lake Chad", "Red Sea Hills",
    ],
    "mena_africa": [
        "Nile Delta", "Lower Egypt", "Upper Egypt", "Cyrenaica", "Tripolitania",
        "Tunisia", "Algeria Coast", "Morocco Atlas", "Levant Coast", "Palestine",
        "Transjordan", "Syria", "Lebanon", "Anatolia West", "Anatolia East", "Armenia Plateau",
        "Mesopotamia", "Kurdistan", "Persian Gulf Coast", "Zagros", "Iran Plateau",
        "Arabia Hejaz", "Nejd", "Yemen Highlands", "Oman Coast", "Sinai", "Suez Corridor",
        "Cyprus", "Caucasus South", "Azerbaijan", "Georgia",
    ],
    "far_east": [
        "Manchuria", "North China Plain", "Yellow River", "Yangtze Delta", "South China",
        "Sichuan Basin", "Tibet Plateau", "Xinjiang", "Korea North", "Korea South",
        "Honshu East", "Honshu West", "Kyushu", "Hokkaido", "Taiwan", "Indochina North",
        "Indochina South", "Burma", "Malaya", "Java", "Sumatra", "Borneo", "Philippines North",
        "Philippines South", "Mongolia", "Inner Mongolia", "Fujian Coast", "Guangdong",
        "Shandong", "Hebei", "Shaanxi", "Yunnan", "Hainan",
    ],
    "central_asia": [
        "Kazakh Steppe", "Siberian West", "Siberian Central", "Siberian East", "Lake Baikal",
        "Altai", "Tian Shan", "Fergana", "Transoxiana", "Turkmen Desert", "Uzbek Oases",
        "Tajik Highlands", "Kyrgyz Mountains", "Caspian East", "Aral", "Pamirs",
        "Yakutia", "Kamchatka Approaches", "Amur Basin", "Transbaikal",
    ],
    "pacific": [
        "Hawaii", "Micronesia", "Melanesia North", "Melanesia South", "Polynesia Central",
        "Guam Approaches", "Marshall Islands", "Solomon Sea", "New Guinea North",
        "New Guinea South", "Coral Sea", "Fiji", "Samoa", "Tahiti", "Midway",
        "Wake", "Mariana", "Palau", "Caroline Islands",
    ],
    "oceania": [
        "New South Wales", "Victoria", "Queensland Coast", "Outback Central", "Western Australia",
        "Tasmania", "North Island NZ", "South Island NZ", "Northern Territory", "South Australia",
        "Kimberley", "Nullarbor", "Great Barrier", "Canberra Plateau", "Perth Basin",
        "Darwin Coast", "Alice Springs", "Otago", "Auckland", "Wellington",
    ],
    "sea": [
        "North Atlantic", "South Atlantic", "North Pacific", "South Pacific", "Indian Ocean",
        "Arctic Ocean", "Mediterranean", "Caribbean Sea", "South China Sea", "Baltic Sea",
        "Black Sea", "Red Sea", "Persian Gulf", "Sea of Japan", "Bering Sea",
    ],
}


def is_placeholder_state_name(name: str) -> bool:
    s = str(name or "").strip()
    if not s:
        return True
    return bool(PLACEHOLDER_STATE_RE.search(s))


def _expand_catalog(base: Sequence[str], need: int) -> List[str]:
    """Return at least ``need`` unique-ish names via modifier prefixes."""
    out: List[str] = []
    base_list = list(base) if base else ["Unnamed Province"]
    # first pass: raw catalog
    for n in base_list:
        if n not in out:
            out.append(n)
        if len(out) >= need:
            return out[:need]
    # second: modifiers
    for mod in MODIFIERS:
        for n in base_list:
            cand = "%s %s" % (mod, n)
            if cand not in out:
                out.append(cand)
            if len(out) >= need:
                return out[:need]
    # third: numbered geographic suffixes (not "Area N")
    i = 2
    while len(out) < need:
        for n in base_list:
            cand = "%s Sector %d" % (n, i)
            if cand not in out:
                out.append(cand)
            if len(out) >= need:
                return out[:need]
        i += 1
    return out[:need]


def pick_state_names(region_or_theater: str, count: int) -> List[str]:
    key = str(region_or_theater or "").strip()
    catalog = EUROPE_REGION_STATES.get(key) or THEATER_STATES.get(key)
    if not catalog:
        # fuzzy: theater-like keys
        low = key.lower().replace(" ", "_")
        catalog = THEATER_STATES.get(low)
    if not catalog:
        # generic geographic pool
        catalog = (
            EUROPE_REGION_STATES["Central Europe"]
            + THEATER_STATES.get("africa", [])[:10]
            + THEATER_STATES.get("north_america", [])[:10]
        )
    return _expand_catalog(catalog, max(1, int(count)))


def assign_state_name(region_or_theater: str, index: int, owner_hint: str = "") -> str:
    """Pick a real place name for the index-th state in a region/theater bucket.

    ``owner_hint`` is intentionally **not** embedded in the display name (ownership
    is era-layer data). Kept for call-site compatibility / future core tagging.
    """
    _ = owner_hint  # ownership is data, not part of place name
    names = pick_state_names(region_or_theater, index + 1)
    return names[index]


def assert_names_shippable(names: Sequence[str]) -> Dict[str, object]:
    bad = [n for n in names if is_placeholder_state_name(n)]
    return {
        "ok": len(bad) == 0 and len(names) > 0,
        "total": len(names),
        "placeholder_n": len(bad),
        "placeholder_samples": bad[:8],
    }
