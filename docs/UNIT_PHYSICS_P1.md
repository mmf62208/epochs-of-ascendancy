# P1 air physics (read-only MVP)

Additive, read-only Breguet / store-drag / radius readout. Existing abstract combat
stats stay authoritative. Nothing in combat, production, missions, AI, save or
TimeManager reads this slice. The `base_range_km/550` switch is P2.

Presets live in `data/unit_physics/air_presets_p1.json` (not in `data/unit_templates/`).
Python mirror: `tools/map_generation/lib/air_physics_p1.py`.
GDScript: `scripts/units/UnitPhysics.gd` + `scripts/units/DesignCalculator.gd`.
Designer hook: Domain = Air → **Physics readout (P1)**. Killswitch `EOA_AIR_PHYSICS_P1=0`.

## Model (named consts)

| Const | Value | Notes |
|---|---|---|
| `HEX_KM` | 24.1 | 1 hex = 15 mi flat-to-flat |
| `MI_TO_KM` | 1.609344 | |
| `NMI_TO_KM` | 1.852 | |
| `K_BREGUET_DEFAULT` | 0.54 | props and jets; each preset fits only `k_preset` |
| `D_PROP` / `D_JET` | 0.19 / 0.25 | store-drag coefficients (central fitted; not pushed +2%) |
| `STORE_CLASS_EXPONENT` | **1.0 (linear)** | spec §4.3 Me 262 1,000 kg needs ×0.50. F2 text says ^(2/3) → ×0.603. Open for Ship/Mike. |
| `WE_REF_PROP_KG` | 4010 | Typhoon Ib empty [R53] = frame-class 1.0 |
| `WE_REF_JET_KG` | 3795 | Me 262 A-1a empty = frame-class 1.0 |
| reserve | 0.10 × standard internal fuel | unused for range; ferry F-16 fit uses no reserve |
| avgas | 6 lb/US gal, 7.2 lb/imp gal, 0.72 kg/L | ESTIMATE |
| J2 | 0.83 kg/L | ESTIMATE |
| CG aft-tank | −15% agility while aft tank > 40 US gal | 40 gal sourced [T17][T18]; 15% is DESIGN PICK |
| RATO | stub only | `allowed=false`, deferred P2. Never legalises over-MTOW in P1. |

Role fractions f: escort/intercept 0.40; strike heavy 0.35; strike light/internal bay 0.45; patrol 0.25; ferry 1.00; missile 1.00.

Breguet (payload carried the whole trip):

- prop: `R_mi = k × 375 × (η / c) × (L/D)_eff × ln(W_i / W_f)`, c in lb/hp/hr
- jet: `R_nmi = k × (V / c) × (L/D)_eff × ln(W_i / W_f)`, V in kt, c in lb/lbf/hr
- `W_f = W_i − usable_fuel`; usable = loaded fuel − reserve

Range hexes = round-half-even(km / 24.1). Radius = floor(f × R_km / 24.1).
Top speed with stores: `V_max × LD_factor^(1/2)` (jet) or `^(1/3)` (prop).
Climb/agility: `(W_clean / W_loaded) × LD_factor`.
Takeoff (ESTIMATE, only where a base run is sourced): `base_run × (W_i / W_ref)²`.
Two-leg: harmonic mean of loaded and clean range, then × f.

Calibration: fit only `k_preset` so `R_preset / R_sourced ∈ [1.010, 1.020]`. Aim 1.015; Me 262 is exactly 1.020 (1,071 km). Soft warning (not a fail) if `k_preset` is outside [0.35, 0.75].

## Sources

