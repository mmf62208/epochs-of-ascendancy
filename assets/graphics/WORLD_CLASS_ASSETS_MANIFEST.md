# World-Class Asset Pack (continued)

Skills: `game-asset-core` · `game-ui-icons` · `game-tilesets`

## UI chrome — `assets/graphics/ui/`

| Asset | Role |
|-------|------|
| `panel_frame_512.png` | 9-slice panel (cyan border, magenta corner ornaments). Margins ≈48px. |
| `progress_bar_frame.png` | Progress bar background track |
| `progress_bar_fill.png` | Progress bar fill (cyan→magenta) |

Wired via `RetrowaveTheme.style_detail_panel` / `style_world_panel` / `style_progress_bar`.

## HUD icons (expanded) — `assets/graphics/icons/hud/`

Prior nav set **plus**:

| Asset | Role |
|-------|------|
| `pause_*` / `play_*` | Clock control |
| `speed1..4_*` | Speed strip |
| `*_hover_*` / `*_pressed_*` | Interaction states (geometry-matched brightness) |

Hover/pressed wired in `HudIconLibrary.wire_icon_hover_states`.

## Terrain tiles — `assets/graphics/tiles/`

| Asset | Notes |
|-------|--------|
| `ocean_seamless.png` | Deep navy water (+ 2×2 preview) |
| `plains_seamless.png` | Olive plains mottling (+ 2×2 preview) |
| `hills_seamless.png` | Gray-brown hills (+ 2×2 preview) |

Palette tints applied in `MapRenderer._characterize_province_fill` via `TerrainTileLibrary` (soft blend; ownership colors remain primary).

## Code

| File | Change |
|------|--------|
| `scripts/ui/RetrowaveTheme.gd` | Texture StyleBox panel + progress bar |
| `scripts/ui/HudIconLibrary.gd` | Speed/pause + hover states |
| `scripts/ui/TopInfoBar.gd` | Pause/speed icons, hover feedback |
| `scripts/ui/NationalSpiritsScreen.gd` | Styled duration progress bars |
| `scripts/map/MapRenderer.gd` | Framed InfoPanel + terrain pack tints |
| `scripts/map/TerrainTileLibrary.gd` | Tile load + terrain tint helper |

## Known limits / next upgrades

- Speed2–4 icons are procedural multi-chevron composites (not full regen) — fine at 32px; regenerate later if needed.
- Plains/hills tiles not yet used as full textured poly fills (performance); tints only.
- Panel 9-slice margins are tuned for 512 source; odd aspect panels may show mild stretch.

## Pass 2 complete — see `PASS2_ASSETS_MANIFEST.md`

- Retrowave unit chips · tech domain icons · plains↔hills transitions · title wordmark

## Pass 3 complete — see `PASS3_ASSETS_MANIFEST.md`

- Unique bomber/sub/carrier/helo/logistics/rocket chips  
- Dedicated doctrine / support / strategic_future icons  
- Main menu wordmark  
- Live plains↔hills adjacency transition tint

## Pass 4 complete — see `PASS4_ASSETS_MANIFEST.md`

- Unique cruiser + frigate chips  
- Forest + desert seamless tiles  
- Menu panel chrome  
- Nation-color frames on unit counters (no icon washout)

## Pass 5 complete — see `PASS5_ASSETS_MANIFEST.md`

- Battleship chip  
- Tundra/snow tiles  
- Minimap frame chrome  
- Formation stack count badges

## Pass 6 complete — see `PASS6_ASSETS_MANIFEST.md`

- Amphib / APC / recon chips  
- Marsh tile  
- OOB formation list icons  
- Multi-icon fan-out for stacks of 2–4

## Pass 7 complete — see `PASS7_ASSETS_MANIFEST.md`

- AA / AT chips  
- Jungle tile  
- DesignPicker production icons  
- Zoom-scaled map unit counters

## Pass 8 complete — see `PASS8_ASSETS_MANIFEST.md`

- Coastal tile · fort/port chips  
- Multi-formation OOB strip on province select  
- Animated stack badge pulse

## Pass 9 complete — see `PASS9_ASSETS_MANIFEST.md`

- Player-only OOB strip filter  
- Fort/port Sprite2D markers on special_features  
- Convoy unit chip  
- Weather icon set (dry/mud/snow/storm) + toolbar legend + inspector img chip

## Pass 10 complete — see `PASS10_ASSETS_MANIFEST.md`

- Weather mapmode (province fill tint + F8 + toolbar)  
- Airfield chip + special_feature markers  
- Trade corridor convoy midpoint markers  
- OOB Yours/All intel toggle

## Pass 11 complete — see `PASS11_ASSETS_MANIFEST.md`

