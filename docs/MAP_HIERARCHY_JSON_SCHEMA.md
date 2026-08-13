# Map Hierarchy JSON Schema (EOA)

Machine-oriented companion to `docs/MAP_HIERARCHY_SYSTEM_DESIGN.md`.

## Files per data dir (`data/provinces_*`)

| File | Required | Role |
|------|----------|------|
| `province_states.json` | yes | Tier-2 states |
| `strategic_regions.json` | yes | Tier-3 regions (scaffold fallback OK) |
| `super_regions.json` | yes | Tier-4 theaters |
| `hierarchy_scaffold.json` | yes | O(1) province→tier bindings |
| `hierarchy_membership_{year}.json` | optional | Era overrides for membership only |
| `province_ownership_{year}.json` | yes for eras | Owner tags (not hierarchy) |

## `province_states.json`

```json
{
  "version": 3,
  "source": "string",
  "naming": "state_name_gazetteer | gis_admin | sample",
  "states": [
    {
      "id": 1,
      "name": "Flanders",
      "province_ids": [700001, 700002],
      "province_n": 2,
      "capital_province_id": 700001,
      "region_id": 3,
      "region_hint": "Low Countries",
      "theater": "europe_core",
      "owner_hint": "BEL",
      "tags": ["historical_province"]
    }
  ]
}
```

**Rules**
- `name` must not match placeholder patterns (`Area N`, `State N`, `TAG · Region · Area`).
- `province_ids` length ideally **5–20** (3–30 hard); sparse may be higher.
- `owner_hint` is seed metadata only — live owner is province ownership.

## `strategic_regions.json`

```json
{
  "version": 4,
  "source": "string",
  "regions": [
    {
      "id": 3,
      "name": "Low Countries",
      "province_ids": [700001],
      "state_ids": [1, 2],
      "super_region_id": 1,
      "theater": "europe_core",
      "notes": ""
    }
  ]
}
```

## `super_regions.json`

```json
{
  "version": 1,
  "super_regions": [
    {
      "id": 1,
      "name": "Europe",
      "region_ids": [1, 2, 3],
      "theaters": ["europe_core"],
      "province_n": 0
    }
  ]
}
```

## `hierarchy_scaffold.json`

```json
{
  "version": 2,
  "four_tier": true,
  "province_to_state": {"700001": 1},
  "province_to_region": {"700001": 3},
  "province_to_super_region": {"700001": 1},
  "state_n": 196,
  "region_n": 10,
  "super_region_n": 1,
  "land_n": 1840
}
```

Every land province key should appear in all three maps.

## `hierarchy_membership_{year}.json` (primary eras = FULL)

**Primary eras (always `mode: full`, most fleshed-out):** `1910`, `1918`, `1936`, `2026`  
**Secondary (optional):** `1945`  
**Policy:** seed on scenario load only; never reapply on year tick.  
**Index:** `membership_era_index.json`  
**Builder:** `tools/map_generation/lib/membership_era_product.py`

```json
{
  "version": 1,
  "era_year": 1936,
  "mode": "full",
  "seed_only": true,
  "primary": true,
  "province_to_state": {"700001": 193600001},
  "province_to_region": {"700001": 3},
  "province_to_super_region": {"700001": 1},
  "states": [{"id": 193600001, "name": "Flanders", "province_ids": [700001], "region_id": 3}],
  "state_n": 1,
  "province_n": 1
}
```

Primary snapshots must include **complete** `province_to_state` / `province_to_region` / `province_to_super_region` maps (not sparse deltas).

## Runtime API (`ScenarioLoader`)

| Method | Returns |
|--------|---------|
| `get_province_state_id(pid)` | int |
| `get_province_region_id(pid)` | int |
| `get_province_super_region_id(pid)` | int |
| `get_state_name(sid)` | String |
| `get_strategic_region_name(rid)` | String |
| `get_super_region_name(srid)` | String |
| `get_hierarchy_for_province(pid)` | `{province_id, state_id, state_name, region_id, region_name, super_region_id, super_region_name, empty}` |

## Integrity gates (pure)

- State names: `state_name_gazetteer.assert_names_shippable`
- State size: majority of states in 5–20 province band
- Four-tier: `province_to_super_region` non-empty; loader prints `hierarchy_query … four_tier=1`
- No ID collision across parallel pilot namespaces
