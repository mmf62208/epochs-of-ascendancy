# Map visual playtest response (2026-07-28)

## Human findings → actions

| Finding | Action |
|---------|--------|
| Ocean void-hex gone | Keep continuous ocean floor + terrain off default |
| Want slight sea-zone differences | `continuous_sea_fill_color(..., zone_hue_shift)` from sea name / region |
| Germany = spiderweb of lines | **Root cause:** unmatched GIS edges drawn as "outer" country borders in **owner red** |
| Maginot GER lines over FRA | Same: thick owner-colored outer edges; now international only, **dark** frontiers |
| Love pink select outline | Keep (no change) |
| Country names hard to read | Nation labels: light text + stronger outline |
| Save slots pink corners unreadable | `style_detail_panel_flat` + larger rows + scroll min height |
| Load leaves menu open | `_closing=true` + close after successful load |
| Greenland/Iceland / US alignment | Geometry data quality (not runtime slide); densify plan below |
| Africa / CA / SA larger provinces | Same densify approach as US merge |

## World-class border stack (HOI4 / EU4 / V3)

1. **Fills** = nation ownership (solid, opaque) — done  
2. **International frontiers** = near-black thin–medium stroke (NOT owner color) — fixed  
3. **Province internal edges** = very faint, **tactical zoom only** — fixed  
4. **Coast** = land↔sea shared edges only — fixed  
5. **Selection** = bright pink outline (player loved) — keep  
6. **Hover** = lighter outline — keep  

**Do not** stroke every polygon edge in nation color — GIS NUTS never shares exact verts → spiderweb.

## Anchoring / "provinces sliding"

Provinces are already in a **single canvas** (`ProvinceContainers` identity scale). They do not slide at runtime. Misplacement of Greenland/Iceland/parts of Americas is **geometry / projection / source-block quality**, not camera decoupling.

**Next data work (not this pass):**
- Audit lon/lat → canvas for Arctic islands  
- RoW densify: Africa / Central America / South America playable merges (US-merge pattern: fewer larger playable provinces while keeping enough for GS flexibility)  
- Optional: snap shared borders (topology repair) so international edges match better  

## Player options (recommended)

| Option | Default | Why |
|--------|---------|-----|
| Clean political / terrain underlay | Clean | Readability |
| Province internal borders | Tactical only | Density |
| Sea zone tint strength | Subtle | Naval readability |
| Label contrast mode | High | Bright fills |

## FPS note

Pan-up lag still soft; other directions improved. Border rebuild no longer every outer edge × owner color — should help tactical Europe.

