# STARTUP-GUARD one-run result — PARK

**MERGE: HOLD.** Test-only. **Not** a product fix. **Not** live-startup PASS.
Does **not** touch `grok/tooltip-p1` or PR **#164**.

## Identity

| Item | Value |
|------|--------|
| Trusted main (base) | `7d7a0b856efba61c04364f123b6a7f37c3e310c8` |
| Branch | `cursor/startup-guard-1-5dbe` |
| Implementation commit | `e9ec08bbe3d28c43d9a3e5211d52d16d922b0ab4` |
| Guard | `WindowedStartupGuardTest` on `LivingTitleBoot.handle_live_begin` |
| Host | cloud xvfb only (not live desktop / not laptop Play) |

## Reproducible command

```bash
EOA_STARTUP_GUARD_OUT=/tmp/eoa-startup-guard tools/eoa_startup_guard.sh
```

| Runtime | Observed |
|---------|----------|
| Engine binary | `/home/ubuntu/Applications/Godot-4.7.1/godot` (provisioned **outside** the repo) |
| `--version` | `4.7.1.stable.official.a13da4feb` |
| Banner | `Godot Engine v4.7.1.stable.official.a13da4feb` |
| Launch | `tools/run_godot.sh --path . --resolution 1280x800 --position 0,0 -s res://scripts/core/WindowedStartupGuardTest.gd` |
| xvfb | `-screen 0 1280x800x24` — **not** `--maximized` |
| Import | separate headless `--import --quit`, timeout 1500s, then one windowed process, timeout 600s |
| Flags | `EOA_SMOKE_AUTO_BEGIN=0`, `EOA_SMOKE_ADVANCE_PAST_PLUS6=0`, `EOA_SKIP_TITLE` unset |
| XDG | fresh nonempty `$OUT/xdg/{data,config,cache,saves}` |
| Renderer this run | Vulkan surface missing → OpenGL 3 / `llvmpipe (LLVM 20.1.2)` (Mesa 25.2.8) |
| Peak RSS | `2303480` KiB = **2249.5** MiB (`rss.txt`) |
| Windowed rc | 0, `RESULT=COMPLETED` |
| Inventory unittest | 3 tests OK in 0.035s |

JSON field `engine_version` is a **formatter concatenation** of `Engine.get_version_info()` (`4.4.7.1-stable (official).stable.a13da4feb8d8aefc283c3763d33a2f170a18d541`). The process banner / `--version` above is the authority. Not a second engine.

## Labels (do not collapse)

| Label | Value |
|-------|-------|
| `DATA_INVARIANT` | **PASS** |
| `PRESENTATION` | **DIAGNOSTIC** |
| `LIVE_BLANK` | **NOT_REPRODUCED** |
| `FIXTURE` | **PASS** |
| `LIVE_STARTUP` | **NOT_CLAIMED** |

`data_fail=[]`, `fixture_fail=[]`. Wrapper refused any `LIVE_STARTUP=PASS`.

## DATA (assertion)

Unchanged `pre_begin` → `post_dismiss` → `post_resize`:

| Field | Observed |
|-------|----------|
| player_tag | GER |
| date | 1936-01-01 00:00 |
| province_n | 3596 (shipped expect 3596) |
| berlin_710300 owner | GER |
| formation_n | 828 |
| identity_fp | `828:636003609` |
| garrison_1936 | **535** (same all three phases) |
| unit_icon_nodes | 259 |
| stockpile_fp | `3210958319` |
| stockpile values | aluminum 4000, coal 8000, fuel 4000, rubber 2000, steel 12000 |

`garrison_1936_observed=535` vs empty-board seed target **575** is a **definition difference** (live F5 board already occupied; `seed_1936_start_garrisons` skips occupied hexes). Reported, not invented. **Not** a Begin wipe: 535→535.

Static inventory (no extra Godot):

| File | SHA-256 |
|------|---------|
| `manifest_world_accurate.json` | `21212fa422904bf676705f3bc2c4315f3c76c11a2bde1f74a8d9e36cdf2ee7a7` |
| `provinces_base.json` | `d62645e9365f5f25c6bf3f566e6b3b50f0380fdec24f48a03e315a980bbd8fb4` |
| `province_ownership_1936.json` | `c3ba2b0e92d09187b6a1bf18bd769e20e0ac60c4331945c9456d753b0a7513f8` |
| `province_adjacency.json` | `be00f5bafa5fe625fb3c31dcc2bd07b426431ae11ff3a85ebaf60c7f7f5ca128` |
| `hierarchy_membership_1936.json` | `3cad187c960721ef634d5af25b617363600134c811b78602e351f9ed2d357e6d` |

Province IDs **3596**, Berlin `710300` present. Seed `20fe9063…` **not recomputed**.

## PRESENTATION (diagnostic — not pixel oracle)