- Animated convoy travel on trade routes  
- Weather particle overlay (weather mapmode)  
- Airfield strip / hangar level variants  
- OOB nationality color chips

## Pass 12 complete — see `PASS12_ASSETS_MANIFEST.md`

- Fort bunker / heavy level variants  
- OOB org + strength mini-bars  
- Convoy interdiction attack flash FX  
- Per-province weather particle density

## Pass 13 complete — see `PASS13_ASSETS_MANIFEST.md`

- Port jetty / major level variants  
- Fort damaged state glyph  
- OOB readiness mini-bar  
- Weather legend click-to-filter

## Pass 14 complete — see `PASS14_ASSETS_MANIFEST.md`

- Damaged port glyph  
- OOB combat XP mini-bar  
- Weather particle filter sync  
- Mapmode preset row (Overview/Logistics/Theater/Climate/Build)

## Pass 15 complete — see `PASS15_ASSETS_MANIFEST.md`

- Airfield damaged glyph  
- OOB fuel mini-bar (naval/air)  
- Multi-mode preset stacks (Warpath / StormOps / BuildNet)  
- Minimap weather ground-state dots

## Pass 16 complete — see `PASS16_ASSETS_MANIFEST.md`

- Society preset (vitality + strain secondary tint)  
- SeaLanes convoy minimap pips  
- OOB ammo mini-bar (land)  
- Airfield repair/construction progress rings

## Pass 17 complete — see `PASS17_ASSETS_MANIFEST.md`

- Live airfield ring refresh on day tick  
- OOB ammo from province depot fill ratio  
- Multi-secondary tint stacks (HomeFront / EconPulse)  
- Minimap convoy pip click-to-focus

## Pass 18 complete — see `PASS18_ASSETS_MANIFEST.md`

- Munitions cargo profile + depot munitions stockpile  
- Airfield ring hover tooltips  
- Double-click convoy → route highlight  
- Secondary tint legend chips

## Pass 19 complete — see `PASS19_ASSETS_MANIFEST.md`

- Munitions desk chip (ship cargo + production open)  
- Airfield ring click → site inspector  
- Multi-route compare (Shift+click A/B)  
- Secondary tint chips click-to-toggle

## Pass 20 complete — see `PASS20_ASSETS_MANIFEST.md`

- Munitions factory line assignment  
- Enhanced site repair CTA + progress  
- Route compare summary card  
- Secondary tint intensity sliders

## Pass 21 complete — see `PASS21_ASSETS_MANIFEST.md`

- Munitions depot stockpile sparkline (24 samples)  
- Multi-site bulk repair CTA  
- Route compare save/load slots (3)  
- Secondary intensity presets Soft/Med/Hard/Max  

## Pass 22 complete — see `PASS22_ASSETS_MANIFEST.md`

- Per-depot munitions mapmode heatmap  
- Theater-wide repair queue chip  
- Persistent compare slots + intensities in save (`map_ui`)  
- Primary mapmode intensity link (Ix + memory)  

## Pass 23 complete — see `PASS23_ASSETS_MANIFEST.md`

- Dedicated munitions mapmode icons (32/64)  
- Ally/partner repair queue scope  
- Compare slot live risk recompute  
- Minimap munitions depot pips  

## Pass 24 complete — see `PASS24_ASSETS_MANIFEST.md`

- Formal alliance / guarantee treaties  
- Repair queue treaty vs partner scope  
- Player-only munitions minimap pips + desk toggle  
- Compare hop-risk sparklines  
- Munitions pip LOD density  

## Pass 25 complete — see `PASS25_ASSETS_MANIFEST.md`

- Alliance negotiation (propose / accept / decline / AI)  
- Path-correlated hop risk on compare card  
- Controller-aware munitions pips  
- Multi-day compare risk history sparkline  

## Pass 26 complete — see `PASS26_ASSETS_MANIFEST.md`

- Alliance counter-offers (terms + AI)  
- Occupation munitions tint + pip rings  
- Risk history CSV export  
- Triple-route A/B/C compare  

## Pass 27 complete — see `PASS27_ASSETS_MANIFEST.md`

- Free-form counter terms dialog  
- C/D in risk history + CSV export  
- Munitions occupation Focus chip  
- Four-route A/B/C/D pack  

## Pass 28 complete — see `PASS28_ASSETS_MANIFEST.md`

- Alliance counter templates (Soft/Standard/Hard/…)  
- Risk history A–D color legend  
- AmmoOcc / AmmoMine / AmmoPack presets  
- 4-route pack save/load slots  

## Pass 29 complete — see `PASS29_ASSETS_MANIFEST.md`

- User-saved alliance counter templates  
- Named pack slot labels  
- Munitions occupation filter in `map_ui` save  
- Auto pack from open supply routes  

