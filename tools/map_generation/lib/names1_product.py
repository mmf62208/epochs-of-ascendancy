"""NAMES-1 pure classifiers and province display-name proposals.

Land names on ``provinces_base.json`` (id < 950000). Sea zones are out of
scope. Pinned ids keep the stored name because a test or the display
contract quotes it. ``proposed_name`` is deterministic given ``ADMIN_HITS``
(geoBoundaries lookups filled by ``apply_names1.py`` from ``~/names1/scratch``,
not committed).
"""
from __future__ import annotations

import re
import unicodedata
from typing import Dict, Iterable, List, Mapping, MutableMapping, Optional, Sequence, Tuple

# Land vs sea. Sea zones are never renamed.
SEA_ID = 950000

# <TAG> <Direction>. Ship measured 366 of these on 5d099346 (four cardinals only).
TAG_DIR_RE = re.compile(r"^[A-Z]{3} (North|South|East|West)$")

# Generator suffix. Ship's 630 excludes three CJK names that also match this
# and the non-Latin pattern; this pattern matches every trailing " area".
AREA_RE = re.compile(r" area$")

# Letters outside the Latin script. Typographic quotes and em dashes on
# otherwise Latin names (Côte-d’Or, Val-d’Oise) are not matches. Ship's 128
# count is this set plus nine Latin names whose only non-ASCII marks are
# punctuation; those stay.
NONLATIN_RE = re.compile(
    "["
    "\u0370-\u03ff\u1f00-\u1fff"  # Greek
    "\u0400-\u04ff\u0500-\u052f"  # Cyrillic
    "\u0530-\u058f"  # Armenian
    "\u0590-\u05ff"  # Hebrew
    "\u0600-\u06ff\u0750-\u077f"  # Arabic
    "\u0900-\u097f"  # Devanagari
    "\u0e00-\u0e7f"  # Thai
    "\u10a0-\u10ff"  # Georgian
    "\u3040-\u30ff"  # Hiragana / Katakana
    "\u3400-\u4dbf\u4e00-\u9fff"  # CJK
    "\uac00-\ud7af"  # Hangul
    "]"
)

# Tag-prefixed leftovers that are not <TAG> <Direction>.
ODDITY_RE = re.compile(r"^ATA region$|^NCR, .+ District$")