Monotonic `Time.get_ticks_usec` since engine start (not wall 4×30s waits):

| Event | usec | Δ from Begin |
|-------|------|--------------|
| guard_start | 902881 | |
| world_ready | 29237294 | world built **before** Begin (~28.3 s after engine) |
| pre_begin shot | 31852740 | |
| **Begin** `handle_live_begin` | 33207227 | 0 |
| boot_closed | 33288004 | +80.8 ms |
| tree_exited | 33797577 | +590.4 ms |
| overlay_gone (visible=false) | 33900548 | +693.3 ms |
| post_dismiss shot | 34486644 | +1.279 s |
| controlled resize 860×550 | 35312206 | +2.105 s |
| post_resize shot | 36204812 | +2.998 s |

Begin return: `{ok:true, closed:true, mode:new, player_tag:GER, year:1936}`.
`boot_closed`: `applied=true`, `defaulted=false`, `default_ger=true`, `default_1936=true`.

| Phase | title_visible | window | mode | ALWAYS_ON_TOP | viewport | camera zoom | capital 710300 in view |
|-------|---------------|--------|------|---------------|----------|-------------|------------------------|
| pre_begin | **true** | 1280×800 | windowed | true | 1280×800 | 0.344 | true |
| post_dismiss | **false** | 1280×800 | windowed | false | 1280×800 | 0.787 | true |
| post_resize | false | **860×550** | windowed | false | **still 1280×800** | 0.787 | true |

Product Begin did **not** `set_size`. ALWAYS_ON_TOP went true→false as the title path does. Soft-center raised zoom 0.344→0.787; GER centroid ≈ (7603.8, 1553.1). Mesh/icon **counts are not pixels**:

| Phase | mesh vis/in_view | icon vis/in_view | image looks_uniform_light | near_light_frac |
|-------|------------------|------------------|---------------------------|-----------------|
| pre_begin | 3596 / 1915 | 259 / 136 | false | 0.01375 |
| post_dismiss | 3596 / 1263 | 259 / 100 | false | 0.01525 |
| post_resize | 3596 / 1263 | 259 / 100 | false | 0.015 |

Resource-chip **container** visible at `vp_w=1280` (`layout_hides_below_1280=false`). Chip **text** reads `"0"` while GameData stockpile values are 4000/8000/… — presentation chrome vs data, **not** treated as a wipe.

## Screenshot observations (cautious)

PNGs are viewport `get_texture().get_image()` at the labeled phase. Sampled RGB is **not** a pixel oracle.

- **`pre_begin.png`**: title overlay **is** on screen (“Epochs of Ascendancy”, Begin Germany 1936). Colored Europe + unit chips visible beside it. Metadata `title_visible=true`. **Not** a post-dismiss frame.
- **`post_dismiss.png`**: title overlay **gone** (`title_visible=false` in metadata; no title card in the image). Colored political map still present (GER red, neighbors distinct), unit chips visible, Berlin tooltip “Owner: GER”, notices still up. **Not** a uniform light-blue / empty field.
- **`post_resize.png`**: visually the same populated Europe field as `post_dismiss`. Window chrome recorded 860×550; captured viewport texture stayed 1280×800, so this is **not** a viewport-shrink shot.

Prior attached `*_post_begin` frames that still showed the title are **not** this run’s post-dismiss evidence.

## LIVE_BLANK

**NOT_REPRODUCED** on this fixture. The pair’s populated-setup-then-blank/light-blue view did **not** appear here after real overlay disappearance.

This is **incomplete coverage of the live pair**, not a product acquittal:

- xvfb + llvmpipe after Vulkan fallback ≠ live desktop WM / default GPU path
- launch was 1280×800 windowed, **not** the pair’s `--maximized`
- `window_set_size(860,550)` did **not** shrink the viewport (stayed 1280×800); chip-hide-below-1280 never triggered
- one run only; trusted **main** only (not tip `26797ec9`)
- seed `20fe9063…` not rerun
- ObjectDB leak warning at exit (7 objects / 3 resources) recorded, not diagnosed

**Never** live-startup PASS.

## Smallest isolated product-fix PROPOSAL (not implemented)

**Unknown.** This run does not justify a product patch.

`handle_live_begin` on this xvfb 1280 windowed recipe preserved data identities and left a varied, titled-off map image. The pair blank (both `7d7a0b85` and `26797ec9`, after a maximize→~860 resize on a live desktop) remains **outside** this isolated Begin function under these launch conditions.

If OP continues: a **separate** Play-path recipe that **holds maximize** and records whether the **viewport** (not only `window.size`) actually drops — still test-only, still not a product edit. Do not treat resize-alone as proven; earlier 7bf first-window ~860 populated vs maximized-second blank already weakens that.

No production change was required to observe this fixture. Parked.

## Cited artifacts

This directory, also copied to `/opt/cursor/artifacts/startup-guard/`.
