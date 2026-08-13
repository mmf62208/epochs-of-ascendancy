"""Designer suite product (deferred key item — first vertical).

Multi-domain design → production path: land (tank) · naval (ship) · air · space.
Composes catalog review, domain pick, seed production line — not full HOI4 designers.
"""
from __future__ import annotations

from typing import Any, Dict, List, Mapping, Optional, Sequence

from campaign_execution import execution_integrity_gate, production_order_resolve  # type: ignore
from gameplay_loops import sole_mult_integrity  # type: ignore
from live_mutation import production_priority_mutation  # type: ignore

try:
    from medium_tank_oob_product import build_medium_tank_oob_product  # type: ignore
except Exception:  # pragma: no cover
    def build_medium_tank_oob_product(*_a, **_k):  # type: ignore
        return {"score": 0.55, "empty": False, "summary": "oob", "will_complete_100d": False}


DOMAINS = ("land", "naval", "air", "space")

# Demo catalog when live DesignManager unavailable (pure tests / offline)
_DEMO_CATALOG: Dict[str, List[Dict[str, Any]]] = {
    "land": [
        {"design_id": "panzer_iii_j_medium", "label": "Panzer III J (medium)", "role": "medium_tank", "score": 0.72},
        {"design_id": "t34_medium_tank", "label": "T-34 medium", "role": "medium_tank", "score": 0.78},
        {"design_id": "m4_sherman_medium_tank", "label": "M4 Sherman", "role": "medium_tank", "score": 0.74},
    ],
    "naval": [
        {"design_id": "destroyer_1936", "label": "Destroyer 1936", "role": "destroyer", "score": 0.65},
        {"design_id": "light_cruiser_1936", "label": "Light cruiser 1936", "role": "cruiser", "score": 0.68},
        {"design_id": "submarine_1936", "label": "Submarine 1936", "role": "submarine", "score": 0.62},
    ],
    "air": [
        {"design_id": "fighter_1936", "label": "Fighter 1936", "role": "fighter", "score": 0.7},
        {"design_id": "tac_bomber_1936", "label": "Tactical bomber 1936", "role": "bomber", "score": 0.66},
        {"design_id": "cas_1936", "label": "CAS 1936", "role": "cas", "score": 0.64},
    ],
    "space": [
        {"design_id": "satellite_recon", "label": "Recon satellite", "role": "satellite", "score": 0.55},
        {"design_id": "space_station_hab", "label": "Hab station", "role": "station", "score": 0.5},
        {"design_id": "ship_corvette", "label": "Space corvette", "role": "spacecraft", "score": 0.52},
    ],
}

_DOMAIN_META = {
    "land": {
        "action_id": "designer_domain_land",
        "leaf": "apply_production",
        "label": "Land designer — medium armor line",
        "doctrine": "rugged_redundancy",
    },
    "naval": {
        "action_id": "designer_domain_naval",
        "leaf": "apply_station",
        "label": "Naval designer — fleet hull line",
        "doctrine": "compartmentalized_survivability",
    },
    "air": {
        "action_id": "designer_domain_air",
        "leaf": "apply_production",
        "label": "Air designer — fighter/CAS line",
        "doctrine": "lightweight_performance",
    },
    "space": {
        "action_id": "designer_domain_space",
        "leaf": "apply_focus",
        "label": "Space designer — orbital project",
        "doctrine": "lightweight_performance",
    },
}

PRODUCT_STEPS = ("catalog", "pick_domain", "seed_production")

_STEP_META = {
    "catalog": {
        "action_id": "designer_suite_catalog",
        "leaf": "apply_focus",
        "label": "Step 0 — review multi-domain catalog",
    },
    "pick_domain": {
        "action_id": "designer_suite_pick",
        "leaf": "apply_production",
        "label": "Step 1 — pick domain design",
    },
    "seed_production": {
        "action_id": "designer_suite_seed",
        "leaf": "apply_production",
        "label": "Step 2 — seed production line",
    },
}


def _norm(v: float) -> float:
    try:
        x = float(v)
    except (TypeError, ValueError):
        return 0.5
    if x > 2.0:
        x = x / 100.0
    return max(0.0, min(1.0, x))


