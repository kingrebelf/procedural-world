# Roadmap

Status key: **done** (in the repo and covered by tests or screenshots), **partial**, **planned**.

What can and cannot be verified from CI: logic (determinism, persistence, economy,
crafting) is covered by the headless test suite. Rendering is checked by an automated
screenshot tour on a *software* GPU (llvmpipe), which proves the scenes render but says
nothing about frame rate or how it looks on a real RTX card. Performance on the reference
machine has to be measured by a human with the game running.

## Phase 0: Foundations (done)

- Design spec (`docs/SPEC.md`).
- Godot 4.5 project, Forward+ renderer, Jolt physics.
- Platform-independent hashing, per-purpose seeded RNG streams.
- Headless test runner (`tests/run_tests.gd`), screenshot tour (`tools/capture.gd`).

## Phase 1: Persistence core (done)

- Chunk generator: heights, era weights, objects, settlements, loot, traders.
- **Materialise on first sight**: every generated chunk is written to disk immediately and
  only ever loaded afterwards. Player changes (felled trees, mined ore, dug craters, emptied
  chests, trader stock and demand) are written into the snapshot within a second.
- Edge stitching: an existing neighbour is authoritative for shared terrain edges.
- Atomic writes for every file; ZSTD-compressed chunks.
- Inventory with per-item provenance (how, where, when) and persistent unique ids.
- Discovery log of every visited chunk and region, shown on the in-game Atlas.

## Phase 2: World and eras (done, first pass)

- Three eras (Medieval, Fantasy, Sci-Fi) on a domain-warped Voronoi map with soft-min
  blending; terrain, ground material, vegetation, fog and sky all blend continuously.
- Era-specific terrain: rolling hills and river valleys; spires that rise deeper into fantasy
  land; terraced sci-fi plateaus.
- Settlements with flattened plazas, traders and era structure kits.
- Threshold markers inside transition bands.
- Era-aware sky: day/night, stars, fantasy aurora, sci-fi planetary ring and planet.

## Phase 3: Player, tools, economy (done, first pass)

- First-person controller: walk, sprint, crouch, jump, head-bob, fall damage.
- Tools: pickaxes (mine ore and rock, dig persistent craters), axes (fell trees), swords,
  pulse pistol (hitscan, consumes power cells).
- Food and healing. Crafting with 14 recipes.
- Traders with era price bias, demand that drops as you sell and recovers over days, and
  deterministic restocking.
- HUD, inventory with provenance tooltips, crafting, trading, Atlas, pause.

## Phase 4: Settings and distribution (done, first pass)

- Settings: presets (Low/Medium/High/Ultra/Custom), window mode, resolution, V-Sync, FPS
  cap, FOV, render scale, FSR 1 / FSR 2.2, FXAA/SMAA/TAA/MSAA, shadows, GI (SSIL/SDFGI), SSAO,
  SSR, volumetric fog, bloom, auto-exposure, view distance, grass density, mouse, audio.
- Windows export and NSIS installer (components, shortcuts, Apps & Features entry,
  uninstaller that asks before deleting saves). Portable zip and Linux tarball.
- GitHub Actions: tests on every push, builds and installer as artifacts, releases on tags.

## v0.2: Living world (done)

- AI-driven people: generated identities, routines, persistent memories, relationships,
  rumours and deaths. Dialogue through any OpenAI-compatible or Anthropic endpoint, or
  built-in offline dialogue. Built-in utility decision engine, replaceable by an external
  fast decision service (`docs/AI.md`).
- Destructible everything with incremental harvesting and material health pools.
- Look-at info panel, pickup feed, painted item icons.
- Controller support with full rebinding.
- Per-region species of trees, mushrooms, rocks and undergrowth; wildlife; alien ruins.
- Global wind (grass, foliage, clouds, waves); depth- and wind-driven water; swimming.
- Cloud layer, sky and shadow tuning; removed the sci-fi ground grid.
- Stacking with per-source provenance; batch crafting (x1/x5/x10/x100/all) with icons.
- Building: grid-snapped houses from the CC0 Medieval Village and Modular Sci-Fi kits,
  crafting stations (workbench, campfire, forge, anvil, arcane cauldron, fabricator) that
  recipes require, a builder's hammer, all persisted in chunk snapshots.

## v0.3: Beyond the planet (done, v0.3.0 to v0.3.50)

- Vehicles from a vehicle bay, riding horses, and a starship built on a launch pad.
- Orbit, five linked planets per world, each saved on its own, and warp between them.
- Human worlds (medieval near spawn, sci-fi further out, nothing glowing) and alien worlds
  as the endgame, with zone levels by distance, level-gated gear and rare portals.
- Landforms (karst, needles, gorges, crags, badlands, dunes and more), regional climates
  and tropical biomes, rivers, waterfalls, lakes with reefs and fish, real caves.
- Walled towns, market squares, shops, guilds, roads, bridges and viaducts; standing with
  each town, crime, stealth and lockpicking.
- People with natural voices, voice input, body and clothing variety, children, natural
  animation and ragdolls.
- Weather fronts, storms, hail, starfall nights, climate wear, spreading fire.
- Power, logic, defences and automation; lockable doors; storage; waystones.
- Strongholds and dungeons, treasure maps, hidden finds, corpses and death bags.
- Boats with crews, multiplayer with a dedicated server, and every item modelled after
  its icon.

## Phase 5: Fidelity pass (next)

The vertical slice uses procedural code-built meshes. It is coherent and lit with modern
techniques, but it does not yet look AAA. In order of visual impact:

1. **Blender asset pipeline** (`tools/blender/`): headless Blender + Python + geometry nodes
   generating high-detail, LOD'd, bevelled kits per era (cottages with real timber framing,
   castle walls, fantasy tree trunks with roots, sci-fi modular habs), exported to glTF and
   assembled procedurally. Placement stays deterministic and snapshotted.
2. Terrain materials: real PBR texture sets (CC0) with triplanar splatting, height-blending
   and parallax; distance-based macro variation.
3. Foliage: impostors for far trees, wind animation for canopies, ground clutter (stones,
   flowers, fallen leaves), denser grass with distance LOD.
4. Water: rivers in medieval valleys, glowing pools in fantasy, coolant channels in sci-fi.
5. Weather: rain, snow, sandstorms per era, with wet-surface shading.
6. Cinematic post: depth of field in menus, lens flare, film grain toggle, colour grading LUT
   per era.
7. Floating-origin rebasing so precision holds hundreds of kilometres from spawn.

## Phase 6: Gameplay depth (planned)

- Creatures per era (wolves and bandits, wisps and treants, sentinel drones) with simple AI;
  defeated creatures stay defeated (recorded in the chunk snapshot).
- Stamina, carry weight, tool durability and repair.
- Building: place persistent structures (stored as player-added objects in chunk snapshots).
- More eras: Prehistoric, Steampunk, Post-collapse, Alien.
- Quests from traders; reputation per settlement.
- Audio: procedural ambience per era, footsteps by surface, music.

## Phase 7: Performance and polish (planned)

- Profile on the reference machine (RTX 3070, 8-core CPU) and tune presets to hold 60 fps at
  1440p High.
- Move hot generation paths (noise, meshing) to a GDExtension (C++) if GDScript limits
  streaming speed at high view distances.
- Hardware ray tracing if/when Godot exposes it.
- Code-signed Windows installer and an auto-updater.