# Ids whose stored name a string literal guards. file:line is the pinning site.
# CHN cardinal blobs are asserted one id at a time in test_nation_tags1.
# 903492 stays "RUS West" because MapPolishFormatters rewrites that exact
# string (and that pid) to "Western Russia". The other "RUS West" (903493)
# is not pinned: the same ``n == "RUS West"`` branch would mislabel it.
PINNED_NAME_IDS: Dict[int, str] = {
    903492: "scripts/map/MapPolishFormatters.gd:663",
    902487: "tools/map_generation/tests/test_nation_tags1.py:183",
    902491: "tools/map_generation/tests/test_nation_tags1.py:184",
    902493: "tools/map_generation/tests/test_nation_tags1.py:185",
    902496: "tools/map_generation/tests/test_nation_tags1.py:186",
    902504: "tools/map_generation/tests/test_nation_tags1.py:187",
    902505: "tools/map_generation/tests/test_nation_tags1.py:188",
    902514: "tools/map_generation/tests/test_nation_tags1.py:189",
    902521: "tools/map_generation/tests/test_nation_tags1.py:190",
    902523: "tools/map_generation/tests/test_nation_tags1.py:191",
    902526: "tools/map_generation/tests/test_nation_tags1.py:192",
    902534: "tools/map_generation/tests/test_nation_tags1.py:193",
    902544: "tools/map_generation/tests/test_nation_tags1.py:194",
    902564: "tools/map_generation/tests/test_nation_tags1.py:195",
    902566: "tools/map_generation/tests/test_nation_tags1.py:196",
    902568: "tools/map_generation/tests/test_nation_tags1.py:197",
    902569: "tools/map_generation/tests/test_nation_tags1.py:198",
    902590: "tools/map_generation/tests/test_nation_tags1.py:199",
    902598: "tools/map_generation/tests/test_nation_tags1.py:200",
    902601: "tools/map_generation/tests/test_nation_tags1.py:201",
    902633: "tools/map_generation/tests/test_nation_tags1.py:202",
    902634: "tools/map_generation/tests/test_nation_tags1.py:203",
    902646: "tools/map_generation/tests/test_nation_tags1.py:204",
    # Exact stored names asserted on these ids. Disambiguation must not suffix them.
    710173: "tools/map_generation/tests/test_maginot_land_uniformity_product.py:57",
    710671: "tools/map_generation/tests/test_caribbean_island_sizing_feed6_product.py:140",
    710679: "tools/map_generation/tests/test_caribbean_island_sizing_feed6_product.py:141",
    710734: "tools/map_generation/tests/test_flanders_nord_land_uniformity_product.py:66",
    710735: "tools/map_generation/tests/test_flanders_nord_land_uniformity_product.py:69",
    710739: "tools/map_generation/tests/test_maginot_land_uniformity_product.py:58",
    710804: "tools/map_generation/tests/test_caribbean_island_sizing_feed6_product.py:88",
    710870: "tools/map_generation/tests/test_seas_coarsen_feed8_ligurian_product.py:86",
    710963: "tools/map_generation/tests/test_seas_coarsen_feed10_tyrrhenian_product.py:94",
    711438: "tools/map_generation/tests/test_se_england_shire_land_uniformity_product.py:82",
    711449: "tools/map_generation/tests/test_se_england_shire_land_uniformity_product.py:85",
    711520: "tools/map_generation/tests/test_flanders_nord_land_uniformity_product.py:70",
    800792: "tools/map_generation/tests/test_world_accurate_board.py:300",
    902398: "tools/map_generation/tests/test_caribbean_island_sizing_feed6_product.py:89",
    902486: "tools/map_generation/tests/test_hong_kong_island_land_product.py:77",
    905844: "tools/map_generation/tests/test_caribbean_island_sizing_feed6_product.py:92",
    905845: "tools/map_generation/tests/test_caribbean_island_sizing_feed6_product.py:94",
    905846: "tools/map_generation/tests/test_caribbean_island_sizing_feed6_product.py:95",
    905847: "tools/map_generation/tests/test_caribbean_island_sizing_feed6_product.py:96",
    905848: "tools/map_generation/tests/test_caribbean_island_sizing_feed6_product.py:97",
    906013: "tools/map_generation/tests/test_nation_tags1.py:176",
    906014: "tools/map_generation/tests/test_nation_tags1.py:177",
    906015: "tools/map_generation/tests/test_nation_tags1.py:178",
    906016: "tools/map_generation/tests/test_nation_tags1.py:179",
    906018: "tools/map_generation/tests/test_nation_tags1.py:180",
    906019: "tools/map_generation/tests/test_nation_tags1.py:181",
}

# Ids left unchanged because no confident Latin place name was found.
# Empty when the gazetteer covers every placeholder. Tests allow these.
UNKNOWN: Dict[int, str] = {}

# First-occurrence names asserted by test_nation_tags1. A lower id must not
# take the exact string or ``by_name.setdefault`` points at the wrong province.
_UKR_BLOCK = (
    "Vinnytsia",
    "Chernihiv",
    "Donetsk",
    "Smolensk",
    "Kursk",
    "Tula",
    "Stanislawow",
    "Tarnopol",
    "Rovno",
    "Drohobych",
    "Kovel",
)
_CHINA_BLOCK = (
    "Urumqi-Turfan",
    "U-Tsang (Lhasa)",
    "Changtang (N. Tibet)",
    "Xikang East (Kangding)",
    "Qinghai East (Xining)",
    "Ningxia",
    "Shanxi North (Datong)",
    "Shaanbei (Yanan)",
    "Guanzhong (Xian)",
    "Shaannan (Hanzhong)",
    "Henan North (Kaifeng)",
    "Henan South (Xinyang)",
    "Jiangsu North (Xuzhou)",
    "Jiangsu South (Shanghai-Nanking)",
    "Anhui North (Bengbu)",
    "Zhejiang North (Hangzhou)",
    "Zhejiang South (Wenzhou)",
    "Jiangxi North (Nanchang)",
    "Jiangxi South (Ganzhou)",
    "Hubei East (Wuhan)",
    "Hubei West (Yichang)",
    "Hunan South (Hengyang)",
    "Sichuan North (Nanchong)",
    "Yunnan West (Dali)",
    "Guangxi West (Nanning)",
    "Guangdong East (Swatow)",
    "Guangdong West (Leizhou)",
    "Hainan",
)
RESERVED_FIRST_NAME: Dict[str, int] = {}
RESERVED_FIRST_NAME.update({n: 906100 + i for i, n in enumerate(_UKR_BLOCK)})
RESERVED_FIRST_NAME.update({n: 906111 + i for i, n in enumerate(_CHINA_BLOCK)})

# NCR congressional districts are not 1936 municipalities. These three
# centroids sit in Rizal province as it was in 1936 (Quezon City is 1939).
NCR_1936: Dict[int, str] = {
    904687: "Parañaque",
    904688: "Marikina",
    904689: "Novaliches",
}

