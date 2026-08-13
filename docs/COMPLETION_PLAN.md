# Epochs of Ascendancy — Completion Plan (Tier A Campaign Alpha)

> **Updated 2026-07-15** — Phase 1 playability slice landed: Campaign Alpha **primary command strip**.

## Goal

**Tier A — Campaign Alpha:** one nation (GER 1936 default), 100+ day enjoyable loop without F10 harness dependence.

## Architecture (sacred)

```
pure product → MapPolishFormatters → MapManager live/apply
  → GameData routes → OrderCommandPanel → ProvinceInsight
  → dual world_full + map CI + SCRIPT 0
```

No province ID changes. Dual bar stays green.

## Phases

| Phase | Focus | Status |
|-------|--------|--------|
| **0** | Freeze catalogue; authority docs | In progress |
| **1** | Playability Alpha spine | **Primary strip landed** |
| **2** | Content / portraits / balance | Next |
| **3** | Perf hard gate (60 fps) | Open |
| **C** | Multiplayer / HOI 3D / NUTS remesh | Parked |

## Phase 1 — Primary strip (this slice)

- [x] Pure `campaign_alpha_primary_strip_product.py` — 8 live actions · recommended-next · dead audit
- [x] Formatters + MapManager live/apply + GameData routes
- [x] OrderCommandPanel: always-visible primary strip · majors collapsed · day packages `max_expanded=1`
- [x] ProvinceInsight chip priority **163** (always-on)
- [x] Dual marker `campaign_alpha_primary_live=1` · CI test gate
- [x] **Stream α Packs C/E/F/G** — combat ribbon · OOB production board · HH TopInfoBar · Save Browser product path
- [x] Dual `stream_alpha_packs_live=1`
- [ ] 100d player-path dual (extend completion_playability) — next
- [ ] Pack N era content density — next

Catalogue labels: campaign alpha · primary strip · phase1_alpha · playability · stream_alpha

Dual markers: `campaign_alpha_primary_live=1` · `stream_alpha_packs_live=1`

## Build rules

1. Vertical playability > new majors #59+
2. Dual world_full · SCRIPT 0 · map CI sacred
3. Prefer wiring existing spines over catalogue churn
