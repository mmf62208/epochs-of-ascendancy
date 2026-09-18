# 2026-09-18 Maginot playtest — closeout process

> **Not SNAPSHOT.** Live truth stays [`GAME_STATUS_SNAPSHOT.md`](../GAME_STATUS_SNAPSHOT.md).  
> **Launch bar** stays [`DESIGN_LAUNCH_PROGRAM.md`](../DESIGN_LAUNCH_PROGRAM.md): 1.0 = one theater land war + production + save + 3-era boot.  
> **Play tree:** `execute-plan/856bb385-pr-3-factory-toe-on-the-default-play-strip` (not stale `main`).  
> **Date:** 2026-09-18 human F5 Maginot.

This note is the process after a full day of collaborative F5: what landed, what the hexes actually are, what to fix next, and how to close the game without opening museum-map or dual-package work.

---

## 1. What today proved

The Maginot **click-order war is real**. Best human run: declare → fight → occupy walk-in → **many French hexes taken** → calendar **12 Jan 23:00**. That is the first-session loop the launch program asked for.

Machine still holds: `HeadlessWorldAccurateUnitOrderLoopTest` **RESULT=PASS** (occupy walk-in, rear stack not yanked, second occupier does not bounce GER home).

### Landed on this tree today (play-driven)

| Slice | What changed | Honest leftover |
|-------|----------------|-----------------|
| Click never `execute` on F5 | Missing-start toasts; `start_land_battle` only | Debug/F10 sample may still execute |
| Occupy | Only assault-hex stack walks in; later stacks station; no recapture-as-GER bounce | Empty-hex occupy still a freeze magnet if RSS climbs |
| Resolve frame | Toast-only on break; no Fight/NEXT rebuild that frame | 1× can still climb RSS over many captures |
| Pick/hover | Canvas transform (not Camera2D node); capital snap in-country; chip disk 32px | Adjacent hex chips still sit on top of each other |
| Political vs F9 | Resource glyphs off political; painted goods on F9 | — |
| Stack cycle | Left-click cycles; right-click same hex cancels | — |
| Air | H is not hills; select wing + right-click hex = CAS region; capture retasks CAS | GER CAS **base** is still Berlin; FRA air in Paris stays until Paris falls |
| Hex readout | Hover/select = **fill tint**, not cyan Line2D; no operational region hull | NUTS Landkreis still overlap; city-NUTS still tiny |
| RSS | Sample `/proc/self/statm` + texture fallback; **do not** `OS.execute(awk)` | Tripwire **still failed** in play (5–18 GB with no pause). Treat as **open P0 for close-out** |

### Honest freeze log (do not flatten)

| Wall | RSS | Trigger |
|------|-----|---------|
| Occupy recapture | ~13.5 GB | Second GER walk-in treated GER as defender |
| Occupy all att_fids | ~12.5 GB | Marched-away / rear stacks yanked to Bas-Rhin |
| Maginot resolve UI | ~8.5 GB | Fight card + NEXT + arrows on the break frame |
| 10d conquest | ~12–18 GB | Many occupy + right-click Paris; tripwire silent |
| H = elevation | ~9.5 GB | 3520 hill overlay; awk fork on RSS |
| Last window | ~5.7 GB | Still climbing; TimeManager once failed to compile (`TOTAL_VIDEO_MEM_USED`) |

**Close-out rule:** a Maginot session that cannot pause at ~2.5 GB is not 1.0, even if the war loop works.

---

## 2. What the latest screenshot is (Kusel / stacked GER)

That is **not** one stack. It is **two living counters on neighboring NUTS hexes** whose centroids are closer than the plate (~50 px). Both use the same chip offset `(0, -12)`. Peeking `×2` / `1/3` is **same-hex** only.

| Do | Don't |
|----|--------|
| Offset chips by a **stable hash of pid** (8–14 px, 4–6 directions) so adjacent Maginot hexes don't share a pixel | Rebuild NUTS so every Landkreis is a hex |
| Keep same-hex stacks as peeking plates + cycle | One chip for the whole Rhine |

Bounded Maginot theater: GER `710173` / FRA `710739` + ~20 Rhine NUTS. Not world-wide chip layout.

---

## 3. Hexes — what is actually wrong

The **pointer is the source of truth**. Fills are NUTS. Problems are three different bugs; mixing them wastes weeks.

### A. Readout ( Maginot-blocking ) — **take ground, then stop**

- Cyan Line2D traced the **full overlapping NUTS ring** (Moselle C around LUX, Freiburg city inside a Landkreis, Südwestpfalz over FRA).
- **Done this session:** fill-tint hover/select; no operational region hull; no hover Line2D.
- **Next (one PR max):** pid-hash chip offset so Kusel/Maginot plates don't share a pixel. Headless: two adjacent GER pids → chip global_positions differ by ≥ 24 px at Maginot zoom.

### B. Fill quality ( ugly, not unplayable )

