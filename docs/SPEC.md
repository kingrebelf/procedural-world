# Procedural World: Design Specification

Working title: **Procedural World**. License: MIT. Engine: Godot 4.5 (Forward+ renderer).
Target platform: Windows 10/11 x64 (primary), Linux x64 (secondary).
Reference hardware: NVIDIA RTX 3070 (8 GB), 8-core desktop CPU in the same price class
(Ryzen 7 5800X / Core i7-11700), 32 GB RAM, SSD.

This document is the source of truth for what the game is. `ROADMAP.md` says in what order
it gets built and what is actually done today.

---

## 1. Pitch

A first-person exploration, survival-crafting and trading game set in a single infinite world
that is generated as you walk. The world is a patchwork of **eras**: a medieval countryside can
give way to a glowing fantasy wildwood, which can give way to a sci-fi frontier of alloy
plateaus and light-lined spires. Each crossing is a smooth, believable transition, never a hard
seam.

The defining rule: **once something exists, it exists.** Every hill, tree, ruin, ore vein,
chest, trader and item the world ever generates is recorded the first time it comes into being
and is never regenerated, re-rolled or forgotten. Walk away for a hundred hours and come back:
the crater you dug, the tree you felled, the chest you emptied, are exactly as you left them.

## 2. Design pillars

1. **Permanence.** Generation is deterministic *and* the first result is snapshotted to disk.
   Player changes are applied on top and saved immediately. Nothing is ever re-rolled.
2. **Coherent strangeness.** Era changes are surprising but designed: terrain shape, palette,
   vegetation, architecture, lighting and fog all cross-fade together over a transition band.
3. **Fidelity first.** Physically based materials, dynamic global illumination, volumetric
   fog, a day/night cycle, temporal anti-aliasing and upscaling. Art quality is a feature, not
   polish.
4. **Things have provenance.** Every item knows where and when it was found, mined or made.
   Value depends on where you sell it: a sci-fi power cell is a marvel in a medieval market.
5. **Respect the player's machine.** A full graphics menu with presets, and a proper Windows
   installer and uninstaller.

## 3. Core loop

Explore → discover (biomes, settlements, caches, ore) → gather (mine, chop, loot) →
craft (refine, build tools and weapons) → trade across eras for profit → buy better gear →
explore further and more dangerous regions.

## 4. World

### 4.1 Coordinates and chunks

- World units are metres. The world is a heightfield plane extending infinitely in X and Z
  (bounded only by float precision; origin shifting is planned, see roadmap).
- The world is divided into **chunks** of 64 m × 64 m, addressed by integer `(cx, cz)`.
- Each chunk stores a 65 × 65 height grid at 1 m spacing (edges shared with neighbours), plus
  a list of **world objects**.

### 4.2 Eras

An era is a data-driven definition (`src/world/eras.gd`) of:

- terrain character (amplitude, roughness, terracing, spires),
- ground palette (grass, soil, rock; emissive accents),
- sky, fog and ambient light tints,
- vegetation set and density,
- structure kit (what a settlement or ruin is built from),
- resource set (which ores and loot appear) and trader price biases.

Shipping eras:

| Era | Terrain | Look | Resources |
|---|---|---|---|
| **Medieval** | rolling meadows, river-cut valleys | green grass, chalky rock, warm daylight | wood, iron ore, stone, coin hoards |
| **Fantasy** | dramatic spires, mossy hollows | teal and violet moss, glowing flora, mist | glowroot wood, aether crystal, mythril |
| **Sci-Fi** | terraced plateaus, flattened pads | graphite ground, alloy plates, cyan light strips | alloy scrap, power cells, circuitry |

The era system is open: further eras (Prehistoric, Steampunk, Post-collapse, Alien) are pure
data plus a structure kit.

### 4.3 Era map and transitions

- Era regions are a jittered **Voronoi** partition with a cell size of 512 m. Each site's era
  is picked from a hash of `(seed, site)`; adjacent sites are allowed to share an era, which
  produces larger, irregular regions.