# Filled by apply_names1 from geoBoundaries before proposed_name runs.
# pid -> {iso, adm1, adm2, lat, lon}
ADMIN_HITS: Dict[int, Dict[str, object]] = {}

# English exonyms for the closed non-Latin set on this board.
# Bulgarian / Serbian / Macedonian: BGN/PCGN and the usual English district name.
# Greek: Eurostat NUTS English. CJK: Hanyu Pinyin without the 鎮/鄉 suffix.
EXONYMS: Dict[str, str] = {
    # Bulgaria oblasts
    "Видин": "Vidin",
    "Монтана": "Montana",
    "Враца": "Vratsa",
    "Плевен": "Pleven",
    "Ловеч": "Lovech",
    "Велико Търново": "Veliko Tarnovo",
    "Габрово": "Gabrovo",
    "Русе": "Ruse",
    "Разград": "Razgrad",
    "Силистра": "Silistra",
    "Варна": "Varna",
    "Добрич": "Dobrich",
    "Шумен": "Shumen",
    "Търговище": "Targovishte",
    "Бургас": "Burgas",
    "Сливен": "Sliven",
    "Ямбол": "Yambol",
    "Стара Загора": "Stara Zagora",
    "София (столица)": "Sofia City",
    "София": "Sofia",
    "Благоевград": "Blagoevgrad",
    "Перник": "Pernik",
    "Кюстендил": "Kyustendil",
    "Пловдив": "Plovdiv",
    "Хасково": "Haskovo",
    "Пазарджик": "Pazardzhik",
    "Смолян": "Smolyan",
    "Кърджали": "Kardzhali",
    # Cyprus / Greece NUTS
    "Κύπρος": "Cyprus",
    "Βόρειος Τομέας Αθηνών": "North Athens",
    "Δυτικός Τομέας Αθηνών": "West Athens",
    "Κεντρικός Τομέας Αθηνών": "Central Athens",
    "Νότιος Τομέας Αθηνών": "South Athens",
    "Ανατολική Αττική": "East Attica",
    "Δυτική Αττική": "West Attica",
    "Πειραιάς, Νήσοι": "Piraeus and Islands",
    "Λέσβος, Λήμνος": "Lesbos and Lemnos",
    "Ικαρία, Σάμος": "Ikaria and Samos",
    "Χίος": "Chios",
    "Κάλυμνος, Κάρπαθος – Ηρωική Νήσος Κάσος, Κως, Ρόδος": "Dodecanese",
    "Άνδρος, Θήρα, Κέα, Μήλος, Μύκονος, Νάξος, Πάρος, Σύρος, Τήνος": "Cyclades",
    "Ηράκλειο": "Heraklion",
    "Λασίθι": "Lasithi",
    "Ρέθυμνο": "Rethymno",
    "Χανιά": "Chania",
    "Έβρος": "Evros",
    "Ξάνθη": "Xanthi",
    "Ροδόπη": "Rhodope",
    "Δράμα": "Drama",
    "Θάσος, Καβάλα": "Thasos and Kavala",
    "Ημαθία": "Imathia",
    "Θεσσαλονίκη": "Thessaloniki",
    "Κιλκίς": "Kilkis",
    "Πέλλα": "Pella",
    "Πιερία": "Pieria",
    "Σέρρες": "Serres",
    "Χαλκιδική": "Chalkidiki",
    "Γρεβενά, Κοζάνη": "Grevena and Kozani",
    "Καστοριά": "Kastoria",
    "Φλώρινα": "Florina",
    "Άρτα, Πρέβεζα": "Arta and Preveza",
    "Θεσπρωτία": "Thesprotia",
    "Ιωάννινα": "Ioannina",
    "Καρδίτσα, Τρίκαλα": "Karditsa and Trikala",
    "Λάρισα": "Larissa",
    "Μαγνησία, Σποράδες": "Magnesia and Sporades",
    "Ζάκυνθος": "Zakynthos",
    "Κέρκυρα": "Corfu",
    "Ιθάκη, Κεφαλληνία": "Ithaca and Cephalonia",
    "Λευκάδα": "Lefkada",
    "Αιτωλοακαρνανία": "Aetolia-Acarnania",
    "Αχαΐα": "Achaea",
    "Ηλεία": "Elis",
    "Βοιωτία": "Boeotia",
    "Εύβοια": "Euboea",
    "Ευρυτανία": "Evrytania",
    "Φθιώτιδα": "Phthiotis",
    "Φωκίδα": "Phocis",
    "Αργολίδα, Αρκαδία": "Argolis and Arcadia",
    "Κορινθία": "Corinthia",
    "Λακωνία, Μεσσηνία": "Laconia and Messenia",
    # Montenegro / North Macedonia statistical regions
    "Црна Гора": "Montenegro",
    "Вардарски": "Vardar",
    "Источен": "Eastern Macedonia",
    "Југозападен": "Southwestern Macedonia",
    "Југоисточен": "Southeastern Macedonia",
    "Пелагониски": "Pelagonia",
    "Полошки": "Polog",
    "Североисточен": "Northeastern Macedonia",
    "Скопски": "Skopje",
    # Serbia districts (област dropped; English exonym)
    "Београдска област": "Belgrade",
    "Западнобачка област": "West Backa",
    "Јужнобанатска област": "South Banat",
    "Јужнобачка област": "South Backa",
    "Севернобанатска област": "North Banat",
    "Севернобачка област": "North Backa",
    "Средњобанатска област": "Central Banat",
    "Сремска област": "Syrmia",
    "Златиборска област": "Zlatibor",
    "Колубарска област": "Kolubara",
    "Мачванска област": "Macva",
    "Моравичка област": "Moravica",
    "Поморавска област": "Pomoravlje",
    "Расинска област": "Rasina",
    "Рашка област": "Raska",
    "Шумадијска област": "Sumadija",
    "Борска област": "Bor",
    "Браничевска област": "Branicevo",
    "Зајечарска област": "Zajecar",
    "Јабланичка област": "Jablanica",
    "Нишавска област": "Nisava",
    "Пиротска област": "Pirot",
    "Подунавска област": "Podunavlje",
    "Пчињска област": "Pcinja",
    "Топличка област": "Toplica",
    # Taiwan townships (Hanyu Pinyin). Owner on this board is JAP.
    "通霄鎮": "Tongxiao",
    "通霄鎮 area": "Tongxiao",
    "泰安鄉": "Tai'an",
    "泰安鄉 area": "Tai'an",
    "金湖鎮": "Jinhu",
    "金湖鎮 area": "Jinhu",
    "芳苑鄉": "Fangyuan",
    "芳苑鄉 area": "Fangyuan",
}

