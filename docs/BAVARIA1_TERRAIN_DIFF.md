# BAVARIA-1 terrain diff

Generator: `tools/map_generation/scripts/polish_world_accurate_terrain.py`.
Alpine codes: `tools/map_generation/data/alpine_nuts3.txt` (NUTS, never province id).

79 land rows changed. Province ids, names, order, and every other key are unchanged.
`province_resources_layer.json` was not rewritten. Terrain-only regen is
`--terrain-only`. A second run reproduces both JSON files byte-for-byte.

| change | rows |
|--------|------|
| mountains → plains | 31 |
| mountains → forest | 1 (Kronobergs län, latitude above 55) |
| plains → mountains | 43 |
| plains → hills | 4 |

The 27 `"berg"` false mountains leave `mountains`: 25 become plains, Bergamo becomes plains, Kronobergs län becomes forest. Landes (FRI13) leaves because `"andes"` is now a whole word. The eight Bavarian rim Kreise that were plains become mountains: Garmisch-Partenkirchen, Berchtesgadener Land, Bad Tölz-Wolfratshausen, Miesbach, Oberallgäu, Ostallgäu, Weilheim-Schongau, Traunstein. The German Alpine Convention annex has no foothill column, so Weilheim-Schongau and Traunstein are mountains. The same annex also sets Rosenheim (city and Landkreis), Kaufbeuren, Kempten, and Lindau.

Hills (second column) are basin or valley-floor codes inside the perimeter: Salzburg und Umgebung (AT323), Rheintal-Bodenseegebiet (AT342), Östliche Obersteiermark (AT223), Westliche Obersteiermark (AT226). Liezen and the High Tauern stay mountains.

Left off the list on purpose: Bergamo (ITC46, a `"berg"` hit, not a predominantly alpine province), Unterallgäu (DE27C, not on the German annex), and partial plateau units this board cannot split (Isère, Ain, Drôme, Bern, Vaud, Torino, and the other partial Alpine Convention provinces).

## Hameln-Pyrmont

Hameln-Pyrmont (710367, DE923) was `mountains` with no name evidence. The old lists match substrings of `alps`, `himal`, `andes`, `rocky`, `tibet`, `caucas`, `atlas`, `pyrene`, `carpath`, `zagros`, `hindu kush`, `pamir`, `altai`, `urals`, `appalach`, `sierra`, `cascade`, `alpen`, `berg`, `montblanc`, `tirol`, `tyrol`, and `mountain`. "Hameln-Pyrmont" contains none of those. The Europe rule (`alpen|berg|tirol|savoie|valais|tyrol|graub`) does not match either. `polish()` copied the stored terrain when no rule fired, so the value stuck. Latitude is about 52, which the latitude rule calls plains. DE923 is Weserbergland, not in the Alpine Convention perimeter. It is plains now.

The same sticky copy, not a keyword, is why these also left `mountains`: Terras de Trás-os-Montes (711128, "Montes" is not a listed token), Gibraltar (711520), and Hong Kong (905844).

Rows already mountains for a real token stay mountains and are absent below: Osttirol, Tiroler Oberland, Tiroler Unterland, Valais, Graubünden, Savoie, Haute-Savoie, plus the non-Alpine name hits (Appalachians, Moose Mountain, Rocky Mountain, Mountain Province). US state ranges stay mountains through the state-FIPS fallback. Sierra Leone stays plains because `sierra` is not a global word token.

## Rows

