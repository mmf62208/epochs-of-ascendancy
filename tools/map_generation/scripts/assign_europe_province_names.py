#!/usr/bin/env python3
"""Assign unique, Europe-theater place names to provinces by map centroid.

Highest-impact map labeling fix for Epochs of Ascendancy:
- Replaces placeholder names ("Province NNNN", "New Settlement")
- Replaces non-European global seed names (Tokyo, Silicon Valley, …)
  that landed on the Europe theater via the Phase-1 subdivision pipeline
- Keeps correctly-named European anchors (Berlin, Paris, London, …)
- Uses a lon/lat→canvas fit from known anchors + nearest-gazetteer matching

Usage:
  python3 tools/map_generation/scripts/assign_europe_province_names.py \\
      --dir data/provinces_full_europe [--dry-run] [--write]
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[3]

# Canvas = a*lon + b*lat + c  (least-squares from known Europe anchors)
_X_COEF = (11.3987280, -0.812649346, 2081.84412)
_Y_COEF = (-0.0681278226, -10.9240726, 1004.31052)

PLACEHOLDER_RE = re.compile(r"^(Province\s+\d+|New Settlement)$", re.I)

# Names that must never appear on the Europe theater (global seed leftovers).
NON_EUROPE_EXACT = {
    "tokyo",
    "beijing",
    "washington dc",
    "houston energy corridor",
    "silicon valley",
    "seoul",
    "johannesburg",
    "sao paulo",
    "hong kong",
    "singapore",
    "ottawa",
    "vancouver",
    "guangzhou",
    "caracas",
    "anchorage",
    "auckland",
    "cape town",
    "lagos",
    "durban",
    "abuja",
    "adelaide",
    "bangalore",
    "bangkok",
    "buenos aires",
    "cali",
    "cebu",
    "chicago",
    "christchurch",
    "colon",
    "darwin",
    "detroit",
    "hanoi",
    "havana",
    "ho chi minh city",
    "honolulu",
    "jakarta",
    "kuala lumpur",
    "lima",
    "manila",
    "santiago de cuba",
    "penang",
    "sydney",
    "rio de janeiro",
    "new delhi",
    "shanghai",
    "riyadh oil heartland",
    "tehran",
    "is fahan",
    "isfahan",
    "baghdad",
    "cairo",  # edge; keep Egypt theater optional — still rename if on Europe canvas
    "jerusalem",  # off-theater seed
    "damascus",
    "baku oil fields",
    "ural industrial region",
}

# Well-known European names already correct — never overwrite.
LOCKED_EUROPE_NAMES = {
    "berlin",
    "paris",
    "london",
    "rome",
    "madrid",
    "warsaw",
    "istanbul",
    "moscow",
    "st. petersburg",
    "copenhagen",
    "helsinki",
    "ruhr industrial area",
    "kiev",
    "kharkiv",
    "ankara",
}


def lonlat_to_canvas(lon: float, lat: float) -> Tuple[float, float]:
    x = _X_COEF[0] * lon + _X_COEF[1] * lat + _X_COEF[2]
    y = _Y_COEF[0] * lon + _Y_COEF[1] * lat + _Y_COEF[2]
    return x, y


def polygon_centroid(points: Sequence[Sequence[float]]) -> Tuple[float, float]:
    if not points:
        return 0.0, 0.0
    sx = sum(float(p[0]) for p in points)
    sy = sum(float(p[1]) for p in points)
    n = float(len(points))
    return sx / n, sy / n


def _needs_rename(name: str) -> bool:
    n = (name or "").strip()
    if not n:
        return True
    if PLACEHOLDER_RE.match(n):
        return True
    if n.lower() in NON_EUROPE_EXACT:
        return True
    if n.lower() in LOCKED_EUROPE_NAMES:
        return False
    # Duplicate-heavy garbage from phase1_test
    if n.lower() == "new settlement":
        return True
    return False


def _is_locked(name: str) -> bool:
    return (name or "").strip().lower() in LOCKED_EUROPE_NAMES


def europe_gazetteer() -> List[Tuple[str, float, float]]:
    """Return (display_name, lon, lat) for European theater places.

    Dense enough for ~500 provinces with unique nearest-name assignment.
    Coordinates are approximate real-world degrees.
    """
    places: List[Tuple[str, float, float]] = [
        # British Isles
        ("London", -0.13, 51.51),
        ("Westminster", -0.14, 51.50),
        ("Greenwich", 0.00, 51.48),
        ("Birmingham", -1.90, 52.48),
        ("Manchester", -2.24, 53.48),
        ("Liverpool", -2.99, 53.41),
        ("Leeds", -1.55, 53.80),
        ("Sheffield", -1.47, 53.38),
        ("Bristol", -2.59, 51.45),
        ("Newcastle", -1.62, 54.98),
        ("Glasgow", -4.25, 55.86),
        ("Edinburgh", -3.19, 55.95),
        ("Aberdeen", -2.09, 57.15),
        ("Inverness", -4.22, 57.48),
        ("Cardiff", -3.18, 51.48),
        ("Swansea", -3.94, 51.62),
        ("Belfast", -5.93, 54.60),
        ("Dublin", -6.26, 53.35),
        ("Cork", -8.48, 51.90),
        ("Galway", -9.05, 53.27),
        ("Limerick", -8.63, 52.66),
        ("Plymouth", -4.14, 50.37),
        ("Southampton", -1.40, 50.91),
        ("Dover", 1.31, 51.13),
        ("Norwich", 1.30, 52.63),
        ("York", -1.08, 53.96),
        ("Oxford", -1.26, 51.75),
        ("Cambridge", 0.12, 52.21),
        ("Portsmouth", -1.09, 50.80),
        ("Brighton", -0.14, 50.82),
        ("Hull", -0.34, 53.74),
        ("Coventry", -1.51, 52.41),
        ("Nottingham", -1.15, 52.95),
        ("Leicester", -1.13, 52.64),
        ("Sunderland", -1.38, 54.91),
        ("Dundee", -2.97, 56.46),
        ("Waterford", -7.11, 52.26),
        ("Derry", -7.31, 54.99),
        # France / Benelux
        ("Paris", 2.35, 48.86),
        ("Versailles", 2.13, 48.80),
        ("Lyon", 4.84, 45.76),
        ("Marseille", 5.37, 43.30),
        ("Toulouse", 1.44, 43.60),
        ("Bordeaux", -0.58, 44.84),
        ("Nantes", -1.55, 47.22),
        ("Lille", 3.06, 50.63),
        ("Strasbourg", 7.75, 48.58),
        ("Nice", 7.27, 43.71),
        ("Rennes", -1.68, 48.11),
        ("Reims", 4.03, 49.26),
        ("Grenoble", 5.72, 45.19),
        ("Dijon", 5.04, 47.32),
        ("Brest", -4.49, 48.39),
        ("Calais", 1.86, 50.95),
        ("Cherbourg", -1.62, 49.63),
        ("Orleans", 1.90, 47.90),
        ("Tours", 0.68, 47.39),
        ("Nancy", 6.18, 48.69),
        ("Metz", 6.18, 49.12),
        ("Clermont-Ferrand", 3.09, 45.78),
        ("Montpellier", 3.88, 43.61),
        ("Toulon", 5.93, 43.12),
        ("Rouen", 1.10, 49.44),
        ("Le Havre", 0.11, 49.49),
        ("Brussels", 4.35, 50.85),
        ("Antwerp", 4.40, 51.22),
        ("Ghent", 3.72, 51.05),
        ("Bruges", 3.22, 51.21),
        ("Liege", 5.57, 50.63),
        ("Charleroi", 4.44, 50.41),
        ("Amsterdam", 4.90, 52.37),
        ("Rotterdam", 4.48, 51.92),
        ("The Hague", 4.30, 52.07),
        ("Utrecht", 5.12, 52.09),
        ("Eindhoven", 5.47, 51.44),
        ("Groningen", 6.57, 53.22),
        ("Maastricht", 5.69, 50.85),
        ("Luxembourg City", 6.13, 49.61),
        ("Arnhem", 5.91, 51.98),
        # Germany / Alps
        ("Berlin", 13.40, 52.52),
        ("Hamburg", 9.99, 53.55),
        ("Munich", 11.58, 48.14),
        ("Cologne", 6.96, 50.94),
        ("Frankfurt", 8.68, 50.11),
        ("Stuttgart", 9.18, 48.78),
        ("Düsseldorf", 6.77, 51.23),
        ("Dortmund", 7.47, 51.51),
        ("Essen", 7.01, 51.46),
        ("Leipzig", 12.37, 51.34),
        ("Dresden", 13.74, 51.05),
        ("Hanover", 9.73, 52.38),
        ("Nuremberg", 11.08, 49.45),
        ("Bremen", 8.80, 53.08),
        ("Bonn", 7.10, 50.74),
        ("Kiel", 10.14, 54.32),
        ("Rostock", 12.14, 54.09),
        ("Magdeburg", 11.63, 52.13),
        ("Erfurt", 11.03, 50.98),
        ("Freiburg", 7.85, 47.99),
        ("Augsburg", 10.90, 48.37),
        ("Mannheim", 8.47, 49.49),
        ("Karlsruhe", 8.40, 49.01),
        ("Saarbrücken", 6.99, 49.24),
        ("Ruhr Industrial Area", 7.20, 51.48),
        ("Vienna", 16.37, 48.21),
        ("Graz", 15.44, 47.07),
        ("Linz", 14.29, 48.31),
        ("Innsbruck", 11.40, 47.27),
        ("Salzburg", 13.05, 47.81),
        ("Zurich", 8.54, 47.38),
        ("Geneva", 6.14, 46.20),
        ("Basel", 7.59, 47.56),
        ("Bern", 7.45, 46.95),
        ("Lausanne", 6.63, 46.52),
        ("Prague", 14.44, 50.08),
        ("Brno", 16.61, 49.20),
        ("Ostrava", 18.26, 49.82),
        ("Pilsen", 13.38, 49.75),
        ("Bratislava", 17.11, 48.15),
        ("Kosice", 21.26, 48.72),
        ("Budapest", 19.04, 47.50),
        ("Debrecen", 21.63, 47.53),
        ("Szeged", 20.15, 46.25),
        ("Pecs", 18.23, 46.07),
        # Iberia
        ("Madrid", -3.70, 40.42),
        ("Barcelona", 2.17, 41.39),
        ("Valencia", -0.38, 39.47),
        ("Seville", -5.98, 37.39),
        ("Zaragoza", -0.88, 41.65),
        ("Malaga", -4.42, 36.72),
        ("Bilbao", -2.93, 43.26),
        ("Vigo", -8.72, 42.24),
        ("A Coruña", -8.40, 43.36),
        ("Granada", -3.60, 37.18),
        ("Murcia", -1.13, 37.99),
        ("Alicante", -0.49, 38.35),
        ("Valladolid", -4.72, 41.65),
        ("Oviedo", -5.84, 43.36),
        ("Santander", -3.81, 43.46),
        ("Pamplona", -1.64, 42.81),
        ("Cordoba", -4.78, 37.89),
        ("Cadiz", -6.29, 36.53),
        ("Lisbon", -9.14, 38.72),
        ("Porto", -8.61, 41.15),
        ("Coimbra", -8.43, 40.20),
        ("Braga", -8.43, 41.55),
        ("Faro", -7.93, 37.02),
        ("Evora", -7.91, 38.57),
        # Italy
        ("Rome", 12.50, 41.90),
        ("Milan", 9.19, 45.46),
        ("Naples", 14.27, 40.85),
        ("Turin", 7.69, 45.07),
        ("Florence", 11.26, 43.77),
        ("Bologna", 11.34, 44.49),
        ("Genoa", 8.95, 44.41),
        ("Venice", 12.34, 45.44),
        ("Palermo", 13.36, 38.12),
        ("Catania", 15.09, 37.51),
        ("Bari", 16.87, 41.12),
        ("Verona", 10.99, 45.44),
        ("Padua", 11.88, 45.41),
        ("Trieste", 13.77, 45.65),
        ("Messina", 15.55, 38.19),
        ("Cagliari", 9.12, 39.22),
        ("Perugia", 12.39, 43.11),
        ("Pisa", 10.40, 43.72),
        ("Siena", 11.33, 43.32),
        ("Ancona", 13.52, 43.62),
        ("Taranto", 17.24, 40.46),
        ("Reggio Calabria", 15.65, 38.11),
        # Scandinavia / Baltics
        ("Copenhagen", 12.57, 55.68),
        ("Aarhus", 10.21, 56.16),
        ("Odense", 10.39, 55.40),
        ("Aalborg", 9.92, 57.05),
        ("Stockholm", 18.07, 59.33),
        ("Gothenburg", 11.97, 57.71),
        ("Malmö", 13.00, 55.61),
        ("Uppsala", 17.64, 59.86),
        ("Oslo", 10.75, 59.91),
        ("Bergen", 5.32, 60.39),
        ("Trondheim", 10.40, 63.43),
        ("Stavanger", 5.73, 58.97),
        ("Helsinki", 24.94, 60.17),
        ("Tampere", 23.76, 61.50),
        ("Turku", 22.27, 60.45),
        ("Oulu", 25.47, 65.01),
        ("Tallinn", 24.75, 59.44),
        ("Tartu", 26.73, 58.38),
        ("Riga", 24.11, 56.95),
        ("Daugavpils", 26.53, 55.87),
        ("Vilnius", 25.28, 54.69),
        ("Kaunas", 23.90, 54.90),
        ("Klaipeda", 21.14, 55.71),
        ("Reykjavik", -21.83, 64.15),
        # Poland / Central East
        ("Warsaw", 21.01, 52.23),
        ("Krakow", 19.94, 50.06),
        ("Lodz", 19.46, 51.76),
        ("Wroclaw", 17.04, 51.11),
        ("Poznan", 16.93, 52.41),
        ("Gdansk", 18.65, 54.35),
        ("Szczecin", 14.55, 53.43),
        ("Lublin", 22.57, 51.25),
        ("Bialystok", 23.17, 53.13),
        ("Katowice", 19.02, 50.26),
        ("Bydgoszcz", 18.01, 53.12),
        ("Gdynia", 18.53, 54.52),
        # Balkans / SE Europe
        ("Belgrade", 20.46, 44.82),
        ("Zagreb", 15.98, 45.81),
        ("Sarajevo", 18.41, 43.86),
        ("Split", 16.44, 43.51),
        ("Dubrovnik", 18.09, 42.65),
        ("Ljubljana", 14.51, 46.05),
        ("Maribor", 15.65, 46.55),
        ("Skopje", 21.43, 42.00),
        ("Podgorica", 19.26, 42.43),
        ("Tirana", 19.82, 41.33),
        ("Pristina", 21.17, 42.66),
        ("Sofia", 23.32, 42.70),
        ("Plovdiv", 24.75, 42.14),
        ("Varna", 27.91, 43.21),
        ("Bucharest", 26.10, 44.43),
        ("Cluj-Napoca", 23.59, 46.77),
        ("Timisoara", 21.23, 45.75),
        ("Iasi", 27.59, 47.16),
        ("Constanta", 28.63, 44.16),
        ("Brasov", 25.59, 45.66),
        ("Athens", 23.73, 37.98),
        ("Thessaloniki", 22.94, 40.64),
        ("Patras", 21.73, 38.25),
        ("Heraklion", 25.14, 35.34),
        ("Ioannina", 20.85, 39.67),
        ("Larissa", 22.42, 39.64),
        ("Rhodes", 28.22, 36.43),
        # Turkey / Caucasus edge / Black Sea
        ("Istanbul", 28.98, 41.01),
        ("Ankara", 32.86, 39.93),
        ("Izmir", 27.14, 38.42),
        ("Bursa", 29.06, 40.19),
        ("Antalya", 30.71, 36.90),
        ("Trabzon", 39.72, 41.00),
        ("Edirne", 26.56, 41.68),
        ("Samsun", 36.33, 41.29),
        ("Adana", 35.32, 37.00),
        ("Konya", 32.48, 37.87),
        # Russia / Ukraine / Belarus (theater edge)
        ("Moscow", 37.62, 55.76),
        ("St. Petersburg", 30.34, 59.93),
        ("Novgorod", 31.27, 58.52),
        ("Pskov", 28.33, 57.81),
        ("Smolensk", 32.04, 54.78),
        ("Kaliningrad", 20.51, 54.71),
        ("Murmansk", 33.09, 68.96),
        ("Arkhangelsk", 40.54, 64.54),
        ("Tver", 35.90, 56.86),
        ("Yaroslavl", 39.87, 57.63),
        ("Nizhny Novgorod", 44.00, 56.33),
        ("Voronezh", 39.20, 51.67),
        ("Rostov-on-Don", 39.70, 47.24),
        ("Krasnodar", 38.98, 45.04),
        ("Sevastopol", 33.53, 44.62),
        ("Simferopol", 34.10, 44.95),
        ("Kiev", 30.52, 50.45),
        ("Kharkiv", 36.23, 49.99),
        ("Odessa", 30.72, 46.48),
        ("Lviv", 24.03, 49.84),
        ("Dnipro", 35.05, 48.46),
        ("Donetsk", 37.80, 48.02),
        ("Mariupol", 37.55, 47.10),
        ("Chernihiv", 31.28, 51.50),
        ("Vinnytsia", 28.47, 49.23),
        ("Zaporizhzhia", 35.14, 47.84),
        ("Minsk", 27.56, 53.90),
        ("Brest", 23.69, 52.10),
        ("Gomel", 30.98, 52.43),
        ("Vitebsk", 30.20, 55.19),
        ("Grodno", 23.83, 53.67),
        ("Chisinau", 28.86, 47.01),
        ("Tbilisi", 44.79, 41.72),
        ("Yerevan", 44.51, 40.18),
        ("Baku", 49.87, 40.41),
        # North Africa theater edge (naval)
        ("Algiers", 3.06, 36.75),
        ("Oran", -0.64, 35.70),
        ("Tunis", 10.18, 36.81),
        ("Tripoli", 13.19, 32.89),
        ("Benghazi", 20.07, 32.12),
        ("Casablanca", -7.59, 33.57),
        ("Tangier", -5.80, 35.76),
        ("Rabat", -6.85, 34.02),
        ("Alexandria", 29.92, 31.20),
        # Extra density: secondary European towns
        ("Amiens", 2.30, 49.89),
        ("Caen", -0.37, 49.18),
        ("Poitiers", 0.34, 46.58),
        ("Limoges", 1.26, 45.83),
        ("Angers", -0.55, 47.47),
        ("Mulhouse", 7.34, 47.75),
        ("Besancon", 6.02, 47.24),
        ("Avignon", 4.81, 43.95),
        ("Perpignan", 2.90, 42.70),
        ("Bayonne", -1.47, 43.49),
        ("Lorient", -3.37, 47.75),
        ("Saint-Etienne", 4.39, 45.44),
        ("Le Mans", 0.20, 48.01),
        ("Troyes", 4.08, 48.30),
        ("Charleville", 4.72, 49.77),
        ("Boulogne", 1.61, 50.73),
        ("Dunkirk", 2.38, 51.03),
        ("Namur", 4.87, 50.47),
        ("Mons", 3.95, 50.45),
        ("Leuven", 4.70, 50.88),
        ("Middelburg", 3.61, 51.50),
        ("Nijmegen", 5.86, 51.84),
        ("Zwolle", 6.09, 52.51),
        ("Leeuwarden", 5.79, 53.20),
        ("Haarlem", 4.65, 52.39),
        ("Delft", 4.36, 52.01),
        ("Breda", 4.78, 51.57),
        ("Tilburg", 5.09, 51.56),
        ("Enschede", 6.90, 52.22),
        ("Lübeck", 10.69, 53.87),
        ("Flensburg", 9.45, 54.78),
        ("Schwerin", 11.42, 53.63),
        ("Potsdam", 13.06, 52.40),
        ("Cottbus", 14.33, 51.76),
        ("Chemnitz", 12.92, 50.83),
        ("Jena", 11.59, 50.93),
        ("Würzburg", 9.93, 49.79),
        ("Regensburg", 12.10, 49.01),
        ("Passau", 13.46, 48.57),
        ("Ulm", 9.99, 48.40),
        ("Konstanz", 9.18, 47.66),
        ("Kassel", 9.48, 51.31),
        ("Bielefeld", 8.53, 52.03),
        ("Münster", 7.63, 51.96),
        ("Osnabrück", 8.05, 52.28),
        ("Oldenburg", 8.21, 53.14),
        ("Braunschweig", 10.53, 52.27),
        ("Göttingen", 9.94, 51.53),
        ("Mainz", 8.27, 50.00),
        ("Wiesbaden", 8.24, 50.08),
        ("Trier", 6.64, 49.76),
        ("Koblenz", 7.59, 50.36),
        ("Heidelberg", 8.69, 49.41),
        ("Ingolstadt", 11.42, 48.77),
        ("Bayreuth", 11.58, 49.95),
        ("Bamberg", 10.89, 49.89),
        ("Gera", 12.08, 50.88),
        ("Halle", 11.97, 51.48),
        ("Zwickau", 12.50, 50.72),
        ("Plauen", 12.14, 50.50),
        ("Görlitz", 14.99, 51.15),
        ("Stralsund", 13.08, 54.31),
        ("Greifswald", 13.39, 54.10),
        ("Wismar", 11.47, 53.89),
        ("Neubrandenburg", 13.26, 53.56),
        ("Brandenburg an der Havel", 12.55, 52.41),
        ("Frankfurt an der Oder", 14.55, 52.35),
        ("Cuxhaven", 8.70, 53.87),
        ("Emden", 7.21, 53.37),
        ("Wilhelmshaven", 8.11, 53.52),
        ("Bremerhaven", 8.58, 53.54),
        ("Gelsenkirchen", 7.12, 51.51),
        ("Bochum", 7.22, 51.48),
        ("Wuppertal", 7.15, 51.26),
        ("Mönchengladbach", 6.44, 51.19),
        ("Aachen", 6.08, 50.78),
        ("Krefeld", 6.56, 51.33),
        ("Leverkusen", 6.98, 51.03),
        ("Solingen", 7.08, 51.17),
        ("Hagen", 7.47, 51.36),
        ("Hamm", 7.82, 51.68),
        ("Herne", 7.22, 51.54),
        ("Mülheim", 6.88, 51.43),
        ("Oberhausen", 6.85, 51.47),
        ("Recklinghausen", 7.20, 51.62),
        ("Remscheid", 7.19, 51.18),
        ("Bottrop", 6.93, 51.52),
        ("Siegen", 8.02, 50.87),
        ("Paderborn", 8.75, 51.72),
        ("Gütersloh", 8.38, 51.91),
        ("Hildesheim", 9.95, 52.15),
        ("Wolfsburg", 10.79, 52.42),
        ("Salzgitter", 10.33, 52.15),
        ("Celle", 10.08, 52.62),
        ("Lüneburg", 10.41, 53.25),
        ("Stade", 9.48, 53.60),
        ("Verden", 9.23, 52.92),
        ("Minden", 8.92, 52.29),
        ("Detmold", 8.88, 51.94),
        ("Bad Hersfeld", 9.71, 50.87),
        ("Fulda", 9.68, 50.55),
        ("Marburg", 8.77, 50.81),
        ("Giessen", 8.68, 50.58),
        ("Darmstadt", 8.65, 49.87),
        ("Offenbach", 8.76, 50.10),
        ("Hanau", 8.92, 50.13),
        ("Aschaffenburg", 9.15, 49.97),
        ("Schweinfurt", 10.23, 50.05),
        ("Coburg", 10.96, 50.26),
        ("Hof", 11.92, 50.32),
        ("Weiden", 12.16, 49.68),
        ("Amberg", 11.86, 49.44),
        ("Landshut", 12.15, 48.54),
        ("Rosenheim", 12.13, 47.86),
        ("Kempten", 10.31, 47.73),
        ("Memmingen", 10.18, 47.99),
        ("Ravensburg", 9.61, 47.78),
        ("Friedrichshafen", 9.48, 47.65),
        ("Singen", 8.84, 47.76),
        ("Villingen-Schwenningen", 8.49, 48.06),
        ("Offenburg", 7.94, 48.47),
        ("Lahr", 7.87, 48.34),
        ("Baden-Baden", 8.24, 48.76),
        ("Pforzheim", 8.70, 48.89),
        ("Heilbronn", 9.21, 49.14),
        ("Ludwigsburg", 9.19, 48.90),
        ("Reutlingen", 9.20, 48.49),
        ("Tübingen", 9.06, 48.52),
        ("Esslingen", 9.31, 48.74),
        ("Göppingen", 9.65, 48.70),
        ("Schwäbisch Gmünd", 9.80, 48.80),
        ("Aalen", 10.09, 48.84),
        ("Schwäbisch Hall", 9.74, 49.11),
        ("Crailsheim", 10.07, 49.13),
        ("Ansbach", 10.57, 49.30),
        ("Fürth", 10.99, 49.48),
        ("Erlangen", 11.00, 49.60),
        ("Bamberg District", 10.90, 49.90),
        ("Bayreuth District", 11.58, 49.95),
        ("Coburg District", 10.97, 50.26),
        # UK extras
        ("Reading", -0.97, 51.45),
        ("Swindon", -1.78, 51.56),
        ("Bath", -2.36, 51.38),
        ("Exeter", -3.53, 50.72),
        ("Truro", -5.05, 50.26),
        ("Bournemouth", -1.88, 50.72),
        ("Ipswich", 1.15, 52.06),
        ("Colchester", 0.90, 51.90),
        ("Chelmsford", 0.47, 51.74),
        ("Luton", -0.42, 51.88),
        ("Milton Keynes", -0.76, 52.04),
        ("Northampton", -0.90, 52.24),
        ("Peterborough", -0.24, 52.57),
        ("Lincoln", -0.54, 53.23),
        ("Derby", -1.47, 52.92),
        ("Stoke-on-Trent", -2.18, 53.00),
        ("Wolverhampton", -2.13, 52.59),
        ("Walsall", -1.98, 52.59),
        ("Wigan", -2.63, 53.54),
        ("Bolton", -2.43, 53.58),
        ("Preston", -2.70, 53.76),
        ("Blackpool", -3.05, 53.82),
        ("Carlisle", -2.94, 54.90),
        ("Middlesbrough", -1.23, 54.57),
        ("Durham", -1.58, 54.78),
        ("Lancaster", -2.80, 54.05),
        ("Scarborough", -0.40, 54.28),
        ("Grimsby", -0.08, 53.57),
        ("Doncaster", -1.13, 53.52),
        ("Barnsley", -1.48, 53.55),
        ("Rotherham", -1.36, 53.43),
        ("Huddersfield", -1.79, 53.65),
        ("Bradford", -1.75, 53.80),
        ("Wakefield", -1.50, 53.68),
        ("Chester", -2.89, 53.19),
        ("Warrington", -2.59, 53.39),
        ("Crewe", -2.44, 53.10),
        ("Shrewsbury", -2.75, 52.71),
        ("Hereford", -2.72, 52.06),
        ("Worcester", -2.22, 52.19),
        ("Gloucester", -2.24, 51.86),
        ("Cheltenham", -2.08, 51.90),
        ("Salisbury", -1.80, 51.07),
        ("Winchester", -1.31, 51.06),
        ("Canterbury", 1.08, 51.28),
        ("Maidstone", 0.52, 51.27),
        ("Guildford", -0.57, 51.24),
        ("Crawley", -0.19, 51.11),
        ("Eastbourne", 0.28, 50.77),
        ("Hastings", 0.58, 50.85),
        ("Folkestone", 1.17, 51.08),
        ("Margate", 1.39, 51.39),
        ("Southend", 0.71, 51.54),
        ("Basildon", 0.49, 51.57),
        ("Harlow", 0.11, 51.77),
        ("Stevenage", -0.20, 51.90),
        ("Watford", -0.40, 51.66),
        ("Slough", -0.59, 51.51),
        ("High Wycombe", -0.75, 51.63),
        ("Aylesbury", -0.81, 51.82),
        ("Bedford", -0.46, 52.14),
        ("Cambridge Fens", 0.20, 52.40),
        ("Norwich Broads", 1.50, 52.70),
        ("The Wash", 0.35, 52.90),
        ("Lake District", -3.10, 54.45),
        ("Snowdonia", -4.00, 53.07),
        ("Pembrokeshire", -4.90, 51.70),
        ("Anglesey", -4.30, 53.28),
        ("Isle of Man", -4.50, 54.15),
        ("Orkney", -3.00, 59.00),
        ("Shetland", -1.15, 60.15),
        ("Hebrides", -7.00, 57.50),
        ("Falkirk", -3.78, 56.00),
        ("Stirling", -3.94, 56.12),
        ("Perth", -3.44, 56.40),
        ("Dumfries", -3.61, 55.07),
        ("Ayr", -4.63, 55.46),
        ("Kilmarnock", -4.50, 55.61),
        ("Paisley", -4.43, 55.85),
        ("Motherwell", -3.99, 55.79),
        ("Livingston", -3.52, 55.89),
        ("Kirkcaldy", -3.16, 56.11),
        ("Dunfermline", -3.44, 56.07),
        ("Inverclyde", -4.75, 55.94),
        ("Argyll", -5.50, 56.20),
        ("Caithness", -3.50, 58.45),
        ("Sutherland", -4.40, 58.20),
        ("Moray", -3.30, 57.65),
        ("Aberdeenshire", -2.20, 57.30),
        ("Scottish Borders", -2.80, 55.55),
        ("Galloway", -4.50, 54.90),
        ("Wigtown", -4.44, 54.87),
        ("Stranraer", -5.03, 54.90),
        ("Campbeltown", -5.61, 55.42),
        ("Oban", -5.47, 56.42),
        ("Fort William", -5.11, 56.82),
        ("Ullapool", -5.16, 57.90),
        ("Wick", -3.09, 58.44),
        ("Thurso", -3.52, 58.60),
        ("Stornoway", -6.39, 58.21),
        ("Lerwick", -1.15, 60.15),
        ("Kirkwall", -2.96, 58.98),
        # Iberia extras
        ("Toledo", -4.02, 39.86),
        ("Salamanca", -5.66, 40.97),
        ("Burgos", -3.70, 42.34),
        ("Leon", -5.57, 42.60),
        ("Logrono", -2.45, 42.47),
        ("San Sebastian", -1.98, 43.32),
        ("Vitoria", -2.67, 42.85),
        ("Albacete", -1.86, 38.99),
        ("Ciudad Real", -3.93, 38.99),
        ("Badajoz", -6.97, 38.88),
        ("Caceres", -6.37, 39.48),
        ("Huelva", -6.95, 37.26),
        ("Jaen", -3.79, 37.77),
        ("Almeria", -2.46, 36.84),
        ("Cartagena", -0.98, 37.60),
        ("Castellon", -0.04, 39.99),
        ("Tarragona", 1.25, 41.12),
        ("Girona", 2.82, 41.98),
        ("Lleida", 0.62, 41.62),
        ("Huesca", -0.41, 42.14),
        ("Teruel", -1.11, 40.34),
        ("Cuenca", -2.14, 40.07),
        ("Guadalajara", -3.16, 40.63),
        ("Segovia", -4.12, 40.95),
        ("Avila", -4.70, 40.66),
        ("Soria", -2.47, 41.76),
        ("Palencia", -4.53, 42.01),
        ("Zamora", -5.75, 41.50),
        ("Ourense", -7.86, 42.34),
        ("Lugo", -7.56, 43.01),
        ("Pontevedra", -8.64, 42.43),
        ("Braganca", -6.76, 41.81),
        ("Guarda", -7.27, 40.54),
        ("Viseu", -7.91, 40.66),
        ("Aveiro", -8.65, 40.64),
        ("Leiria", -8.81, 39.74),
        ("Setubal", -8.89, 38.52),
        ("Beja", -7.86, 38.02),
        ("Portalegre", -7.43, 39.29),
        # Italy extras
        ("Brescia", 10.21, 45.54),
        ("Bergamo", 9.67, 45.70),
        ("Como", 9.09, 45.81),
        ("Varese", 8.83, 45.82),
        ("Novara", 8.62, 45.45),
        ("Alessandria", 8.62, 44.91),
        ("Asti", 8.21, 44.90),
        ("Cuneo", 7.55, 44.39),
        ("Savona", 8.48, 44.31),
        ("La Spezia", 9.83, 44.11),
        ("Parma", 10.33, 44.80),
        ("Modena", 10.93, 44.65),
        ("Ferrara", 11.62, 44.84),
        ("Ravenna", 12.20, 44.42),
        ("Rimini", 12.57, 44.06),
        ("Forli", 12.04, 44.22),
        ("Pesaro", 12.91, 43.91),
        ("Macerata", 13.45, 43.30),
        ("Ascoli Piceno", 13.58, 42.85),
        ("L'Aquila", 13.40, 42.35),
        ("Pescara", 14.21, 42.46),
        ("Campobasso", 14.67, 41.56),
        ("Foggia", 15.55, 41.46),
        ("Lecce", 18.17, 40.35),
        ("Brindisi", 17.94, 40.64),
        ("Potenza", 15.81, 40.64),
        ("Matera", 16.60, 40.67),
        ("Cosenza", 16.25, 39.30),
        ("Catanzaro", 16.59, 38.91),
        ("Reggio Emilia", 10.63, 44.70),
        ("Piacenza", 9.69, 45.05),
        ("Cremona", 10.02, 45.13),
        ("Mantua", 10.79, 45.16),
        ("Vicenza", 11.55, 45.55),
        ("Treviso", 12.24, 45.67),
        ("Udine", 13.24, 46.07),
        ("Pordenone", 12.66, 45.96),
        ("Bolzano", 11.35, 46.50),
        ("Trento", 11.12, 46.07),
        ("Aosta", 7.32, 45.74),
        ("Livorno", 10.31, 43.55),
        ("Arezzo", 11.88, 43.46),
        ("Grosseto", 11.11, 42.76),
        ("Viterbo", 12.11, 42.42),
        ("Latina", 12.90, 41.47),
        ("Frosinone", 13.35, 41.64),
        ("Caserta", 14.33, 41.07),
        ("Salerno", 14.77, 40.68),
        ("Benevento", 14.78, 41.13),
        ("Avellino", 14.79, 40.91),
        ("Sassari", 8.56, 40.73),
        ("Nuoro", 9.33, 40.32),
        ("Oristano", 8.59, 39.90),
        ("Syracuse", 15.29, 37.08),
        ("Trapani", 12.51, 38.02),
        ("Agrigento", 13.59, 37.31),
        ("Ragusa", 14.73, 36.93),
        ("Enna", 14.28, 37.57),
        ("Caltanissetta", 14.06, 37.49),
        # Eastern extras
        ("Lublin Voivodeship", 22.60, 51.20),
        ("Rzeszow", 22.00, 50.04),
        ("Kielce", 20.63, 50.87),
        ("Olsztyn", 20.48, 53.78),
        ("Bialystok Region", 23.20, 53.10),
        ("Torun", 18.60, 53.01),
        ("Elblag", 19.40, 54.16),
        ("Slupsk", 17.03, 54.46),
        ("Koszalin", 16.18, 54.19),
        ("Gorzow", 15.24, 52.74),
        ("Zielona Gora", 15.51, 51.94),
        ("Opole", 17.92, 50.67),
        ("Czestochowa", 19.12, 50.81),
        ("Radom", 21.15, 51.40),
        ("Plock", 19.70, 52.55),
        ("Siedlce", 22.27, 52.17),
        ("Suwalki", 22.93, 54.10),
        ("Lomza", 22.08, 53.18),
        ("Przemysl", 22.77, 49.78),
        ("Nowy Sacz", 20.70, 49.62),
        ("Tarnow", 20.99, 50.01),
        ("Bielsko-Biala", 19.04, 49.82),
        ("Gliwice", 18.67, 50.29),
        ("Zabrze", 18.79, 50.32),
        ("Bytom", 18.91, 50.35),
        ("Ruda Slaska", 18.85, 50.26),
        ("Rybnik", 18.55, 50.10),
        ("Tychy", 18.99, 50.14),
        ("Dabrowa Gornicza", 19.19, 50.32),
        ("Sosnowiec", 19.17, 50.29),
        # More Balkans density
        ("Novi Sad", 19.84, 45.25),
        ("Nis", 21.90, 43.32),
        ("Kragujevac", 20.92, 44.01),
        ("Subotica", 19.67, 46.10),
        ("Osijek", 18.69, 45.55),
        ("Rijeka", 14.44, 45.33),
        ("Zadar", 15.23, 44.12),
        ("Pula", 13.85, 44.87),
        ("Banja Luka", 17.19, 44.77),
        ("Mostar", 17.81, 43.34),
        ("Tuzla", 18.67, 44.54),
        ("Zenica", 17.91, 44.20),
        ("Nis Region", 21.90, 43.32),
        ("Bitola", 21.33, 41.03),
        ("Ohrid", 20.80, 41.12),
        ("Shkoder", 19.51, 42.07),
        ("Durres", 19.45, 41.32),
        ("Vlore", 19.49, 40.47),
        ("Elbasan", 20.08, 41.11),
        ("Gjirokaster", 20.14, 40.08),
        ("Korce", 20.78, 40.62),
        ("Burgas", 27.47, 42.50),
        ("Ruse", 25.97, 43.85),
        ("Pleven", 24.62, 43.42),
        ("Stara Zagora", 25.63, 42.43),
        ("Craiova", 23.79, 44.32),
        ("Galati", 28.05, 45.44),
        ("Braila", 27.96, 45.27),
        ("Sibiu", 24.15, 45.80),
        ("Oradea", 21.93, 47.05),
        ("Arad", 21.32, 46.19),
        ("Suceava", 26.25, 47.65),
        ("Bacau", 26.91, 46.57),
        ("Ploiesti", 26.02, 44.94),
        ("Pitesti", 24.87, 44.86),
        ("Targu Mures", 24.56, 46.54),
        ("Baia Mare", 23.58, 47.66),
        ("Satu Mare", 22.88, 47.79),
        # Ukraine extras
        ("Zhytomyr", 28.66, 50.25),
        ("Poltava", 34.54, 49.59),
        ("Sumy", 34.80, 50.91),
        ("Cherkasy", 32.06, 49.44),
        ("Kirovohrad", 32.26, 48.51),
        ("Mykolaiv", 31.99, 46.97),
        ("Kherson", 32.62, 46.64),
        ("Uzhhorod", 22.30, 48.62),
        ("Ivano-Frankivsk", 24.71, 48.92),
        ("Ternopil", 25.59, 49.55),
        ("Rivne", 26.25, 50.62),
        ("Lutsk", 25.34, 50.75),
        ("Khmelnytskyi", 26.98, 49.42),
        ("Kremenchuk", 33.42, 49.07),
        ("Kryvyi Rih", 33.38, 47.91),
        ("Melitopol", 35.37, 46.85),
        ("Berdiansk", 36.80, 46.76),
        ("Kerch", 36.47, 45.36),
        ("Yalta", 34.16, 44.50),
        ("Feodosia", 35.38, 45.03),
        # Russia European extras
        ("Bryansk", 34.37, 53.25),
        ("Orel", 36.07, 52.97),
        ("Kursk", 36.19, 51.73),
        ("Belgorod", 36.59, 50.60),
        ("Lipetsk", 39.57, 52.60),
        ("Tambov", 41.45, 52.72),
        ("Ryazan", 39.74, 54.63),
        ("Tula", 37.62, 54.20),
        ("Kaluga", 36.27, 54.53),
        ("Vladimir", 40.41, 56.14),
        ("Ivanovo", 40.97, 57.00),
        ("Kostroma", 40.93, 57.77),
        ("Vologda", 39.88, 59.22),
        ("Cherepovets", 37.90, 59.13),
        ("Petrozavodsk", 34.35, 61.78),
        ("Murmansk Oblast", 33.00, 68.00),
        ("Karelia", 34.00, 63.00),
        ("Pskov Region", 28.50, 57.50),
        ("Novgorod Region", 31.50, 58.50),
        ("Smolensk Region", 32.50, 54.80),
        ("Kaluga Region", 36.00, 54.50),
        ("Tver Region", 35.50, 57.00),
        ("Yaroslavl Region", 39.50, 57.60),
        ("Ivanovo Region", 41.00, 57.00),
        ("Vladimir Region", 40.50, 56.10),
        ("Ryazan Region", 40.00, 54.60),
        ("Tula Region", 37.50, 54.00),
        ("Orel Region", 36.00, 53.00),
        ("Kursk Region", 36.20, 51.70),
        ("Belgorod Region", 36.60, 50.60),
        ("Voronezh Region", 39.20, 51.70),
        ("Lipetsk Region", 39.50, 52.60),
        ("Tambov Region", 41.50, 52.70),
        ("Rostov Region", 40.00, 47.50),
        ("Krasnodar Region", 39.00, 45.00),
        ("Stavropol", 41.97, 45.04),
        ("Volgograd", 44.50, 48.71),
        ("Astrakhan", 48.04, 46.35),
        ("Saratov", 46.03, 51.53),
        ("Samara", 50.15, 53.20),
        ("Penza", 45.00, 53.20),
        ("Ulyanovsk", 48.39, 54.31),
        ("Kazan", 49.12, 55.79),
        ("Nizhny Novgorod Region", 44.00, 56.30),
        ("Cheboksary", 47.25, 56.14),
        ("Yoshkar-Ola", 47.89, 56.63),
        ("Saransk", 45.17, 54.18),
        ("Ufa", 55.97, 54.74),
        ("Perm", 56.25, 58.01),
        ("Kirov", 49.66, 58.60),
        ("Syktyvkar", 50.84, 61.67),
        ("Naryan-Mar", 53.09, 67.64),
        ("Vorkuta", 64.00, 67.50),
        ("Salekhard", 66.60, 66.53),
        # Black Sea / Caucasus extras
        ("Sochi", 39.72, 43.60),
        ("Novorossiysk", 37.77, 44.72),
        ("Tuapse", 39.08, 44.10),
        ("Anapa", 37.32, 44.89),
        ("Gelendzhik", 38.08, 44.56),
        ("Maikop", 40.11, 44.61),
        ("Nalchik", 43.62, 43.50),
        ("Vladikavkaz", 44.67, 43.02),
        ("Grozny", 45.69, 43.32),
        ("Makhachkala", 47.50, 42.98),
        ("Derbent", 48.29, 42.07),
        ("Batumi", 41.64, 41.65),
        ("Kutaisi", 42.70, 42.27),
        ("Sukhumi", 41.02, 43.00),
        ("Gyumri", 43.85, 40.79),
        ("Vanadzor", 44.49, 40.81),
        ("Ganja", 46.36, 40.68),
        ("Sumqayit", 49.67, 40.59),
        ("Nakhchivan", 45.41, 39.21),
        # Anatolia extras
        ("Bursa Region", 29.10, 40.20),
        ("Eskisehir", 30.52, 39.78),
        ("Kocaeli", 29.92, 40.77),
        ("Sakarya", 30.40, 40.78),
        ("Balikesir", 27.89, 39.65),
        ("Canakkale", 26.41, 40.15),
        ("Tekirdag", 27.51, 40.98),
        ("Kirklareli", 27.23, 41.73),
        ("Zonguldak", 31.79, 41.45),
        ("Kastamonu", 33.78, 41.39),
        ("Sinop", 35.15, 42.03),
        ("Corum", 34.95, 40.55),
        ("Amasya", 35.83, 40.65),
        ("Tokat", 36.55, 40.32),
        ("Sivas", 37.02, 39.75),
        ("Erzurum", 41.28, 39.90),
        ("Erzincan", 39.49, 39.75),
        ("Malatya", 38.31, 38.36),
        ("Gaziantep", 37.38, 37.07),
        ("Sanliurfa", 38.79, 37.17),
        ("Diyarbakir", 40.23, 37.91),
        ("Mardin", 40.74, 37.31),
        ("Van", 43.38, 38.50),
        ("Kars", 43.10, 40.60),
        ("Artvin", 41.82, 41.18),
        ("Rize", 40.52, 41.02),  # placeholder fix: will skip invalid
        ("Rize Coast", 40.52, 41.02),
        ("Ordu", 37.88, 40.98),
        ("Giresun", 38.39, 40.91),
        ("Rize Fix", 39.00, 41.00),
        ("Gumushane", 39.48, 40.46),
        ("Bayburt", 40.23, 40.26),
        ("Aydin", 27.84, 37.84),
        ("Mugla", 28.37, 37.22),
        ("Denizli", 29.09, 37.78),
        ("Isparta", 30.56, 37.76),
        ("Burdur", 30.29, 37.72),
        ("Afyon", 30.54, 38.76),
        ("Usak", 29.41, 38.67),
        ("Manisa", 27.43, 38.61),
        ("Kutahya", 29.98, 39.42),
        ("Bilecik", 29.98, 40.14),
        ("Yalova", 29.28, 40.66),
        ("Duzce", 31.16, 40.84),
        ("Bolu", 31.61, 40.74),
        ("Karabuk", 32.63, 41.20),
        ("Bartin", 32.34, 41.64),
        ("Kastamonu Coast", 33.80, 41.90),
        ("Cankiri", 33.62, 40.60),
        ("Kirikkale", 33.51, 39.85),
        ("Yozgat", 34.81, 39.82),
        ("Nevsehir", 34.71, 38.62),
        ("Kayseri", 35.49, 38.73),
        ("Nigde", 34.68, 37.97),
        ("Aksaray", 34.03, 38.37),
        ("Karaman", 33.22, 37.18),
        ("Mersin", 34.64, 36.80),
        ("Hatay", 36.16, 36.20),
        ("Osmaniye", 36.25, 37.07),
        ("Kilis", 37.12, 36.72),
        ("Kahramanmaras", 36.92, 37.59),
        ("Adiyaman", 38.28, 37.76),
        ("Batman", 41.13, 37.89),
        ("Siirt", 41.94, 37.93),
        ("Sirnak", 42.46, 37.52),
        ("Hakkari", 43.74, 37.57),
        ("Agri", 43.05, 39.72),
        ("Igdir", 44.05, 39.92),
        ("Ardahan", 42.70, 41.11),
        ("Artvin District", 41.82, 41.18),
        ("Rize District", 40.52, 41.02),
    ]
    # Drop accidental placeholder typos
    cleaned: List[Tuple[str, float, float]] = []
    seen_lower = set()
    for name, lon, lat in places:
        key = name.strip().lower()
        if not key or "rory" in key:
            continue
        if key in seen_lower:
            continue
        seen_lower.add(key)
        cleaned.append((name.strip(), float(lon), float(lat)))
    return cleaned


def build_gazetteer_canvas(
    places: Optional[List[Tuple[str, float, float]]] = None,
) -> List[Tuple[str, float, float]]:
    """Return (name, canvas_x, canvas_y)."""
    src = places if places is not None else europe_gazetteer()
    out: List[Tuple[str, float, float]] = []
    for name, lon, lat in src:
        cx, cy = lonlat_to_canvas(lon, lat)
        out.append((name, cx, cy))
    return out


def assign_names_to_provinces(
    base_provinces: List[Dict[str, Any]],
    geometry_provinces: List[Dict[str, Any]],
    gazetteer_canvas: Optional[List[Tuple[str, float, float]]] = None,
) -> Dict[str, Any]:
    """Pure assignment. Returns stats + renamed province list (copies).

    Rules:
    - Locked European names kept if unique.
    - Placeholders / non-Europe names replaced by nearest free gazetteer name.
    - If gazetteer exhausted, fall back to "Region {id}" (should not happen with dense list).
    - All output names unique.
    """
    gaz = list(gazetteer_canvas) if gazetteer_canvas is not None else build_gazetteer_canvas()
    geom_by_id = {int(g["id"]): g for g in geometry_provinces}

    # Compute centroids
    centroids: Dict[int, Tuple[float, float]] = {}
    for p in base_provinces:
        pid = int(p["id"])
        g = geom_by_id.get(pid)
        if g and g.get("points"):
            centroids[pid] = polygon_centroid(g["points"])
        elif g and g.get("label_anchor"):
            la = g["label_anchor"]
            centroids[pid] = (float(la[0]), float(la[1]))
        else:
            centroids[pid] = (0.0, 0.0)

    used: set = set()
    result: List[Dict[str, Any]] = []
    renamed = 0
    kept = 0
    fallback = 0

    # First pass: lock unique good names
    claimed_locked: Dict[str, int] = {}
    for p in base_provinces:
        name = str(p.get("name", "")).strip()
        if _is_locked(name) and name.lower() not in claimed_locked:
            claimed_locked[name.lower()] = int(p["id"])
            used.add(name.lower())

    # Sort by id for stability
    ordered = sorted(base_provinces, key=lambda p: int(p["id"]))

    for p in ordered:
        pid = int(p["id"])
        old = str(p.get("name", "")).strip()
        new_p = dict(p)

        if _is_locked(old) and claimed_locked.get(old.lower()) == pid:
            new_p["name"] = old
            kept += 1
            result.append(new_p)
            continue

        if not _needs_rename(old) and old.lower() not in used:
            # Keep reasonable unique name already present
            new_p["name"] = old
            used.add(old.lower())
            kept += 1
            result.append(new_p)
            continue

        # Need a new name: nearest free gazetteer entry
        cx, cy = centroids.get(pid, (0.0, 0.0))
        best_name: Optional[str] = None
        best_d = float("inf")
        for gname, gx, gy in gaz:
            key = gname.lower()
            if key in used:
                continue
            d = (gx - cx) ** 2 + (gy - cy) ** 2
            if d < best_d:
                best_d = d
                best_name = gname

        if best_name is None:
            # Exhausted — unique synthetic
            best_name = f"Theater Sector {pid}"
            fallback += 1
        else:
            renamed += 1

        # Ensure uniqueness if synthetic collision
        final = best_name
        n = 2
        while final.lower() in used:
            final = f"{best_name} {n}"
            n += 1
        used.add(final.lower())
        new_p["name"] = final
        result.append(new_p)

    # Preserve original order loosely by sorting ids then we already sorted —
    # restore input order:
    by_id = {int(p["id"]): p for p in result}
    ordered_out = [by_id[int(p["id"])] for p in base_provinces]

    placeholders_left = sum(
        1 for p in ordered_out if PLACEHOLDER_RE.match(str(p.get("name", "")))
    )
    non_europe_left = sum(
        1 for p in ordered_out if str(p.get("name", "")).lower() in NON_EUROPE_EXACT
    )
    names = [str(p.get("name", "")) for p in ordered_out]
    unique = len(set(n.lower() for n in names))

    return {
        "provinces": ordered_out,
        "stats": {
            "total": len(ordered_out),
            "renamed": renamed,
            "kept": kept,
            "fallback": fallback,
            "placeholders_remaining": placeholders_left,
            "non_europe_remaining": non_europe_left,
            "unique_names": unique,
            "gazetteer_size": len(gaz),
        },
    }


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def run_on_dir(data_dir: Path, write: bool = False) -> Dict[str, Any]:
    base_path = data_dir / "provinces_base.json"
    geom_path = data_dir / "provinces_geometry.json"
    if not base_path.exists() or not geom_path.exists():
        raise FileNotFoundError(f"Missing base/geometry under {data_dir}")

    base_payload = load_json(base_path)
    geom_payload = load_json(geom_path)
    base_list = base_payload["provinces"] if isinstance(base_payload, dict) else base_payload
    geom_list = geom_payload["provinces"] if isinstance(geom_payload, dict) else geom_payload

    out = assign_names_to_provinces(base_list, geom_list)
    stats = out["stats"]

    if write:
        if isinstance(base_payload, dict):
            new_payload = dict(base_payload)
            new_payload["provinces"] = out["provinces"]
            meta = dict(new_payload.get("meta") or {})
            meta["names_assigned"] = "assign_europe_province_names.py"
            meta["name_assignment_unique"] = stats["unique_names"]
            new_payload["meta"] = meta
            write_json(base_path, new_payload)
        else:
            write_json(base_path, out["provinces"])

    return stats


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dir",
        default="data/provinces_full_europe",
        help="Province data directory relative to project root",
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="Write updated provinces_base.json (default is dry-run)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Force dry-run even if --write is set",
    )
    args = parser.parse_args(argv)

    data_dir = Path(args.dir)
    if not data_dir.is_absolute():
        data_dir = ROOT / data_dir

    write = bool(args.write) and not args.dry_run
    stats = run_on_dir(data_dir, write=write)
    mode = "WROTE" if write else "DRY-RUN"
    print(f"[{mode}] {data_dir}")
    for k, v in stats.items():
        print(f"  {k}: {v}")

    ok = (
        stats["placeholders_remaining"] == 0
        and stats["non_europe_remaining"] == 0
        and stats["unique_names"] == stats["total"]
    )
    if not ok:
        print("FAIL: naming quality gates not met", file=sys.stderr)
        return 1
    print("PASS: unique Europe-theater names, zero placeholders / non-Europe leftovers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