# 1936 English names for a modern ADM1, after clean_admin_name + ASCII fold.
# Only unambiguous well-known regions. Manchukuo is resolved by box below.
HISTORIC_ADM1: Dict[Tuple[str, str], str] = {
    ("IND", "Uttar Pradesh"): "United Provinces",
    ("IND", "Uttarakhand"): "United Provinces",
    ("IND", "Madhya Pradesh"): "Central Provinces",
    ("IND", "Chhattisgarh"): "Central Provinces",
    ("IND", "Rajasthan"): "Rajputana",
    ("IND", "Ladakh"): "Kashmir",
    ("IND", "Arunachal Pradesh"): "North-East Frontier",
    ("IND", "Odisha"): "Orissa",
    ("IND", "Orissa"): "Orissa",
    ("IND", "West Bengal"): "Bengal",
    ("IND", "Tamil Nadu"): "Madras",
    ("IND", "Andhra Pradesh"): "Madras",
    ("IND", "Telangana"): "Hyderabad",
    ("IND", "Karnataka"): "Mysore",
    ("IND", "Kerala"): "Travancore",
    ("IND", "Maharashtra"): "Bombay",
    ("IND", "Gujarat"): "Bombay",
    ("IND", "Haryana"): "Punjab",
    ("IND", "Himachal Pradesh"): "Punjab",
    ("IND", "Jharkhand"): "Bihar",
    ("PAK", "Sindh"): "Sind",
    ("PAK", "Sind"): "Sind",
    ("PAK", "Khyber Pakhtunkhwa"): "North-West Frontier",
    ("PAK", "Balochistan"): "Baluchistan",
    ("PAK", "Islamabad"): "Punjab",
    ("PAK", "Gilgit-Baltistan"): "Gilgit",
    ("PAK", "Azad Kashmir"): "Kashmir",
    ("PAK", "Azad Jammu and Kashmir"): "Kashmir",
}

_BARE_DIRECTION = {
    "north",
    "south",
    "east",
    "west",
    "central",
    "centre",
    "eastern",
    "western",
    "northern",
    "southern",
    "northeast",
    "northwest",
    "southeast",
    "southwest",
}

_ADMIN_SUFFIXES = (
    " Zhuang Autonomous Region",
    " Uygur Autonomous Region",
    " Uyghur Autonomous Region",
    " Hui Autonomous Region",
    " Autonomous Region",
    " Special Administrative Region",
    " Autonomous Okrug",
    " Autonomous Republic",
    " Autonomous Province",
    " Province",
    " Municipality",
    " Oblast",
    " Krai",
    " Governorate",
    " Prefecture",
    " Voivodeship",
    " Department",
)