## Pass 30 complete — see `PASS30_ASSETS_MANIFEST.md`

- Campaign-shared counter templates (◆)  
- Auto pack Mine (player-majority routes)  
- Pack slot pins on minimap  
- Pack share codes Share / Import  

## Pass 31 complete — see `PASS31_ASSETS_MANIFEST.md`

- EORP2 share with day-history samples  
- Route owner filter + card owner labels  
- Multi-pin A–D per pack on minimap  
- QR export via qrencode + popup  

## Pass 32 complete — see `PASS32_ASSETS_MANIFEST.md`

- In-engine QR (`RoutePackQR.gd`) with qrencode fallback  
- Fuzzy owner filter (contains / 1-edit)  
- Minimap pin polylines  
- Pack **Merge** (slots → best A–D)  

## Pass 33 complete — see `PASS33_ASSETS_MANIFEST.md`

- QR versions 11–20 + version info bits  
- Slot-weighted pack merge  
- Minimap polyline hit-test → load slot  
- **EORP3** deflate share codes (delta paths)  

## Pass 34 complete — see `PASS34_ASSETS_MANIFEST.md`

- Pack pin legend (minimap + card)  
- Slot reorder ◀/▶ (merge priority)  
- QR auto module size (~248 px)  
- Share **File** + Shift+Import from `.eorp`  

## Pass 35 complete — see `PASS35_ASSETS_MANIFEST.md`

- Free-slot drag-drop reorder  
- Multi-file pack library (`user://route_packs/`)  
- Share + QR preview toast  
- Legend click → load slot  

## Pass 36 complete — see `PASS36_ASSETS_MANIFEST.md`

- Library search / `#tag` filter  
- Pack tags sidecar + Tag L  
- Dual-pane **Compare L|R**  
- Minimap legend hover tooltips  

## Pass 37 complete — see `PASS37_ASSETS_MANIFEST.md`

- Tag cloud chips (toggle filter)  
- Sort: newest / name / size / tags  
- Pack notes editor + Tag+Note L  
- Pack pin hover tooltips  

## Pass 38 complete — see `PASS38_ASSETS_MANIFEST.md`

- ★ Favorites + sort  
- Library **Index** export (JSON/CSV)  
- Multi-tag AND chip polish  
- Pin risk color intensity  

## Pass 39 complete — see `PASS39_ASSETS_MANIFEST.md`

- **★ only** favorites filter  
- **Merge Idx** metadata union  
- Minimap risk lo→hi scale  
- **Bulk Tag** multi-select  

## Pass 40 complete — see `PASS40_ASSETS_MANIFEST.md`

- Merge **Repl** mode toggle  
- **Untag** bulk  
- Risk pin **histogram**  
- Folder **groups** + sort  

## Pass 41 complete — see `PASS41_ASSETS_MANIFEST.md`

- Nested group paths (`a/b/c`)  
- Drag packs onto group headers  
- **Heat** risk heatmap export  
- Search **History…**  

## Pass 42 complete — see `PASS42_ASSETS_MANIFEST.md`

- Group **tree** panel  
- Heatmap **MapManager** bounds  
- **Clr Hist**  
- **Group chips** synced to filter  

## Pass 43 complete — see `PASS43_ASSETS_MANIFEST.md`

- **Grp OR** multi-group filter  
- Tree multi-select + **Assign Sel**  
- Minimap risk heat overlay  
- History **★** pin favorites  

## Pass 44 complete — see `PASS44_ASSETS_MANIFEST.md`

- Compare card **Heat map** toggle  
- History **hist…** filter box  
- Live group chip counts  
- Tree drop multi-move  

## Pass 45 complete — see `PASS45_ASSETS_MANIFEST.md`

- Debounced library filter (~180ms)  
- Heat **intensity** slider  
- **Exp Hist** export  
- Group chip **right-click** assign  

## Pass 46 complete — see `PASS46_ASSETS_MANIFEST.md`

- Heat prefs persisted (`_map_prefs.json` + save)  
- **Imp Hist** (union / Shift replace)  
- Chip **context menu** (Filter / Assign / Copy / Clear)  
- Filter **Updating…** progress indicator  

## Pass 47 complete — see `PASS47_ASSETS_MANIFEST.md`

- Pack **legend opacity** slider (persisted)  
- Hist **file dialogs** (Ctrl/Alt export/import)  
- Filter **cancel** (click / Esc)  
- Chip menu **F/A/C/X** accelerators  

## Pass 48 complete — see `PASS48_ASSETS_MANIFEST.md`

- **Native** OS hist file dialogs  
- Heat **color ramp** picker (classic/inferno/viridis/mono)  
- Library **layout** presets (standard/compact/wide/left)  
- **Bulk** chip multi-select (Ctrl + Bulk Filt/Asg/Clr)  