- **Glass shards** (Groß-Gerau): raw ring as one `Polygon2D` → Godot triangulation junk. **Done:** `convex_parts` decompose; hull only if area grows ≤ 1.35× (Moselle must not swallow LUX).
- **Verify next F5:** Groß-Gerau / Kusel / Freiburg are **solid** country color, not triangles.
- If still shards: cap parts at 32 and drop slivers below `MIN_AREA`. Do **not** hull Moselle.

### C. NUTS topology ( parking lot )

German **Landkreis vs Stadtkreis**, French departments wrapping LUX, Rhine bank mismatch. That is **data**: clip-to-owner, merge city into county, or museum borders.

**Non-goals (already in launch program):** 13k HOI provinces, densify, SE Asia micro-merge, `world_full` ID renumber.

**Close-out rule:** if you can **pick, fight, occupy, and read owner** on Maginot, hex work **stops** until RSS + 20-minute loop are green. Hexes are not the 1.0.

---

## 4. How to continue (session protocol)

Every sitting, in this order. If a sitting skips 1–2, it is a map rabbit hole.

1. **Read SNAPSHOT** (one screen). This note does not override it.
2. **F5 Maginot** on the factory-toe play tree via `tools/run_godot.sh`. Not `main` @ `2d56b84`.
3. **One slice** from the queue below. Headless `HeadlessWorldAccurateUnitOrderLoopTest` **RESULT=PASS** after any occupy/pick/air change. `--quick` while iterating.
4. **Human note** in this file or M6 smoke: date, days reached, RSS peak, freeze Y/N, one screenshot if hex/chip.
5. **Stop the sitting** when Maginot loop still works and RSS is honest — even if Groß-Gerau is ugly.

### Queue (strict order)

| # | Slice | Done when | Stop if |
|---|--------|-----------|---------|
| **0** | **RSS tripwire actually pauses 1×** | F5 print `RSS tripwire N KB last=` before 3 GB; human cannot sit at 12 GB | More hex art |
| **1** | **Chip pid-hash offset** | Adjacent Maginot GER plates ≥ 24 px apart; same-hex still peeks | World-wide layout |
| **2** | **20-minute stranger loop** | PLAYTEST §0b 11–15 marked; one 20d unpause note in M6 smoke | New mapmodes |
| **3** | **Air is one sentence** | Select CAS wing → right-click Paris → toast CAS covering Paris; H never elevation | Air designer / rebase animation |
| **4** | **Save after a real war** | Ctrl+S after occupy walk-in; Ctrl+L restores owners + open fight | New save schema |
| **5** | **Hex readout freeze** | Fill-tint + solid convex fills on Rhine; SNAPSHOT says hex work parked | Clip-all-NUTS / 13k |

PRs 1–6 from the launch DAG stay **stacked, not merged**, until you say merge. Do not open JOINING/Taken/portraits as a second Maginot rewrite — they already shipped on the execute-plan stack.

---

## 5. Closing the game (1.0)

**1.0 ships when a stranger can:**

1. F5 GER 1936, political Europe, Maginot chips visible, **no SCRIPT ERROR**.
2. Click GER chip → right-click Alsace → declare if needed → 1× → FRA breaks → GER walks in → hex GER.
3. Take 2–3 more hexes without 1× locking; if memory climbs, **game pauses** with a last-callee line.
4. Open Production, see Fill% / stockpile, Ctrl+S / Ctrl+L.
5. Optionally boot 1918 or 2026 without a grey map.

**1.0 does not require:** hexes that would pass a cartography review, HOI designer, naval TF, ideology UI, MP, V3 pops, epoch fit/lift, 30 fps hard pass, M6-as-machine-gate.

### Merge / publish

- Play lives on **factory-toe** until RSS + §0b 11–15.
- Then **one** merge to `main` of that tree (not six surprise PRs).
- Steam/EA price still depends on **that** bar (`DESIGN_LAUNCH_PROGRAM` + market note): thin theater war, not HOI4.

---

## 6. Anti-patterns (today's traps)

- `Camera2D.get_canvas_transform()` for pick (cursor north, fill south).
- `OS.execute("awk")` every capture (fork freeze).
- `RENDERING_INFO_TOTAL_VIDEO_MEM_USED` on 4.7.1 (TimeManager failed to compile).
- Occupy-after-win enqueue **every** `att_fid`.
- Recapture when controller is already GER.
- H = 3520 elevation.
- Convex hull of Moselle as hover Line2D.
- Treating Groß-Gerau shards as “need 13k hexes.”

---

## 7. Next human sitting (copy onto SNAPSHOT when you agree)

1. F5 this tree. Hover Kusel / Groß-Gerau / Moselle: **solid fill**, no cyan ring, LUX stays a hole.
2. Maginot war to **at least 5 occupied hexes**. Watch RSS. If 1× does not pause by ~3 GB, **slice 0 is still open** — do not start hex clipping.
3. If plates still occupy the same pixel, **slice 1** (pid-hash offset) only.
4. Append M6: days, freeze Y/N, RSS peak.

Until slice 0 is green, **do not** open NUTS clip, densify, or epoch-loop PRs.