- At any position the generator computes **era weights** from the distances to the nearby
  sites using a soft-min (`w_i = exp(-(d_i - d_min) / τ)`, τ ≈ 22 m), giving a transition band
  of roughly 60 to 90 m. Weights are continuous, so every derived quantity is continuous.
- Everything blends by these weights: terrain height functions, ground material colours (per
  vertex), vegetation choice and density, fog density and colour, sky tint and ambient light.
- Structures are only placed where one era dominates (weight > 0.8) so buildings never straddle
  a seam. Inside the transition band, special **threshold objects** (worn standing stones on the
  medieval side, crystal shards on the fantasy side, beacon pylons on the sci-fi side) mark the
  crossing so it reads as intentional.

### 4.4 Terrain

`height(x, z) = continental(x, z) + Σ_era w_era · era_shape_era(x, z)`

- `continental`: very low frequency FBM shared by all eras (hundreds of metres), so large
  landforms continue through transitions.
- Medieval: medium-frequency FBM hills plus a ridged river-valley term.
- Fantasy: ridged noise raised to a power for spires and hollows, plus a domain-warped layer.
- Sci-Fi: smooth base quantised into terraces with a smoothstep between levels so slopes stay
  walkable, plus flattened landing pads.
- Collision uses a height-map shape per chunk. Rendering uses a triplanar PBR shader blended by
  slope and era weight.

### 4.5 World objects

Every object in a chunk has a stable identity `(cx, cz, index)` assigned at generation time.

| Kind | Examples | Interactions |
|---|---|---|
| Tree | oak, pine (Medieval), glowcap, crystal tree (Fantasy), solar mast (Sci-Fi) | chop with axe → wood type |
| Rock | boulders | mine with pickaxe → stone |
| Ore node | iron vein, aether crystal, alloy scrap pile | mine → ore, depletes |
| Cache | chest, rune coffer, supply pod | open → loot (contents fixed at generation) |
| Structure | cottage, watchtower, shrine, hab dome, comms spire | static scenery, settlement anchor |
| Trader | merchant per era | buy/sell |
| Room prop (Lore) | terminals, wall screens, holo-tables, bookcases, lecterns, journals, letters, scrolls, tombs inside walk-in rooms | Interact → read logs, books and epitaphs about the place; terminals download their survey to the atlas and charge flashlights once a day, holo-tables mark the nearest settlement, a shrine's rite restores stamina daily (state in the room's `lore` / `lore_act`) |
| Threshold marker | standing stone, crystal shard, beacon | scenery in transition bands |
| Creature (planned) | wolves, wisps, sentinel drones | combat, drops |

Settlements: a deterministic 256 m site grid; each site has a hash-based chance of hosting a
settlement if its era weight is dominant. A settlement places a trader and 3 to 7 structures
around a clearing.

## 5. Persistence (the non-negotiable)

### 5.1 Principle

Two layers make "once it exists, it exists" true:

1. **Deterministic generation.** All randomness is derived from `hash(seed, cx, cz, salt)`
   (a fixed, platform-independent 32-bit integer hash, `src/core/hash.gd`) feeding
   per-purpose PCG generators. No global RNG is ever used for world content.
2. **Materialise on first sight.** The first time a chunk is generated, its full result (height
   grid, every object with transform and initial state, every cache's loot list, every trader's
   stock) is written to disk. From then on the chunk is **only ever loaded from disk**, never
   regenerated. This makes the world immune to generator changes in future game versions:
   updating the game cannot move a mountain you have already seen.

Player changes are stored in the same snapshot (the snapshot is the live state, not a pristine
copy plus a diff). Removed objects are kept as records with `gone = true` so their identity is
never reused.

### 5.2 What is persisted