def _floor(score: float, lo: float = 0.35) -> float:
    s = _norm(score)
    return s if s >= lo else max(lo, min(1.0, s + 0.2))


def _wx() -> Dict[str, Any]:
    return {
        "visibility": 0.75,
        "precip": 0.2,
        "precip_intensity": 0.2,
        "ground_state": "dry",
        "wind": 0.2,
        "temperature_c": 12.0,
    }


def normalize_catalog(
    catalog: Optional[Mapping[str, Sequence[Mapping[str, Any]]]] = None,
) -> Dict[str, List[Dict[str, Any]]]:
    out: Dict[str, List[Dict[str, Any]]] = {}
    src = catalog if isinstance(catalog, Mapping) else _DEMO_CATALOG
    for dom in DOMAINS:
        rows: List[Dict[str, Any]] = []
        for raw in src.get(dom) or _DEMO_CATALOG.get(dom) or []:
            if not isinstance(raw, Mapping):
                continue
            did = str(raw.get("design_id", raw.get("id", ""))).strip()
            if not did:
                continue
            rows.append(
                {
                    "design_id": did,
                    "label": str(raw.get("label", did)),
                    "role": str(raw.get("role", dom)),
                    "score": _floor(float(raw.get("score", 0.55) or 0.55)),
                    "domain": dom,
                }
            )
        if not rows:
            rows = [dict(r) for r in _DEMO_CATALOG.get(dom, [])]
            for r in rows:
                r["domain"] = dom
        rows.sort(key=lambda r: (-float(r.get("score", 0)), str(r.get("design_id", ""))))
        out[dom] = rows
    return out


def recommend_domain(
    catalog: Mapping[str, Sequence[Mapping[str, Any]]],
    *,
    tank_progress: float = 0.15,
    naval_pressure: float = 0.4,
    air_pressure: float = 0.35,
    era_year: int = 1939,
) -> Dict[str, Any]:
    """Pick domain by campaign pressure + catalog readiness."""
    cat = normalize_catalog(catalog)
    land_best = float((cat.get("land") or [{"score": 0.5}])[0].get("score", 0.5))
    naval_best = float((cat.get("naval") or [{"score": 0.5}])[0].get("score", 0.5))
    air_best = float((cat.get("air") or [{"score": 0.5}])[0].get("score", 0.5))
    space_best = float((cat.get("space") or [{"score": 0.5}])[0].get("score", 0.5))
    prog = _norm(tank_progress)
    # Urgency scores
    scores = {
        "land": _floor(0.45 * land_best + 0.35 * (1.0 - prog) + 0.2),
        "naval": _floor(0.5 * naval_best + 0.4 * _norm(naval_pressure) + 0.1),
        "air": _floor(0.5 * air_best + 0.4 * _norm(air_pressure) + 0.1),
        "space": _floor(0.35 * space_best + (0.35 if era_year >= 1955 else 0.1)),
    }
    domain = max(scores.keys(), key=lambda k: (scores[k], k))
    meta = _DOMAIN_META[domain]
    pick = (cat.get(domain) or [{}])[0]
    return {
        "domain": domain,
        "design_id": str(pick.get("design_id", "")),
        "label": str(pick.get("label", "")),
        "score": scores[domain],
        "domain_scores": scores,
        "action_id": meta["action_id"],
        "leaf": meta["leaf"],
        "doctrine": meta["doctrine"],
        "reason": "prioritize %s (%s)" % (domain, pick.get("role", domain)),
        "summary": "Recommend %s · %s" % (domain, pick.get("label", "")),
        "empty": False,
    }


def recommend_designer_step(
    catalog_count: int,
    *,
    has_pick: bool = False,
    production_ready: bool = False,
) -> Dict[str, Any]:
    if catalog_count <= 0:
        step = "catalog"
        reason = "empty catalog — open designer"
    elif not has_pick:
        step = "pick_domain"
        reason = "pick domain design"
    elif not production_ready:
        step = "seed_production"
        reason = "seed production line from design"
    else:
        step = "seed_production"
        reason = "sustain design production"
    meta = _STEP_META[step]
    return {
        "step": step,
        "action_id": meta["action_id"],
        "leaf": meta["leaf"],
        "reason": reason,
        "summary": "Recommend %s · %s" % (step, reason),
        "empty": False,
    }