## Pass 49 complete — see `PASS49_ASSETS_MANIFEST.md`

- Heat **custom cool/hot** colors + `custom` ramp  
- Layout **Ctrl+1..4** chords  
- **Tag OR** / **Bulk OR** filter modes  
- **Pin Foc** risk-cycle focus  

## Pass 50 complete — see `PASS50_ASSETS_MANIFEST.md`

- **Pin Foc** filtered by bulk tags/groups / Left packs  
- Heat **swatch** legend + hist ramp colors  
- Library **drag-resize** (persisted)  
- **Shift+Lib** multi-window  

## Pass 51 complete — see `PASS51_ASSETS_MANIFEST.md`

- Library **dock** (float/left/right/bottom + edge snap)  
- Pin focus **soft/tactical/keep** zoom  
- **Shared bulk** across library windows  
- Click heat **swatch** to cycle ramp  

## Pass 52 complete — see `PASS52_ASSETS_MANIFEST.md`

- Dock **Ctrl+Shift+arrows** chords  
- Pin focus **pulse rings** marker  
- **Bulk Exp** clipboard export  
- Compare card ramp **↻ / ↺**  

## Pass 53 complete — see `PASS53_ASSETS_MANIFEST.md`

- Pulse tint from **heat ramp**  
- **Bulk Imp** clipboard import  
- **Per-window** dock map  
- Compare card **ramp strip**  

## Pass 54 complete — see `PASS54_ASSETS_MANIFEST.md`

- **Pin ◀** focus history back  
- Library **opacity** slider (persisted)  
- Prefs **v7** docks map + opacity  

## Pass 55 complete — see `PASS55_ASSETS_MANIFEST.md`

- Pin history **persisted** to `_pin_focus_history.json`  
- **Per-window** library opacity  
- Bulk Imp/Exp **file dialogs** (Ctrl/Alt)  
- Pin pulse **SFX** (`pin_focus`)  

## Pass 56 complete — see `PASS56_ASSETS_MANIFEST.md`

- **Pin hist…** jump list + **Clr Pin**  
- **Link α** multi-window opacity  
- Bulk **JSON schema** export/import  
- **Pin SFX** mute toggle  

## Pass 57 complete — see `PASS57_ASSETS_MANIFEST.md`

- Pin hist **search** (`pin…`)  
- JSON **packs[]** → Left multi-select  
- Pin SFX **volume** (dB)  
- Library **themes** (classic/mono/amber/magenta)  

## Pass 58 complete — see `PASS58_ASSETS_MANIFEST.md`

- **Per-window** library theme  
- Pack select **scroll-into-view**  
- Pin SFX **preview** (▶)  
- Theme **presets file** exp/imp  

## Pass 59 complete — see `PASS59_ASSETS_MANIFEST.md`

- Theme **color pickers** (Chrome/Title) + **Save Theme** / Shift custom  
- Pack-select **highlight pulse** (click + bulk)  
- Pin SFX **audio bus** OptionButton  
- Theme share **EOTM1** clipboard exp/imp  

## Pass 60 complete — see `PASS60_ASSETS_MANIFEST.md`

- Typed **theme id** LineEdit + save-as  
- Theme / chrome **QR** (RoutePackQR)  
- Pulse **L cyan / R magenta** + multi **stagger**  
- **EOCS1** chrome snapshot (theme+dock+α)  

## Pass 61 complete — see `PASS61_ASSETS_MANIFEST.md`

- **QR↙** decode import (zbarimg) for EOTM1/EOCS1  
- EOCS1 **v2** layout + pin SFX prefs  
- Theme id **autocomplete** from presets  

## Pass 62 complete — see `PASS62_ASSETS_MANIFEST.md`

- Pure-GDScript **QR decoder** (engine-first, zbarimg fallback)  
- Pin SFX UI **live refresh** on chrome import  
- Theme AC **↑↓ Enter Esc**  
- **Batch** QR import (Shift+QR↙)  

## Pass 63 complete — see `PASS63_ASSETS_MANIFEST.md`

- QR **Reed-Solomon** correction + robust sampling  
- AC **hover ↔ keyboard** index sync  
- Theme/chrome **QR strip** export (Ctrl+Shift)  

## Pass 64 complete — see `PASS64_ASSETS_MANIFEST.md`

- Strip export **clipboard-safe** + **3×5 bitmap labels**  
- **RS stats toast** on noisy QR import  
- Mild **anisotropic/shear** QR sampling  

## Rotation safety (tiles)

All three seamless tiles use non-directional lighting → **rotation-safe** for future autotile edges.
Transition edge tile is a candidate straight-edge (plains|hills) for rotation economy.