| Data | Where | When written |
|---|---|---|
| World meta: seed, name, generator version, created, play time, game clock | `world.dat` (Godot text variant, human-readable) | on create, every autosave |
| Player: position, look, health, money, selected slot | `player.dat` | every autosave (10 s), on quit, on pause |
| Inventory and equipment, every item with provenance | `player.dat` | within 1 s of any change |
| Chunk snapshot: heights, objects, object state | `chunks/<cx>_<cz>.chunk` | on first generation, within 1 s of any change |
| Discovery log: visited chunks with first-visit time, named places | `discovery.dat` | on each new chunk visited |
| Settings (graphics, audio, controls) | `user://settings.cfg` (not per world) | on change |

Save root: `%APPDATA%\ProceduralWorld\worlds\<world-id>\` on Windows (Godot custom user
directory), `~/.local/share/ProceduralWorld/` on Linux.

### 5.3 Integrity

- Every write is atomic: write to `<file>.tmp`, flush, then rename over the original. A crash
  mid-save leaves the previous good file.
- Chunk files are ZSTD-compressed Godot binary variants with a `format` field for migrations.
- Each world records `gen_version`. Chunks already on disk keep their content regardless of
  generator version; only never-seen chunks use the current generator. Borders between old and
  new chunks are stitched by the snapshot of the older chunk being authoritative for shared
  edge vertices.
- Approximate cost: a chunk is about 8 to 12 KB on disk. 10,000 explored chunks (about 41 km²)
  is roughly 100 MB.

### 5.4 Items

```
Item {
  uid:      int        // unique per world, from a persisted counter
  type:     String     // key into ItemDB
  qty:      int        // stackables only
  quality:  float      // 0.5..1.5, affects value and tool power
  name:     String     // generated for notable items ("Ashwood Pick of Varn")
  origin:   { era, chunk, how: "mined"|"found"|"crafted"|"bought", day }
}
```

Stackable raw materials stack by `(type, quality band)`. Tools, weapons and notable items are
unique instances and are never merged or re-rolled.

## 6. Player

- First-person controller: walk 4.5 m/s, sprint 8 m/s, crouch, jump, head-bob, smooth
  slope handling, fall damage (planned).
- Health; stamina (planned).
- Hotbar of 6 slots plus a 36-slot backpack. Weight limit (planned).
- Interaction ray (3 m): open caches, talk to traders, pick up.

### 6.1 Tools and weapons

| Item | Era | Use |
|---|---|---|
| Pickaxe (iron / mythril / plasma) | any | mine rock, ore, dig terrain |
| Axe | any | chop trees |
| Sword | Medieval/Fantasy | melee, 3 m arc |
| Pulse pistol | Sci-Fi | hitscan ranged, uses power cells |

Tool tier multiplies gather speed and yield. Digging lowers terrain in a smooth crater and is
persisted in the chunk height grid (and any neighbour chunk that shares the affected vertices).

## 7. Economy

- Currency: **Marks**, carried in `player.money`.
- Every item type has a base value. A trader's offer is
  `base × quality × era_factor × demand_factor`.
- **Era factor**: goods foreign to the trader's era sell for a premium (1.6× to 2.4×), goods
  native to it are discounted (0.7×). This is the core arbitrage loop.
- **Demand factor**: every unit the player sells to a trader lowers that trader's price for that
  type by 8% (compounding); it recovers toward 1.0 over in-game days. Trader stock and demand
  are persisted in the trader object's state.
- Trader stock is generated on first sight and restocks on a deterministic in-game schedule.

## 8. Crafting

Recipes (`src/items/recipes.gd`) consume inputs from the inventory. Initial set: planks, iron
ingots, mythril ingots, alloy plate, tool upgrades, sword, pulse pistol, power cells. Crafted
items record `how = "crafted"`.

## 9. Visual target and rendering

Renderer: Godot Forward+ (Vulkan on Windows, D3D12 optional).

- Lighting: directional sun and moon with cascaded shadows, physically based sky, day/night
  cycle, SDFGI for dynamic global illumination (High/Ultra), SSIL (Medium+), SSAO.
- Atmosphere: volumetric fog with era-blended density and albedo, height fog, aerial
  perspective through fog.
- Post: ACES filmic tonemapping, auto-exposure, bloom/glow, SSR on wet/metal surfaces,
  TAA or FSR 2 temporal upscaling.
- Materials: physically based, triplanar terrain with procedural micro-detail normals, emissive
  accents for fantasy and sci-fi.
- Vegetation: GPU-instanced grass with wind animation, per-era meshes.
- **Ray tracing**: Godot 4.5 has no hardware ray tracing API. "Ray-traced" style lighting is
  approximated with SDFGI plus SSR. Hardware RT is tracked in the roadmap as a future option
  (dependent on engine support).

Performance budget on the reference machine at 1440p with the High preset:
60 fps or better, under 6 GB VRAM, under 8 GB RAM. (Design target; it must be measured on real
hardware, and cannot be measured in CI.)

### 9.1 Asset strategy

The vertical slice builds every mesh procedurally in code (Godot `ArrayMesh`/`SurfaceTool`)
so the whole game is generated and reproducible. For AAA-level fidelity the roadmap adds a
**Blender asset pipeline**: headless Blender Python scripts in `tools/blender/` generate
high-detail, LOD'd structure and prop kits per era (geometry nodes), exported as glTF and
assembled procedurally at runtime. Those meshes are still procedurally placed and snapshotted.

## 10. Graphics and game settings

Settings live in `user://settings.cfg` and apply live.

