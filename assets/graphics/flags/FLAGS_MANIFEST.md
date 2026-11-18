# FLAGS_MANIFEST: VICTORY-SCENE-1 flag set (Ink, 11 Nov 2026)

These are clean vector redraws by Ink: hand-written SVG, rendered with cairosvg (`tools/make_flags.py`). **Own work.** National flag designs are public symbols and generally not subject to copyright; these drawings are our own reproductions. Nothing was downloaded or traced.

**EOA symbol rule (applies to every flag in EOA):**
- No swastika, and **no Nazi-era or fascist flag or emblem of any kind**: no 1935–45 German national flag, no Reichskriegsflagge, no swastika eagles, no fasces, no Francoist/Nationalist Spanish flags or the eagle of St John, no Ustaše, no Iron Guard symbols.
- No Rising Sun military flag.
- **GER uses black-red-gold** (OP decision, 11 Nov 2026), deliberately not the historical 1936 flag.
- The minors use their **plain national/civil flags as valid on 1 Jan 1936**. Royal/state arms are omitted for legibility at small sizes.

## Files per tag (`flags/`)
| File | What |
|---|---|
| `<tag>.svg` | vector master (true proportion) |
| `<tag>_true_h960.png` | true proportion, 960 px tall. **Use this for the in-scene cloth** (the template keeps each flag's real proportion) |
| `<tag>_1440x960.png`, `_720x480.png`, `_96x64.png`, `_48x32.png` | fixed 3:2 canvases for UI. The flag sits at its true proportion, centred, with transparent letterbox padding. The 96/48 px versions are downsampled from a 4× render for crisp edges. The 48×32 size matches the existing `data/nations/flags/` convention. |
| `generic_field_mask.svg`, `generic_field_mask_h960.png` (1440×960), `generic_field_mask_720x480.png` | L8 mask for the GENERIC tint. White = the slate field plus the rosette centre. |
| `flags_meta.json` | ratio, pixel size and source line per tag |
| `_flags_sheet.png` | overview (all 14) |

## Majors + GENERIC
| Tag | SVG | Proportion | True-ratio PNG | Design source / notes |
|---|---|---|---|---|
| FRA | `fra.svg` | 2:3 (h:w) | 1440×960 | Tricolour, equal vertical bands blue-white-red (Third Republic usage, 1936). |
| ENG | `eng.svg` | 1:2 (h:w) | 1920×960 | Union Flag (1801 design), 1:2, counterchanged saltire, standard geometric construction. |
| USA | `usa.svg` | 10:19 (h:w) | 1824×960 | 48-star flag (1912-1959), 6 rows x 8 stars; proportions per Executive Order 1637 (1912): union 7/13 hoist x 0.76 hoist, star diameter 0.0616 hoist. |
| SOV | `sov.svg` | 1:2 (h:w) | 1920×960 | USSR state flag, 1924-1936 pattern (red field; gold hammer and sickle in the canton with a red, gold-bordered five-pointed star above). Simplified own drawing. |
| ITA | `ita.svg` | 2:3 (h:w) | 1440×960 | Kingdom of Italy state flag (1848-1946): green-white-red tricolour, Savoy shield (red, white cross, blue bordure) surmounted by the royal crown. Simplified own drawing; no fasces. |
| JAP | `jap.svg` | 7:10 (h:w) | 1371×960 | Hinomaru, merchant/national flag per Proclamation No. 57 (1870): 7:10, disc diameter 3/5 hoist, offset 1/100 fly toward hoist. Rising Sun (military) flag deliberately NOT used. |
| GER | `ger.svg` | 3:5 (h:w) | 1600×960 | Black-red-gold horizontal tricolour, 3:5 (OP decision 11 Nov 2026). NOT the 1936 historical flag: EOA symbol rule bars every Nazi-era flag/emblem. |
| GENERIC | `generic.svg` | 2:3 (h:w) | 1440×960 | EOA neutral banner (own design): slate field, gold hoist band, ivory 8-point compass rosette. Fallback for any tag without a flag file. Ship may tint the field with MapManager.get_country_color(tag). |

## 1936 minors (added 11 Nov 2026, OP order POL → NLD → SPA → TUR → YUG → BEL)
| Tag | SVG | Proportion | True-ratio PNG | Design source / notes |
|---|---|---|---|---|
| POL | `pol.svg` | 5:8 (h:w) | 1536×960 | Second Republic national flag (in force 1 Jan 1936): white over red, equal halves, 5:8. Plain national version (state flag with the white eagle on the white band not used). |
| NLD | `nld.svg` | 2:3 (h:w) | 1440×960 | Kingdom of the Netherlands: red-white-blue horizontal tricolour, 2:3 (the form in use on 1 Jan 1936). |
| SPA | `spa.svg` | 2:3 (h:w) | 1440×960 | Second Spanish Republic tricolour (decree 27 Apr 1931; valid on 1 Jan 1936): red-yellow-purple (morado) equal bands, 2:3. Plain civil version (Republican arms omitted). NOT the 1936-39 Nationalist flags. |
| TUR | `tur.svg` | 2:3 (h:w) | 1440×960 | Republic of Turkey: white crescent and star on red, 2:3, geometry per the Turkish Flag Law (No. 2994, 29 May 1936; drawn without the 1/30 G white hoist hem); design unchanged from that in use on 1 Jan 1936. |
| YUG | `yug.svg` | 1:2 (h:w) | 1920×960 | Kingdom of Yugoslavia national flag (1918/1922-1941): blue-white-red horizontal tricolour, 1:2. Plain version (royal arms omitted). |
| BEL | `bel.svg` | 13:15 (h:w) | 1108×960 | Kingdom of Belgium: black-yellow-red vertical tricolour, 13:15 (official national-flag proportion; 2:3 civil usage also common). |

**Spain, flag choice for 1 Jan 1936:**
- **Chosen:** the Second Republic tricolour, red-yellow-purple (*morado*), in equal horizontal bands. It was adopted by decree on 27 Apr 1931 and was the legal flag on 1 Jan 1936.
- **Not used:**
  - the monarchy's red-yellow-red (1785/1843–1931; replaced in 1931);
  - the Republic's state flag with the arms (the plain civil form is used for legibility);
  - the Nationalist red-yellow-red flags adopted from Aug 1936, and the Francoist eagle of St John (1938–81). These postdate the start date and are excluded by the symbol rule anyway.

**Turkey:**
- Geometry per Flag Law No. 2994 (29 May 1936). The design was the same one in use on 1 Jan 1936.
- Construction, with G = hoist:
  - outer circle centre at ½G, diameter ½G;
  - inner circle offset 1/16 G, diameter 0.4G;
  - star circle diameter ¼G, placed ⅓G from the inner circle's edge (star centre at 0.8208G);
  - one star point faces the hoist.
- Drawn without the 1/30 G white hoist hem.

**Poland:** 5:8 per the 1927/28 regulations. This is the plain national flag; the state flag with the white eagle isn't used.

**Belgium:** 13:15 is the official national-flag proportion. 2:3 is also widely used for civil flags, and the 3:2 UI canvases letterbox it.

**Yugoslavia:** the Kingdom's blue-white-red at 1:2, without the royal arms.

**Colour values used:**
- FRA `#002395 / #FFFFFF / #ED2939`
- UK `#012169 / #FFFFFF / #C8102E`
- USA `#B22234 / #FFFFFF / #3C3B6E`
- SOV `#CC0000` with gold `#FFD200`
- ITA `#009246 / #FFFFFF / #CE2B37`, shield `#D21034` with a `#0067C6` bordure, crown `#E3B53B`
- JAP `#BC002D` on white
- GER `#000000 / #DD0000 / #FFCE00`
- GENERIC `#2E3A4E` with gold `#C9A54A` and ivory `#EDE6D3`
- POL `#FFFFFF / #DC143C`
- NLD `#AE1C28 / #FFFFFF / #21468B`
- SPA `#C60B1E / #FFC400 / #6C2D7C`
- TUR `#E30A17` / white
- YUG `#0C4076 / #FFFFFF / #C6363C`
- BEL `#000000 / #FDDA24 / #EF3340`

**Simplifications (by design):** the SOV hammer, sickle and star, and the ITA Savoy crown, are simplified vector emblems. They read correctly at 96 px and in the waving cloth; they aren't heraldic-exact.

## GENERIC banner and tint (OP decision, 11 Nov)
- **Use:** any tag with no flag file.
- **Tint:** `rgb = mix(tex.rgb, map.rgb, 0.35 * mask.r)`, using `generic_field_mask`.
- **`map` comes from** `MapManager.get_country_color(tag)` (scenario `countries[].color`). There's **no tint** if that's a stub default: `Color(0.45,0.55,0.65)` or `Color(0.5,0.5,0.6)`.
- **Untouched:** the gold band, ivory stripe, frame and rosette.
- **Examples:** `export/_preview/generic_tint_examples.png` (SWE `#006AA7`, DNK `#C8102E`).

**Repo target (Ship, VS-1 build):**
- `assets/graphics/flags/<tag>.png` (from `_true_h960`) and `assets/graphics/flags/generic_field_mask.png`.
- The existing `data/nations/flags/` (`.gdignore`, 48×32 UKR/MDA/PRC/MAN placeholders) can stay as it is for chips.