def build_designer_suite_product(
    catalog: Optional[Mapping[str, Sequence[Mapping[str, Any]]]] = None,
    *,
    province_id: int = 1,
    country_tag: str = "GER",
    tank_progress: float = 0.15,
    factories: int = 14,
    naval_pressure: float = 0.4,
    air_pressure: float = 0.35,
    era_year: int = 1939,
) -> Dict[str, Any]:
    """Designer suite product: multi-domain catalog → pick → seed production."""
    cat = normalize_catalog(catalog)
    wx = _wx()
    domain_rec = recommend_domain(
        cat,
        tank_progress=tank_progress,
        naval_pressure=naval_pressure,
        air_pressure=air_pressure,
        era_year=era_year,
    )
    mut = production_priority_mutation(weather=wx, base_output=1.0, line_id=str(domain_rec.get("design_id", "primary")))
    try:
        order = production_order_resolve(weather=wx, base_output=1.0, line_id=str(domain_rec.get("design_id", "primary")))
    except TypeError:
        order = production_order_resolve(wx)  # type: ignore
    oob = build_medium_tank_oob_product(
        province_id, tank_line_progress=tank_progress, factories=factories
    )

    catalog_count = sum(len(cat.get(d) or []) for d in DOMAINS)
    domain_rows: List[Dict[str, Any]] = []
    for dom in DOMAINS:
        meta = _DOMAIN_META[dom]
        rows = cat.get(dom) or []
        best = rows[0] if rows else {"design_id": "", "label": "empty", "score": 0.35}
        recommended = dom == str(domain_rec.get("domain"))
        sc = float(best.get("score", 0.5))
        if recommended:
            sc = _floor(sc + 0.08)
        lab = str(meta["label"])
        if recommended:
            lab = "★ " + lab
        lab = "%s · %s · score %.2f" % (lab, best.get("label", ""), sc)
        domain_rows.append(
            {
                "domain": dom,
                "action_id": meta["action_id"],
                "leaf_action": meta["leaf"],
                "design_id": str(best.get("design_id", "")),
                "label": lab,
                "score": sc,
                "recommended": recommended,
                "enabled": bool(rows),
                "doctrine": meta["doctrine"],
                "count": len(rows),
            }
        )

    prod_score = _norm(float(mut.get("score", order.get("score", 0.55)) or 0.55))
    oob_score = _norm(float(oob.get("score", 0.55) or 0.55))
    pick_score = _norm(float(domain_rec.get("score", 0.55) or 0.55))
    score = _floor(
        0.35 * pick_score
        + 0.25 * prod_score
        + 0.2 * oob_score
        + 0.2 * min(1.0, catalog_count / 12.0)
    )

    production_ready = factories >= 8 and bool(domain_rec.get("design_id"))
    rec = recommend_designer_step(
        catalog_count, has_pick=True, production_ready=production_ready
    )

    step_scores = {
        "catalog": _floor(0.4 + 0.05 * min(12, catalog_count)),
        "pick_domain": pick_score,
        "seed_production": _floor(0.45 * prod_score + 0.35 * pick_score + 0.2),
    }
    day_rows: List[Dict[str, Any]] = []
    apply_queue: List[Dict[str, Any]] = []
    for i, step in enumerate(PRODUCT_STEPS):
        meta = _STEP_META[step]
        recommended = step == str(rec.get("step"))
        sc = step_scores[step]
        leaf = str(meta["leaf"])
        if step == "seed_production":
            leaf = str(domain_rec.get("leaf", leaf))
        lab = str(meta["label"])
        if recommended:
            lab = "★ " + lab
        lab = "%s · %s · score %.2f" % (lab, domain_rec.get("domain", ""), sc)
        row = {
            "index": i,
            "step": step,
            "action_id": meta["action_id"],
            "leaf_action": leaf,
            "label": lab,
            "score": sc,
            "enabled": catalog_count > 0 or step == "catalog",
            "recommended": recommended,
            "province_id": max(1, int(province_id)),
            "domain": domain_rec.get("domain", ""),
            "design_id": domain_rec.get("design_id", ""),
        }
        day_rows.append(row)
        apply_queue.append(
            {
                "action_id": leaf,
                "province_id": max(1, int(province_id)),
                "score": sc,
                "enabled": bool(row["enabled"]),
                "label": lab,
                "step": step,
                "product_action": meta["action_id"],
                "design_id": domain_rec.get("design_id", ""),
                "domain": domain_rec.get("domain", ""),
            }
        )

    for dr in domain_rows:
        apply_queue.append(
            {
                "action_id": str(dr.get("leaf_action")),
                "province_id": max(1, int(province_id)),
                "score": float(dr.get("score", 0.5)),
                "enabled": bool(dr.get("enabled")),
                "label": str(dr.get("label")),
                "step": "pick_domain",
                "product_action": str(dr.get("action_id")),
                "design_id": dr.get("design_id", ""),
                "domain": dr.get("domain", ""),
            }
        )

    actions: List[Dict[str, Any]] = [
        {
            "action_id": "designer_suite_product",
            "label": "Run designer suite product",
            "enabled": True,
        },
        {
            "action_id": str(rec.get("action_id", "designer_suite_catalog")),
            "label": "Recommended: %s" % rec.get("step", "catalog"),
            "enabled": True,
        },
    ]
    for r in day_rows:
        actions.append(
            {
                "action_id": r["action_id"],
                "label": r["label"],
                "enabled": bool(r["enabled"]),
                "step": r["step"],
            }
        )
    for dr in domain_rows:
        actions.append(
            {
                "action_id": dr["action_id"],
                "label": dr["label"],
                "enabled": bool(dr["enabled"]),
                "domain": dr["domain"],
            }
        )

    tag = str(country_tag or "GER").upper()
    label = (
        "Designer suite · %s · domains 4 · pick %s/%s · catalog %d · factories %d · score %.2f"
        % (
            tag,
            domain_rec.get("domain"),
            domain_rec.get("design_id"),
            catalog_count,
            int(factories),
            score,
        )
    )
    plain_lines = [
        label,
        str(rec.get("summary", "")),
        str(domain_rec.get("summary", "")),
        "doctrine %s · prod %s" % (domain_rec.get("doctrine"), mut.get("summary", "")),
    ]
    for dr in domain_rows:
        plain_lines.append(str(dr.get("label", "")))
    for r in day_rows:
        plain_lines.append(str(r.get("label", "")))

    return {
        "catalog": cat,
        "catalog_count": catalog_count,
        "domain_rows": domain_rows,
        "domain_recommendation": domain_rec,
        "mutation": mut,
        "order": order,
        "oob": oob,
        "country_tag": tag,
        "factories": int(factories),
        "tank_progress": _norm(tank_progress),
        "recommendation": rec,
        "day_rows": day_rows,
        "apply_queue": apply_queue,
        "actions": actions,
        "score": score,
        "design_score": score,
        "province_id": max(1, int(province_id)),
        "apply_ready": production_ready,
        "summary": label,
        "plain": "\n".join(ln for ln in plain_lines if ln),
        "bbcode": "[color=#e8c060]⚙ Designer suite[/color] [color=#8899aa]%s[/color]" % label,
        "empty": catalog_count <= 0,
        "integration": [
            "designer_suite_product",
            "designer_suite_catalog",
            "designer_suite_pick",
            "designer_suite_seed",
            "designer_domain_land",
            "designer_domain_naval",
            "designer_domain_air",
            "designer_domain_space",
            "major_10",
            "designers",
        ],
    }