# BGN/PCGN-style Cyrillic. Bulgarian х→h, щ→sht, ъ→a. Serbian ј/љ/њ included.
_CYR = {
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e",
    "ж": "zh", "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m",
    "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u",
    "ф": "f", "х": "h", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sht",
    "ъ": "a", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
    "ј": "j", "љ": "lj", "њ": "nj", "ћ": "c", "ђ": "dj", "џ": "dz",
    "є": "ye", "і": "i", "ї": "yi", "ґ": "g",
}
_GR = {
    "α": "a", "β": "v", "γ": "g", "δ": "d", "ε": "e", "ζ": "z", "η": "i",
    "θ": "th", "ι": "i", "κ": "k", "λ": "l", "μ": "m", "ν": "n", "ξ": "x",
    "ο": "o", "π": "p", "ρ": "r", "σ": "s", "ς": "s", "τ": "t", "υ": "y",
    "φ": "f", "χ": "ch", "ψ": "ps", "ω": "o",
}


def is_sea(pid: int) -> bool:
    return int(pid) >= SEA_ID


def is_nonlatin(name: str) -> bool:
    return NONLATIN_RE.search(str(name or "")) is not None


def name_categories(name: str) -> List[str]:
    """Categories that apply, stable order: oddity, tag-dir, area, nonlatin."""
    n = str(name or "")
    out: List[str] = []
    if ODDITY_RE.match(n):
        out.append("oddity")
    if TAG_DIR_RE.match(n):
        out.append("tag-dir")
    if AREA_RE.search(n):
        out.append("area")
    if is_nonlatin(n):
        out.append("nonlatin")
    return out


def primary_category(name: str) -> Optional[str]:
    cats = name_categories(name)
    return cats[0] if cats else None


def _ascii_fold(text: str) -> str:
    nfd = unicodedata.normalize("NFD", text)
    out = "".join(ch for ch in nfd if unicodedata.category(ch) != "Mn")
    return (
        out.replace("ø", "o")
        .replace("Ø", "O")
        .replace("ł", "l")
        .replace("Ł", "L")
        .replace("đ", "d")
        .replace("Đ", "D")
        .replace("æ", "ae")
        .replace("Æ", "Ae")
        .replace("œ", "oe")
        .replace("ß", "ss")
        .replace("–", "-")
        .replace("—", "-")
    )


def clean_admin_name(shape_name: str) -> str:
    """geoBoundaries shapeName → short English label."""
    n = _ascii_fold(str(shape_name or "").strip())
    n = re.sub(r"\s+", " ", n)
    if n.lower().startswith("republic of "):
        n = n[12:]
    for suf in _ADMIN_SUFFIXES:
        if n.endswith(suf):
            n = n[: -len(suf)]
            break
    if n.endswith(" Republic"):
        n = n[: -len(" Republic")]
    if n.endswith(" Region"):
        stem = n[: -len(" Region")].strip()
        if stem.lower() not in _BARE_DIRECTION:
            n = stem
    n = n.replace("–", "-").strip(" -")
    n = re.sub(r"\s+", " ", n).strip()
    return n


def historic_1936_name(iso: str, adm1: str, lat: Optional[float], lon: Optional[float]) -> Optional[str]:
    """Well-known 1936 name when the modern ADM1 sits in one. Else None."""
    iso_u = str(iso or "").upper()
    if iso_u == "BGD" and adm1:
        return "Bengal"
    if iso_u == "PHL" and adm1 in ("National Capital Region", "Metro Manila"):
        return "Manila"
    mapped = HISTORIC_ADM1.get((iso_u, adm1))
    if mapped:
        return mapped
    # Manchukuo (1932–1945). Boxes follow the 1934 province seats.
    if lat is None or lon is None:
        return None
    a = adm1.lower()
    in_manchuria = (
        "liaoning" in a
        or "jilin" in a
        or "heilongjiang" in a
        or (116.0 <= lon <= 135.0 and 40.0 <= lat <= 53.5 and ("hebei" in a or "inner mongolia" in a or "reing" in a))
    )
    if not in_manchuria:
        return None
    if "liaoning" in a:
        if lon < 122.2:
            return "Jinzhou"
        if lat < 41.2 and lon > 123.3:
            return "Andong"
        return "Fengtian"
    if "jilin" in a:
        if lon > 128.5:
            return "Jiandao"
        if lat > 44.5:
            return "Binjiang"
        return "Jilin"
    if "heilongjiang" in a:
        if lat > 49.0:
            return "Heihe"
        if lon > 129.0:
            return "Sanjiang"
        return "Longjiang"
    if 116.0 <= lon <= 122.0 and 40.2 <= lat <= 43.2:
        return "Rehe"
    if lon >= 119.0 and lat >= 46.0:
        return "Xing'an"
    return None


