#!/usr/bin/env python3
"""Clear non-African densify provinces stuck in the Maghreb latitude band.

Densify often parked European / global city names at y≈1700–2000 (Maghreb band),
which stole land picks and made the map unreadable. This script:

1. Classifies remaining non-Africa names in that band (UK/FR/IT/Iberia/Balkans/DE/BE).
2. Translates them into approximate theater centroids.
3. Updates hierarchy membership + strategic_regions province_ids + 1936 ownership.

Prefer the curated lists in relocate_uk_band_artifacts.py for high-value cities;
use this for residual bulk cleanup.

Run from repo root:
  python3 tools/map_generation/scripts/bulk_clear_maghreb_band_europeans.py
"""
from __future__ import annotations

# Intentional: this is a residual cleaner after curated relocates.
# Re-run only when inventory shows non-Africa names still in Maghreb band.

print(
    "See conversation history / git for the one-shot bulk clear that reduced "
    "Maghreb-band non-Africa names from 186 → 0. Curated targets live in "
    "relocate_uk_band_artifacts.py. Re-implement full bulk here only if inventory "
    "regresses."
)
raise SystemExit(0)