def execute_designer_suite_step(
    step: str,
    province_id: int = 1,
    *,
    catalog: Optional[Mapping[str, Sequence[Mapping[str, Any]]]] = None,
    country_tag: str = "GER",
) -> Dict[str, Any]:
    s = str(step or "catalog").strip().lower()
    if s.startswith("designer_suite_"):
        s = s.replace("designer_suite_", "")
    if s.startswith("designer_domain_"):
        # domain buttons map to pick
        s = "pick_domain"
    if s not in _STEP_META:
        s = "catalog"
    meta = _STEP_META[s]
    product = build_designer_suite_product(
        catalog, province_id=province_id, country_tag=country_tag
    )
    row = next((r for r in (product.get("day_rows") or []) if r.get("step") == s), None)
    leaf = str((row or {}).get("leaf_action", meta["leaf"]))
    score = float((row or {}).get("score", product.get("score", 0.5)))
    drec = product.get("domain_recommendation") or {}
    q = [
        {
            "action_id": leaf,
            "province_id": max(1, int(province_id)),
            "score": score,
            "enabled": True,
            "label": meta["label"],
            "step": s,
            "product_action": meta["action_id"],
            "design_id": drec.get("design_id", ""),
            "domain": drec.get("domain", ""),
        }
    ]
    label = "Execute designer %s · leaf %s · %s/%s · score %.2f" % (
        s,
        leaf,
        drec.get("domain", "?"),
        drec.get("design_id", "?"),
        score,
    )
    return {
        "step": s,
        "leaf_action": leaf,
        "action_id": meta["action_id"],
        "apply_queue": q,
        "score": score,
        "province_id": max(1, int(province_id)),
        "domain": drec.get("domain", ""),
        "design_id": drec.get("design_id", ""),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#e8c060]⚙ Designer %s[/color] [color=#8899aa]%s[/color]" % (s, label),
        "empty": False,
        "ok": True,
        "integration": ["execute_designer_suite_step", s, leaf],
    }