def _title_token(tok: str) -> str:
    if not tok:
        return tok
    if tok.isupper() and len(tok) <= 3:
        return tok
    return tok[0].upper() + tok[1:]


def bgn_cyrillic(text: str) -> str:
    """BGN/PCGN Cyrillic → Latin. Word-initial capitals follow the source."""
    out: List[str] = []
    cap = True
    for ch in str(text or ""):
        low = ch.lower()
        if low in _CYR:
            lat = _CYR[low]
            if ch.isupper() or cap:
                lat = _title_token(lat) if lat else lat
                cap = False
            out.append(lat)
        else:
            out.append(ch)
            cap = ch.isspace() or ch in "(-/"
    return "".join(out)


def bgn_greek(text: str) -> str:
    out: List[str] = []
    cap = True
    for ch in str(text or ""):
        low = ch.lower()
        if low in _GR:
            lat = _GR[low]
            if ch.isupper() or cap:
                lat = _title_token(lat)
                cap = False
            out.append(lat)
        else:
            out.append(ch)
            cap = ch.isspace() or ch in "(-/,"
    return "".join(out)


def romanize_text(text: str) -> str:
    """Latin rendering. Exonym table wins. CJK without an exonym returns ''."""
    raw = str(text or "").strip()
    if raw in EXONYMS:
        return EXONYMS[raw]
    if re.search(r"[\u3400-\u9fff]", raw):
        return ""
    if re.search(r"[\u0400-\u04ff]", raw):
        return bgn_cyrillic(raw)
    if re.search(r"[\u0370-\u03ff\u1f00-\u1fff]", raw):
        return bgn_greek(raw)
    return raw


def _admin_label(hit: Mapping[str, object], *, prefer_adm2: bool) -> Tuple[str, str, bool]:
    """Return (label, source, historic)."""
    adm2 = clean_admin_name(str(hit.get("adm2") or ""))
    adm1 = clean_admin_name(str(hit.get("adm1") or ""))
    iso = str(hit.get("iso") or "")
    lat = hit.get("lat")
    lon = hit.get("lon")
    lat_f = float(lat) if isinstance(lat, (int, float)) else None
    lon_f = float(lon) if isinstance(lon, (int, float)) else None
    # Numeric geoBoundaries zones (Qatar ADM2 "78") are not place names.
    adm2_ok = bool(adm2) and adm2.lower() not in _BARE_DIRECTION and not adm2.isdigit() and len(adm2) > 2
    if prefer_adm2 and adm2_ok and not ODDITY_RE.match(adm2) and not TAG_DIR_RE.match(adm2):
        # Quezon City was chartered in 1939. In 1936 the site was Rizal province.
        if adm2 == "Quezon City":
            return "Rizal", "historic-1936", True
        return adm2, "geoboundaries-ADM2", False
    base = adm1 or adm2
    if not base:
        return "", "", False
    hist = historic_1936_name(iso, base, lat_f, lon_f)
    if hist:
        return hist, "historic-1936", True
    src = "geoboundaries-ADM1" if adm1 else "geoboundaries-ADM2"
    return base, src, False


def _guard_reserved(pid: int, name: str) -> str:
    owner_pid = RESERVED_FIRST_NAME.get(name)
    if owner_pid is not None and int(owner_pid) != int(pid):
        return f"{name} District"
    return name


def _sanitize(name: str) -> str:
    n = re.sub(r"\s+", " ", str(name or "").strip())
    n = n.replace('"', "'")
    if AREA_RE.search(n):
        n = AREA_RE.sub("", n).strip()
    if TAG_DIR_RE.match(n) or ODDITY_RE.match(n) or is_nonlatin(n):
        return ""
    return n