| ID | URL |
|---|---|
| S2 | https://en.wikipedia.org/wiki/Messerschmitt_Bf_109_variants |
| S3 | https://www.dingeraviation.net/spitfire/overview.htm |
| R9 | https://www.warbirdsresourcegroup.org/AARG/spitfire.html |
| R8 | https://www.wwiiaircraftperformance.com/wwiiaircraftperformance.org/spitfireperformance.com/MK1/Spitfire%20Mk%20I%20K.9793%20Trials%20Report.html |
| S7 | https://en.wikipedia.org/wiki/Focke-Wulf_Fw_190 |
| S8 | https://en.wikipedia.org/wiki/Mitsubishi_A6M_Zero |
| S10 | https://www.nationalmuseum.af.mil/Visit/Museum-Exhibits/Fact-Sheets/Display/Article/196270/boeing-b-17g-flying-fortress/ |
| S11 | https://www.486th.org/Aircraft/B17/B17Gspecs.htm |
| S13 | https://www.nationalmuseum.af.mil/Visit/Museum-Exhibits/Fact-Sheets/Display/Article/196263/north-american-p-51d-mustang/ |
| S15 | https://www.nationalmuseum.af.mil/Visit/Museum-Exhibits/Fact-Sheets/Display/Article/196266/messerschmitt-me-262a-schwalbe/ |
| S17 | https://www.nationalmuseum.af.mil/Visit/Museum-Exhibits/Fact-Sheets/Display/Article/196118/north-american-f-86a-sabre/ |
| S23 / R12 | https://www.af.mil/About-Us/Fact-Sheets/Display/Article/104505/f-16-fighting-falcon/ |
| S28 / R11 | https://www.af.mil/About-Us/Fact-Sheets/Display/Article/478441/f-35a-lightning-ii-conventional-takeoff-and-landing-variant/ |
| R10 | https://www.f35.com/content/dam/lockheed-martin/aero/f35/documents/F-35A%20Product%20Card.pdf |
| R3 / R7 | https://archive.org/stream/nasa_techdoc_19850023776/19850023776_djvu.txt |
| R4 / R50 | https://www.mustangsmustangs.com/p-51/specifications/ |
| R5 | https://aopa.org/news-and-media/all-news/2007/august/01/north-american-aviation-p-51d-mustang |
| R6 | https://www.wwiiaircraftperformance.org/Aircraft_Engines_of_the_World_Packard_Merlin.pdf |
| R22 | https://americancombatplanes.com/p51_2.html |
| R25 | http://www.americancombatplanes.com/p47_2.html |
| R51 | https://en.wikipedia.org/wiki/Republic_P-47_Thunderbolt |
| R53 | https://en.wikipedia.org/wiki/Hawker_Typhoon |
| R54 | https://stephentaylorhistorian.com/wp-content/uploads/2020/04/typhoon-1a1b.pdf |
| R58 / T2 | https://en.wikipedia.org/wiki/Messerschmitt_Me_262 |
| R59 / T3 | https://www.warbirdsresourcegroup.org/LRG/me262-specifications.html |
| T4 | http://zenoswarbirdvideos.com/Images/Me262/ME262PILOTDEBRIEF.pdf (figures from search text; PDF not re-fetched) |
| T17 | https://aircorpslibrary.com/operation-of-p-51-series-airplanes-with-85-gallon-fuselage-fuel-tank/ |
| T18 | https://data.ntsb.gov/Docket/Document/docBLOB?FileExtension=.PDF&FileName=P51D+Normal+Operating+Instructions-Master.PDF&ID=40206631 |
| P1-1 (candidate) | https://www.nationalmuseum.af.mil/Visit/Museum-Exhibits/Fact-Sheets/Display/Article/858869/republic-p-47/ |
| P1-2 | https://www.worldwar2.ro/arr/bf109e.htm (Bf 109 E empty 2,125 kg / loaded 2,665 kg / 560 km/h / range 660 km max) |
| P1-4 | https://aergistal.github.io/il2/planes/bf109e7.html (E-7 400 L / 2,893 kg max T/O) |
| P1-5 | Wikipedia Spitfire Mk I max 6,528 lb |
| P1-6 | https://www.aircraftinformation.info/JB_AIF/usaf_fighters/p86_2.html (F-86A-5 empty 10,093 lb / 435 gal) |
| P1-7 | https://www.163atkw.ang.af.mil/About-Us/Fact-Sheets/Display/Article/452910/north-american-f-86-sabre-day-fighter-a-e-and-f-models/ (F-86A cruise 540 mph) |

Every input not in the spec table is either one of those IDs or labelled ESTIMATE / DESIGN PICK in the JSON `labels` map. Nothing is invented as "sourced".

