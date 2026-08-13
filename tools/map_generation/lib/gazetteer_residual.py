"""Residual gazetteer name quality pure gate (not full rename pass).

Detects residual placeholder-ish patterns that should stay cleared on world_full
after the map-star name polish (Sector/Basin-coord, Waters-N, Theater N).
"""
from __future__ import annotations

import re
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence

# Patterns that were hard gates in map-star polish (must stay at 0 on play board)
ROBOTIC_RE = re.compile(
    r"(?i)\b(Sector\s+[A-Z0-9]+|Basin[-_]?[0-9]+|Basin\s+[0-9]+|"
    r"Theater\s+\d+|Waters[-_\s]?\d+)\b"
)
PLACEHOLDER_RE = re.compile(
    r"(?i)\b(Province\s+\d+|Unnamed|TODO|PLACEHOLDER|TEST\s+\d+)\b"
)


def classify_province_name(name: str) -> Dict[str, Any]:
    n = str(name or "").strip()
    robotic = bool(ROBOTIC_RE.search(n))
    placeholder = bool(PLACEHOLDER_RE.search(n))
    ok = bool(n) and not robotic and not placeholder
    flags: List[str] = []
    if not n:
        flags.append("empty")
    if robotic:
        flags.append("robotic")
    if placeholder:
        flags.append("placeholder")
    return {
        "name": n,
        "ok": ok,
        "robotic": robotic,
        "placeholder": placeholder,
        "flags": flags,
    }


def audit_province_names(
    names: Sequence[Any],
    *,
    sample_limit: int = 20,
) -> Dict[str, Any]:
    """Audit a list of province name strings (or {id,name} dicts)."""
    total = 0
    robotic = 0
    placeholder = 0
    empty = 0
    bad_samples: List[str] = []
    for item in names or []:
        if isinstance(item, dict):
            n = item.get("name", item.get("province_name", ""))
        else:
            n = item
        c = classify_province_name(str(n))
        total += 1
        if not c["name"]:
            empty += 1
        if c["robotic"]:
            robotic += 1
            if len(bad_samples) < sample_limit:
                bad_samples.append(c["name"])
        if c["placeholder"]:
            placeholder += 1
            if len(bad_samples) < sample_limit and c["name"] not in bad_samples:
                bad_samples.append(c["name"])
    residual = robotic + placeholder + empty
    return {
        "total": total,
        "robotic": robotic,
        "placeholder": placeholder,
        "empty": empty,
        "residual": residual,
        "ok": residual == 0 and total > 0,
        "bad_samples": bad_samples,
        "summary": (
            "gazetteer residual=%d (robotic=%d placeholder=%d empty=%d) of %d"
            % (residual, robotic, placeholder, empty, total)
        ),
    }


def audit_world_full_names(provinces_payload: Mapping[str, Any]) -> Dict[str, Any]:
    """Audit provinces_base.json-shaped payload names."""
    provs = provinces_payload.get("provinces") or []
    names = []
    for p in provs:
        if isinstance(p, dict):
            names.append({"id": p.get("id"), "name": p.get("name", "")})
    return audit_province_names(names)