def proposed_name(pid: int, row: Mapping[str, object], centroid: Optional[Sequence[float]]) -> str:
    """Proposed display name. ``centroid`` is (lon, lat) or None.

    Pinned ids and sea zones return the stored name. Tag-direction and
    numeric ``"NN area"`` placeholders use the admin hit. Other ``" area"``
    names drop the suffix. Non-Latin names use the English exonym, else
    BGN/PCGN (Cyrillic / Greek). CJK without an exonym is left unchanged
    (``unidecode`` is not used).
    """
    pid_i = int(pid)
    old = str((row or {}).get("name") or "")
    if is_sea(pid_i) or pid_i in PINNED_NAME_IDS:
        return old
    cats = name_categories(old)
    if not cats:
        return old
    hit = ADMIN_HITS.get(pid_i) or {}
    rule_name = old

    if "oddity" in cats and old == "ATA region":
        # Northern Antarctic Peninsula, British name in 1936.
        rule_name = "Graham Land"
    elif "oddity" in cats and pid_i in NCR_1936:
        rule_name = NCR_1936[pid_i]
    elif "oddity" in cats:
        label, _src, _hist = _admin_label(hit, prefer_adm2=True)
        rule_name = label or old
    elif "tag-dir" in cats:
        label, _src, _hist = _admin_label(hit, prefer_adm2=False)
        rule_name = label or old
    else:
        stem = AREA_RE.sub("", old).strip() if "area" in cats else old
        if "area" in cats and stem.isdigit():
            label, _src, _hist = _admin_label(hit, prefer_adm2=True)
            rule_name = label or stem
        elif is_nonlatin(stem) or is_nonlatin(old):
            rendered = romanize_text(old if old in EXONYMS else stem)
            rule_name = rendered or old
        else:
            rule_name = stem

    rule_name = _guard_reserved(pid_i, rule_name)
    cleaned = _sanitize(rule_name)
    return cleaned or old


def proposal_detail(
    pid: int, row: Mapping[str, object], centroid: Optional[Sequence[float]]
) -> Dict[str, str]:
    """Same decision as ``proposed_name`` plus rule and source for evidence."""
    pid_i = int(pid)
    old = str((row or {}).get("name") or "")
    new = proposed_name(pid_i, row, centroid)
    if new == old:
        if pid_i in PINNED_NAME_IDS:
            return {"old": old, "new": new, "rule": "pinned", "source": PINNED_NAME_IDS[pid_i]}
        if is_nonlatin(old) or TAG_DIR_RE.match(old) or ODDITY_RE.match(old):
            return {"old": old, "new": new, "rule": "unknown", "source": "no-confident-name"}
        return {"old": old, "new": new, "rule": "unchanged", "source": ""}
    cats = name_categories(old)
    hit = ADMIN_HITS.get(pid_i) or {}
    if old == "ATA region":
        return {"old": old, "new": new, "rule": "oddity", "source": "historic-1936 Graham Land"}
    if pid_i in NCR_1936:
        return {
            "old": old,
            "new": new,
            "rule": "historic-1936",
            "source": "1936 Rizal municipality",
        }
    if "oddity" in cats:
        _label, src, _h = _admin_label(hit, prefer_adm2=True)
        return {"old": old, "new": new, "rule": "oddity", "source": src or "geoboundaries-ADM2"}
    if "tag-dir" in cats:
        _label, src, hist = _admin_label(hit, prefer_adm2=False)
        rule = "historic-1936" if hist else "tag-dir"
        return {"old": old, "new": new, "rule": rule, "source": src}
    stem = AREA_RE.sub("", old).strip()
    if "area" in cats and stem.isdigit():
        _label, src, hist = _admin_label(hit, prefer_adm2=True)
        return {
            "old": old,
            "new": new,
            "rule": "historic-1936" if hist else "area-admin",
            "source": src or "geoboundaries-ADM2",
        }
    if is_nonlatin(old) or is_nonlatin(stem):
        src = "exonym" if (old in EXONYMS or stem in EXONYMS) else "bgn-pcgn"
        if re.search(r"[\u3400-\u9fff]", old):
            src = "hanyu-pinyin"
        rule = "area+nonlatin" if "area" in cats else "nonlatin"
        return {"old": old, "new": new, "rule": rule, "source": src}
    if "area" in cats:
        return {"old": old, "new": new, "rule": "area", "source": "strip-suffix"}
    return {"old": old, "new": new, "rule": "rename", "source": ""}


def _compass(lat: float, lon: float, clat: float, clon: float) -> str:
    dlat = lat - clat
    dlon = lon - clon
    if abs(dlat) < 1e-6 and abs(dlon) < 1e-6:
        return "East"
    if abs(dlat) >= abs(dlon) * 1.4:
        return "North" if dlat > 0 else "South"
    if abs(dlon) >= abs(dlat) * 1.4:
        return "East" if dlon > 0 else "West"
    ns = "North" if dlat >= 0 else "South"
    ew = "east" if dlon >= 0 else "west"
    return ns + ew