| Group | Settings |
|---|---|
| Preset | Low, Medium, High, Ultra, Custom |
| Display | resolution, window mode (windowed, borderless, exclusive fullscreen), monitor, V-Sync (off/on/adaptive/mailbox), FPS cap, field of view (60 to 110) |
| Upscaling | render scale (50% to 200%), scaler (Bilinear, FSR 1, FSR 2.2), sharpness |
| Anti-aliasing | Off, FXAA, SMAA, TAA, MSAA 2x/4x/8x |
| Lighting | shadow quality (cascade size + filter), shadow distance, global illumination (Off, SSIL, SDFGI), SSAO, SSR, volumetric fog quality |
| Post | bloom, auto-exposure, film grain off/on, motion-sickness options (head-bob) |
| World | view distance (chunk radius 3 to 8), grass density, object LOD bias |
| Controls | mouse sensitivity, invert Y, key bindings (planned) |
| Audio | master, music, effects (audio content planned) |

Presets map onto these values (see `src/settings/graphics_settings.gd`).

## 11. Windows distribution

- Build: Godot export (`Windows Desktop`, x86_64, embedded PCK) produces
  `ProceduralWorld.exe`.
- Installer: **NSIS** (`installer/windows/installer.nsi`), built on Linux or Windows:
  - welcome, MIT license, component selection, install directory, progress, finish with
    "Launch game" option;
  - components: Game files (required), Start Menu shortcuts, Desktop shortcut;
  - per-machine install into `Program Files\Procedural World` (admin) with registry entries
    for *Apps & Features* (publisher, version, size, icon, uninstall string);
  - uninstaller removes files, shortcuts and registry keys, and asks whether to also delete
    saved worlds and settings (default: keep);
  - 64-bit Windows check.
- A portable `.zip` is published alongside the installer.
- CI (GitHub Actions) runs the headless test suite, exports Windows and Linux builds, compiles
  the installer, and attaches all of it to a GitHub Release on version tags.

## 12. Audio (planned)

Era-blended ambient beds (birds and wind; chimes and hum; servo and wind over alloy),
footsteps by surface, tool impacts. Procedural synthesis first, recorded CC0 assets later.

## 13. Non-goals for now

Multiplayer, mod loader, quests and story, voice acting. The persistence format is designed so
multiplayer could later reuse it (chunk ownership is per file).