## Calibration report

```
P1 air-physics calibration (k_preset only; target 1.015, Me 262 = 1.020)
id                sourced_km  result_km  ratio   k_preset  band  src
------------------------------------------------------------------------------
a6m2_zero          1870.000   1898.050 1.0150  0.78327  OK  S8
b17g               2977.286   3021.946 1.0150  0.99136  OK  S10
bf109e              660.000    669.900 1.0150  0.50852  OK  S2
f16c               3222.480   3270.817 1.0150  0.61877  OK  S23 / R12
f35a               2222.400   2255.736 1.0150  0.48768  OK  S28 / R10
f86a               1931.213   1960.181 1.0150  0.85894  OK  S17
fw190a             1000.000   1015.000 1.0150  0.85430  OK  S7
me262_a1a          1050.000   1071.000 1.0200  0.63483  OK  R59 / T3
p47d               1657.624   1682.489 1.0150  0.88689  OK  P1-1
p51d               1609.344   1633.484 1.0150  0.63208  OK  S13
spitfire_mk1        635.691    645.226 1.0150  0.49910  OK  S3 / R9
typhoon_ib         1110.447   1127.104 1.0150  1.11202  OK  R53

Variant pairs (k cancels; |error| ≤ 5%)
  P-51 B/C→D  model -3.21%  real -2.12%  error -1.12%
  P-51 tank 180→269  model +49.43%  real +56.29%  error -4.39%
  Typhoon +2×45 gal  model +58.93%  real +57.97%  error +0.61%
```

`k_preset` outside [0.35, 0.75] is a **soft warning** on Typhoon, B-17G, P-47D, F-86A, Fw 190, A6M2 (small fuel fraction → k has to carry the historical range). Only `k` was fitted; aero inputs that are ESTIMATE were not re-tuned to hide this.

## Open for Ship/Mike

1. **`STORE_CLASS_EXPONENT = 1.0` vs F2's 2/3.** Linear is required for the Me 262 1,000 kg ×0.50 case. ^(2/3) would give ×0.603 and break §4.3.
2. **P-47D candidate source** 1,030 mi NMUSAF [P1-1]; fuel config unstated. D-25 370 gal mixed with D-40 empty/gross. Razorback 1,100 mi *with* aux tanks was not used.
3. **F-16C** has no sourced internal combat range. Ferry 1,740 nmi / 2 tanks calibrated (no reserve, no +10% ferry bonus). Combat range is DERIVED.
4. **F-35A radius 42 vs worked-example 52.** 52 stacks efficient-turbofan ×0.8 and uses a 669 nmi radius. Sourced 1,200 nmi already includes the real engine; ×0.8 is not stacked. Light-strike `floor(0.45 × 93.60) = 42`.
5. **Me 262 1,071 vs NMUSAF S15 1,046 km (+2.4%).** Calibrated on R59 1,050 km ×1.02 per spec §4.2.
6. **Template name/variant mismatches — flagged, not edited:**
   - `typhoon_fighter` name is "Eurofighter Typhoon" with `era: ww2`
   - `f86_sabre` is the F-86F; preset is F-86A
   - `a6m_zero_fighter` is the A6M5; preset is A6M2
   - `fw190a_fighter` is the A-8; S7 range band's variant is unclear
   - `f16c_fighting_falcon` era is "interwar"
7. **B-17G empty-weight disagreement:** S11 31,780 lb vs common Boeing/Wikipedia 36,135 lb. S11 used so the 1,850 mi / 1,700 gal pair stays together. S10 does not state bomb-load basis. Tokyo tanks 3,070 mi not used.
8. **Fw 190 fuel:** Wikipedia A-8 lists 639 L; mains-only 524 L also appears. 639 L used and noted.
9. **T4 takeoff** figures taken from search text; the Hans Fey PDF was not re-fetched.

## Out of scope (P2+)

Replacing `base_range_km/550`; hourly mission step; fuel/stores/ammo pools; tankers; ships; space Δv; RATO execution; DesignManager cache; physics blocks in templates/modules; AI or production use; efficient-turbofan tech; tank-option unlocks.