def disambiguate(
    rows: Sequence[MutableMapping[str, object]],
) -> List[Dict[str, object]]:
    """Suffix duplicate names within one owner. Never uses ``#id``.

    Each row needs pid, owner, name, lat, lon. A row with ``pinned`` true
    keeps its name. A group whose members are all pinned is left as-is
    (the CHN cardinal blobs). Other members of a colliding group receive
    a short compass suffix (``Hebei North``). The lowest unpinned id, or
    the pinned member, keeps the bare name when one keeper is enough.
    """
    changes: List[Dict[str, object]] = []
    by_key: Dict[Tuple[str, str], List[MutableMapping[str, object]]] = {}
    used_by_owner: Dict[str, set] = {}
    for row in rows:
        if is_sea(int(row["pid"])):
            continue
        owner = str(row.get("owner") or "")
        used_by_owner.setdefault(owner, set()).add(str(row.get("name") or ""))
        key = (owner, str(row.get("name") or ""))
        by_key.setdefault(key, []).append(row)

    for (_owner, name), group in by_key.items():
        if len(group) < 2 or not name:
            continue
        if all(bool(r.get("pinned")) for r in group):
            continue
        keepers = [r for r in group if r.get("pinned")]
        if keepers:
            keeper = min(keepers, key=lambda r: int(r["pid"]))
        else:
            keeper = min(group, key=lambda r: int(r["pid"]))
        klat = float(keeper.get("lat") or 0.0)
        klon = float(keeper.get("lon") or 0.0)
        # Owner-wide, so a suffix cannot collide with another province of the
        # same owner (including names assigned earlier in this pass).
        used = used_by_owner.setdefault(_owner, set())
        used.add(name)
        movers = [r for r in group if int(r["pid"]) != int(keeper["pid"]) and not r.get("pinned")]
        movers.sort(key=lambda r: (float(r.get("lat") or 0.0), float(r.get("lon") or 0.0), int(r["pid"])))
        # Rank far duplicates that share a compass.
        compasses: Dict[str, List[MutableMapping[str, object]]] = {}
        for r in movers:
            comp = _compass(float(r.get("lat") or 0.0), float(r.get("lon") or 0.0), klat, klon)
            compasses.setdefault(comp, []).append(r)
        for comp, members in compasses.items():
            members.sort(
                key=lambda r: (
                    -((float(r.get("lat") or 0.0) - klat) ** 2 + (float(r.get("lon") or 0.0) - klon) ** 2),
                    int(r["pid"]),
                )
            )
            for i, r in enumerate(members):
                suffix = comp if i == 0 else f"Far {comp}" if i == 1 else f"{comp} {i + 1}"
                candidate = _guard_reserved(int(r["pid"]), _sanitize(f"{name} {suffix}"))
                guard = 0
                while (
                    (not candidate)
                    or candidate in used
                    or TAG_DIR_RE.match(candidate)
                    or ODDITY_RE.match(candidate)
                    or AREA_RE.search(candidate)
                    or is_nonlatin(candidate)
                ):
                    guard += 1
                    candidate = _guard_reserved(
                        int(r["pid"]), _sanitize(f"{name} {suffix} {guard}")
                    )
                    if guard > 6:
                        adm2 = clean_admin_name(
                            str((ADMIN_HITS.get(int(r["pid"])) or {}).get("adm2") or "")
                        )
                        candidate = (
                            _guard_reserved(int(r["pid"]), _sanitize(f"{name} {adm2}".strip()))
                            if adm2
                            else f"{name} {comp}"
                        )
                        break
                extra = 7
                while (
                    (not candidate)
                    or candidate in used
                    or TAG_DIR_RE.match(candidate)
                    or ODDITY_RE.match(candidate)
                    or AREA_RE.search(candidate)
                    or is_nonlatin(candidate)
                ):
                    extra += 1
                    candidate = _guard_reserved(
                        int(r["pid"]), _sanitize(f"{name} {comp} {extra}")
                    )
                    if extra > 40:
                        candidate = _sanitize(f"{name} {comp} {extra}") or f"{name} {comp} {extra}"
                        break
                used.add(candidate)
                old = str(r.get("name") or "")
                if candidate != old:
                    r["name"] = candidate
                    changes.append({"pid": int(r["pid"]), "old": old, "new": candidate, "rule": "disambiguate"})
    return changes


def count_categories(names: Iterable[str]) -> Dict[str, int]:
    """Count land-name hits. A name can increment more than one bucket."""
    counts = {"tag-dir": 0, "area": 0, "nonlatin": 0, "oddity": 0}
    for name in names:
        for cat in name_categories(str(name)):
            counts[cat] += 1
    return counts