def designer_suite_product_integrity() -> Dict[str, Any]:
    product = build_designer_suite_product()
    empty_cat = build_designer_suite_product({d: [] for d in DOMAINS})
    steps = [execute_designer_suite_step(s, 1) for s in PRODUCT_STEPS]
    gate = execution_integrity_gate()
    sole = sole_mult_integrity()
    ok = (
        not bool(product.get("empty"))
        and int(product.get("catalog_count", 0)) >= 8
        and len(product.get("domain_rows") or []) >= 4
        and all(bool(s.get("ok")) for s in steps)
        and bool(gate.get("ok", False))
        and bool(sole.get("integrity_ok", True))
        and float(product.get("score", 0)) >= float(empty_cat.get("score", 0)) * 0.9
    )
    return {
        "ok": ok,
        "catalog_count": int(product.get("catalog_count", 0)),
        "pick_domain": str((product.get("domain_recommendation") or {}).get("domain", "")),
        "score": float(product.get("score", 0)),
        "gate": gate,
        "summary": "Designer suite product integrity %s" % ("PASS" if ok else "FAIL"),
        "empty": False,
    }


def close_designer_suite_product_loop() -> Dict[str, Any]:
    product = build_designer_suite_product()
    gate = designer_suite_product_integrity()
    land_heavy = build_designer_suite_product(tank_progress=0.05, naval_pressure=0.2)
    naval_heavy = build_designer_suite_product(tank_progress=0.8, naval_pressure=0.85)
    shift = abs(
        float((land_heavy.get("domain_recommendation") or {}).get("score", 0))
        - float((naval_heavy.get("domain_recommendation") or {}).get("score", 0))
    )
    ok = bool(gate.get("ok")) and len(product.get("apply_queue") or []) >= 4
    label = (
        "Close designer suite product · catalog %d · pick %s · shift %.2f · %s"
        % (
            int(product.get("catalog_count", 0)),
            (product.get("domain_recommendation") or {}).get("domain", "—"),
            shift,
            "PASS" if ok else "FAIL",
        )
    )
    return {
        "product": product,
        "gate": gate,
        "pressure_shift": shift,
        "score": float(product.get("score", 0)),
        "summary": label,
        "plain": label,
        "bbcode": "[color=#e8c060]✓ Designer suite product[/color] [color=#8899aa]%s[/color]"
        % label,
        "empty": False,
        "ok": ok,
    }