| pid | NUTS | name | old | new |
|-----|------|------|-----|-----|
| 710023 | AT211 | Klagenfurt-Villach | plains | mountains |
| 710024 | AT212 | Oberkärnten | plains | mountains |
| 710025 | AT213 | Unterkärnten | plains | mountains |
| 710027 | AT222 | Liezen | plains | mountains |
| 710028 | AT223 | Östliche Obersteiermark | plains | hills |
| 710031 | AT226 | Westliche Obersteiermark | plains | hills |
| 710037 | AT321 | Lungau | plains | mountains |
| 710038 | AT322 | Pinzgau-Pongau | plains | mountains |
| 710039 | AT323 | Salzburg und Umgebung | plains | hills |
| 710040 | AT331 | Außerfern | plains | mountains |
| 710041 | AT332 | Innsbruck | plains | mountains |
| 710045 | AT341 | Bludenz-Bregenzer Wald | plains | mountains |
| 710046 | AT342 | Rheintal-Bodenseegebiet | plains | hills |
| 710131 | CH051 | Glarus | plains | mountains |
| 710133 | CH053 | Appenzell Ausserrhoden | plains | mountains |
| 710134 | CH054 | Appenzell Innerrhoden | plains | mountains |
| 710139 | CH062 | Uri | plains | mountains |
| 710140 | CH063 | Schwyz | plains | mountains |
| 710141 | CH064 | Obwalden | plains | mountains |
| 710142 | CH065 | Nidwalden | plains | mountains |
| 710144 | CH070 | Ticino | plains | mountains |
| 710177 | DE125 | Heidelberg, Stadtkreis | mountains | plains |
| 710206 | DE213 | Rosenheim, Kreisfreie Stadt | plains | mountains |
| 710208 | DE215 | Berchtesgadener Land | plains | mountains |
| 710209 | DE216 | Bad Tölz-Wolfratshausen | plains | mountains |
| 710211 | DE218 | Ebersberg | mountains | plains |
| 710216 | DE21D | Garmisch-Partenkirchen | plains | mountains |
| 710217 | DE21E | Landsberg am Lech | mountains | plains |
| 710218 | DE21F | Miesbach | plains | mountains |
| 710223 | DE21K | Rosenheim, Landkreis | plains | mountains |
| 710224 | DE21L | Starnberg | mountains | plains |
| 710225 | DE21M | Traunstein | plains | mountains |
| 710226 | DE21N | Weilheim-Schongau | plains | mountains |
| 710239 | DE231 | Amberg, Kreisfreie Stadt | mountains | plains |
| 710242 | DE234 | Amberg-Sulzbach | mountains | plains |
| 710249 | DE241 | Bamberg, Kreisfreie Stadt | mountains | plains |
| 710253 | DE245 | Bamberg, Landkreis | mountains | plains |
| 710265 | DE254 | Nürnberg, Kreisfreie Stadt | mountains | plains |
| 710270 | DE259 | Nürnberger Land | mountains | plains |
| 710280 | DE267 | Haßberge | mountains | plains |
| 710282 | DE269 | Miltenberg | mountains | plains |
| 710287 | DE272 | Kaufbeuren, Kreisfreie Stadt | plains | mountains |
| 710288 | DE273 | Kempten (Allgäu), Kreisfreie Stadt | plains | mountains |
| 710290 | DE275 | Aichach-Friedberg | mountains | plains |
| 710295 | DE27A | Lindau (Bodensee) | plains | mountains |
| 710296 | DE27B | Ostallgäu | plains | mountains |
| 710299 | DE27E | Oberallgäu | plains | mountains |
| 710326 | DE715 | Bergstraße | mountains | plains |
| 710340 | DE725 | Vogelsbergkreis | mountains | plains |
| 710346 | DE736 | Waldeck-Frankenberg | mountains | plains |
| 710367 | DE923 | Hameln-Pyrmont | mountains | plains |
| 710376 | DE934 | Lüchow-Dannenberg | mountains | plains |
| 710422 | DEA29 | Heinsberg | mountains | plains |
| 710423 | DEA2A | Oberbergischer Kreis | mountains | plains |
| 710424 | DEA2B | Rheinisch-Bergischer Kreis | mountains | plains |
| 710482 | DEB3D | Donnersbergkreis | mountains | plains |
| 710522 | DEE0E | Wittenberg | mountains | plains |
| 710531 | DEF09 | Pinneberg | mountains | plains |
| 710535 | DEF0D | Segeberg | mountains | plains |
| 710553 | DEG0H | Sonneberg | mountains | plains |
| 710760 | FRI13 | Landes | mountains | plains |
| 710795 | FRL01 | Alpes-de-Haute-Provence | plains | mountains |
| 710796 | FRL02 | Hautes-Alpes | plains | mountains |
| 710797 | FRL03 | Alpes-Maritimes | plains | mountains |
| 710862 | ITC14 | Verbano-Cusio-Ossola | plains | mountains |
| 710867 | ITC20 | Valle d’Aosta/Vallée d’Aoste | plains | mountains |
| 710875 | ITC44 | Sondrio | plains | mountains |
| 710876 | ITC46 | Bergamo | mountains | plains |
| 710922 | ITH10 | Bolzano-Bozen | plains | mountains |
| 710923 | ITH20 | Trento | plains | mountains |
| 710926 | ITH33 | Belluno | plains | mountains |
| 710966 | LI000 | Liechtenstein | plains | mountains |
| 711128 | PT11E | Terras de Trás-os-Montes | mountains | plains |
| 711220 | SE212 | Kronobergs län | mountains | forest |
| 711236 | SI033 | Koroška | plains | mountains |
| 711243 | SI042 | Gorenjska | plains | mountains |
| 711244 | SI043 | Goriška | plains | mountains |
| 711520 | GI001 | Gibraltar | mountains | plains |
| 905844 | — | Hong Kong | mountains | plains |
