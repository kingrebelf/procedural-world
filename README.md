# Procedural World

A free and open-source first-person survival and exploration game set in one endless world
that is generated as you walk. You start in medieval country: walled towns, market squares,
farms, rivers and old forests. The further out you travel, the more dangerous and rewarding
the land becomes, until human sci-fi outposts take over, and in the end the stars and the
alien worlds beyond them.

**Once it exists, it exists.** Every hill, tree, ruin, chest, trader and item the world
generates is saved the first time it appears and is never regenerated. The tree you felled,
the crater you dug, the house you burnt down, the chest you emptied and every item in your
pack (with where and when you got it) stay exactly as you left them, forever.

> Status: v0.3.50, an early but large vertical slice. Single player or multiplayer on your
> own dedicated server. Download it from the
> [Releases page](https://github.com/kingrebelf/procedural-world/releases). The roadmap is
> in [docs/ROADMAP.md](docs/ROADMAP.md).

![A walled medieval town](docs/screenshots/town.jpg)

## Screenshots

All shots are taken in game (v0.3.50, seed 4242, High preset, 2560x1440 on an RTX 4090),
with the HUD hidden.

### The land

| | |
|---|---|
| ![Sunset over medieval farmland](docs/screenshots/sunset.jpg) | ![A river in its own valley](docs/screenshots/river.jpg) |
| ![A stone viaduct carrying a road](docs/screenshots/viaduct.jpg) | ![Karst towers over a lake](docs/screenshots/karst.jpg) |
| ![Old-growth forest from a ridge](docs/screenshots/forest_overlook.jpg) | ![Inside the forest](docs/screenshots/forest.jpg) |
| ![A waterfall and its plunge pool](docs/screenshots/waterfall.jpg) | ![A valley below a waterfall](docs/screenshots/waterfall_valley.jpg) |
| ![Tropical rainforest](docs/screenshots/rainforest.jpg) | ![Dry savanna](docs/screenshots/savanna.jpg) |

### Towns and people

| | |
|---|---|
| ![A village yard](docs/screenshots/village_yard.jpg) | ![A market square](docs/screenshots/market.jpg) |
| ![Village fields](docs/screenshots/village_fields.jpg) | ![Sun through a house window](docs/screenshots/house.jpg) |
| ![The hall of a keep](docs/screenshots/keep_hall.jpg) | ![A house the player built](docs/screenshots/player_house.jpg) |

### Water, weather and night

| | |
|---|---|
| ![A cog at anchor on a lake](docs/screenshots/cog.jpg) | ![A cog under way, with its wake](docs/screenshots/cog_wake.jpg) |
| ![Lightning over a town in a storm](docs/screenshots/storm.jpg) | ![Mist in the forest](docs/screenshots/mist.jpg) |
| ![A reef on a lake bed](docs/screenshots/reef.jpg) | ![Under the water](docs/screenshots/underwater.jpg) |
| ![Moonrise](docs/screenshots/moonrise.jpg) | ![A night sky](docs/screenshots/night_sky.jpg) |

### Further out

| | |
|---|---|
| ![A human sci-fi outpost](docs/screenshots/outpost.jpg) | ![Inside an outpost](docs/screenshots/outpost_room.jpg) |
| ![The planet from orbit](docs/screenshots/orbit.jpg) | ![Landed on an alien moon](docs/screenshots/fey_moon.jpg) |

## Features

### An endless, persistent world

- Endless terrain streamed in 64 m chunks on worker threads, with distant land, forests
  and rivers drawn out to the horizon.
- Every chunk is saved the moment it is first generated and only ever loaded after that.
  Your changes (felled trees, mined ore, dug craters, emptied chests, burnt buildings, killed
  animals, trader stock) are written into it within a second.
- Landforms with their own shape: rolling hills, river valleys, high peaks, karst towers,
  rock needles, gorges, crags, badlands, dunes, sinkholes, craters, terraces and lake
  country. Cliffs have ledges, rills and fractures.
- Regional climates and biomes, from temperate woods and meadows to tropical rainforest
  with palms, dry savanna and boreal forest. Each region also rolls its own tree, mushroom,
  rock and undergrowth species, so no two look alike.
- Rivers wind through the lowlands in valleys of their own, and drop over rock lips as
  waterfalls into misty plunge pools. Lakes have reefs, kelp, lily ponds, lake-bed weed and
  shoals of fish.
- Natural trees whose branches taper to twigs, dense meadows with straw blades and seed
  heads, and ground cover that changes with the forest above it.
- Real caves: tunnel networks under the hills, with cave mouths you can walk into.
- Hidden finds: a sword in a stone, a gnome ring that only shows after dark, messages in
  bottles, lost camps and more.

### Human worlds and alien worlds

- Every new game starts on a human world, in medieval land. Human worlds are natural:
  real plants, real animals, normal clothes, and nothing that glows.
- The land levels up as you go outwards (one zone level per 150 m). Enemies get tougher,
  loot gets better and technology moves on, from medieval near spawn to human sci-fi
  outposts a few kilometres out. A map overlay (J) shows creature levels, danger, era,
  zones and landforms.
- Sci-fi gear, guns, power and building pieces unlock from level 10, a launch pad at 30
  and starships at 35.
- **Ancient portals.** Rare rune rings stand only in level 40+ zones. Step through one to
  another world linked to yours, human or alien, and come back out of the same portal.
- Alien worlds are the endgame (zone level 50 and up), with glowing fey wilds, xeno cities,
  alien creatures and alien people.
- **Planets and warp.** Keep climbing at the top of the sky to reach orbit. Every world has
  five linked planets, each with its own land, people and map, saved separately. Warp
  between them from orbit and land wherever you like.

### Towns and people

- Hamlets, villages and walled towns joined by roads that follow the land, with stone
  bridges and viaducts. If you find a road, it leads to people.
- Market squares with stalls and crowds, shops, guild halls, and houses you can buy.
  Traders price goods by where they come from and how much you have already sold them.
- **People driven by AI.** Everyone has a name, job, family, personality, daily routine and
  a lasting memory of you. Families include children and teens. Talk to them in your own
  words through a local model (Ollama, LM Studio and others) or an API (Anthropic, OpenAI,
  OpenRouter), or with built-in dialogue offline. See [docs/AI.md](docs/AI.md).
- **They talk back out loud** with 128 built-in natural voices and regional accents, and
  you can talk to them with your own voice: built-in offline speech-to-text, push to talk
  (B) or an open mic (O) that lets nearby people overhear you.
- No clones: bodies, faces, builds, posture and clothes vary person to person, and clothes
  suit each job.
- Natural animation, with feet that plant on slopes, and ragdoll deaths that stay where
  they fall.
- **Standing with each town.** What you do raises or lowers how a town sees you. It sets
  shop prices, and walled towns watch their gates and shut them at night (a rope gets you
  over the wall).
- Crime and stealth: bounties, witnesses, pickpocketing, sneaking and a lockpicking game.
- Townsfolk fight fires with bucket lines from the well. Bandits and pirates come after
  you, and only you.

### Water, weather and fire

- Lakes and rivers with swell, wind waves, reflections and caustics. Swim, dive and run out
  of breath.
- Boats with crews sail the big lakes: rowboats, cogs and research vessels, each leaving a
  real wake.
- Weather that moves across the land in fronts: rain, snow, hail, storms with lightning,
  mist, dust, named great storms and starfall nights where fallen stars leave craters full
  of scrap. One wind drives the grass, trees, flags, clouds, waves and rain.
- Climate wear: moss on buildings in wet lands, frost and snow pack in the cold, dust in
  dry lands.
- **Spreading fire.** Buildings and trees catch, burn downwind, die out in rain and fall to
  ruins. Light them with torches, fire pots, fire bottles and incendiary grenades; put them
  out with buckets. Arson is a crime.
- Living flames on torches, lanterns and hearths, and cloth flags that blow in the wind.

### Survival, gear and combat

- Health, stamina, oxygen and experience. Each level gives points for Strength,
  Endurance, Agility and Intellect, plus skills such as sneaking, picking pockets and
  locks. Strength sets how much you can carry.
- Hundreds of items, every one with a painted icon and a 3D model made to match it. Gear
  rolls ranks and affixes (grey, green, blue, orange, red, purple), and items keep their
  story ("Mined in Ashford Vale on day 3"), even in a stack.
- Armour and clothes on a paper doll: head, neck, chest, hands, legs and feet.
- Melee weapons, bows and crossbows early on, firearms later, with metal that reads as
  forged iron in medieval lands and polished steel only in sci-fi.
- Mining, chopping, digging, hunting and butchering. Kills leave bodies you can loot or
  skin, and if you die your things wait in a bag where you fell.
- Torches that burn out and flashlights whose batteries fail.
- Strongholds and dungeons: castles, crypts and bunkers with maze-like halls, underground
  levels, simple puzzles and lit treasuries. Treasure maps lead to chests you dig up.
- Wildlife per region, from deer, elk, boar, hares and wild horses to wolves and other
  predators, fully animated, with name, level and loot tags you can read through
  binoculars.

### Build and make

- **Build your own places.** Foundations, floors, timber, stone and alloy walls, doors you
  can lock, windows, stairs and tiled roofs snap to a grid and to the storeys already
  built. Furniture sits level and a red ghost tells you why something won't fit. Your
  buildings weather with the climate over the days.
- Crafting in batches at stations you build: workbench, campfire, forge, anvil,
  fabricator and more, with tabs, search and a "can craft now" filter.
- Storage chests, map markers and waystones that teleport you between your bases.
- **Power and automation.** Windmills, water wheels, solar panels, steam engines and
  generators feed lamps, doors, turrets and traps through cables. Logic wire, sensors,
  gates and relays let you automate them, and belts, hoppers, arms, miners, furnaces,
  sawmills and assemblers run whole workshops.
- **Vehicles.** Build a vehicle bay for a hover speeder or a survey rover, or a stable for
  a riding horse. Set one down from your pack, ride it and pack it up again.
- **Starships.** Build a launch pad (level 30) and a starship on it (level 35). It flies
  where you look and sets down anywhere flat.

### Multiplayer

- Play together on a dedicated server for Linux, Windows or macOS, with chat, alliances
  that share doors and bases, and a server-side option for PvP. See
  [docs/SERVER.md](docs/SERVER.md).

### Looks and settings

- Forward+ rendering: global illumination, volumetric fog and sunbeams through windows,
  SSAO, SSR, PBR photo textures, ACES tonemapping with a gentle film grade, auto-exposure,
  a day and night cycle with moon phases, and clouds that fade into the haze.
- Full graphics settings with Low, Medium, High and Ultra presets, TAA, MSAA and FSR 2.2,
  motion blur and head bob options, and a horizontal FOV slider.
- A live title screen that floats over a slow flight across a generated world.
- Your own body: first-person hands holding your tool or weapon (none when you put it away
  with H), and a third-person view (V) with full animation.
- Xbox, PlayStation and generic controllers, with every action rebindable.
- Windows installer with Start Menu and desktop shortcuts and a clean uninstaller.

## Recommended hardware

NVIDIA RTX 3070 or better, an 8-core desktop CPU, 32 GB RAM, Windows 10/11 64-bit, SSD.
Measured on an RTX 4090 at 2560x1440 on the High preset (v0.3.49): about 80 FPS in a
town and 105 FPS in a forest in clear weather.

## Controls

All bindings can be changed in Settings > Controls, for keyboard and controller.
Controllers use ARK: Survival Ascended's layout.

| Action | Keyboard and mouse | Controller |
|---|---|---|
| Move / look | WASD / mouse | Left stick / right stick |
| Sprint / crouch / jump | Shift / Ctrl / Space | Left stick click / right stick click / A |
| Swim: dive / rise | Look down and move, or Ctrl / Space | Look down and move, or right stick click / A |
| Use tool or weapon | Left mouse | RT |
| Reload (with a gun or bow in hand) | R | |
| Interact, open, talk, trade (prompt floats over it) | E | Y |
| Eat | F | X |
| Torch or flashlight on / off | T | |
| Put away what you hold | H | |
| Inventory (drag items onto the hotbar) | Tab | B |
| Crafting / Character / Atlas | R / K / M | D-pad up / D-pad down / View |
| Map overlay / minimap zoom | J / N | |
| Hotbar | 1 to 0, mouse wheel | D-pad left/right; hold LB + Y, B, X, A, D-pad for slots 1 to 8 |
| Talk with your voice: hold to speak / open mic | B / O | |
| Chat (on a server) | Enter | |
| Free / lock the mouse pointer | Alt | |
| Turn a building piece (Shift + Q turns it back) | Q | RB |
| Raise / lower a building piece | X / Z | D-pad up / D-pad down (while holding a piece) |
| Grid snap on / off (free placement) | G | X (while holding a piece) |
| Take down a piece you built (returns it) | Hold E | Hold Y |
| Set down a vehicle from the hotbar | Left mouse | RT |
| Ride a vehicle / get off | E | Y |
| Pack a vehicle up (returns it) | Hold E | Hold Y |
| Drive / steer / boost (while riding) | W S / A D / Shift | Left stick / L3 |
| Fly a starship: thrust / climb / descend | W / Space / Ctrl, steer by looking | Left stick up / A / right stick click |
| Leave for orbit | Hold Space at the top of the sky | Hold A |
| First / third person | V | |
| Pause and settings | Esc | Menu |
| Cheat console (fly, noclip, god, speed, give, tp, xp, level, weather; type help) | ` | |
| Screenshot / FPS counter | F12 / F3 | |

## Install

Download `ProceduralWorld-<version>-Setup.exe` from the Releases page and run it, or use the
portable zip or the Linux tarball. The installer's optional "Talk with your voice" part adds
the offline speech model. Saved worlds live in `%APPDATA%\ProceduralWorld`.

## Build from source

1. Install [Godot 4.5.1](https://godotengine.org/download) and its export templates.
2. Open the folder in Godot and press Play, or run `godot --path .`.
3. Tests: `godot --headless --path . --script res://tests/run_tests.gd`
4. Windows/Linux builds and the installer (needs NSIS): `./tools/build.sh`
5. Screenshot tour: `godot --path . res://src/world/world.tscn -- --capture --seed=4242`
   (add `--shots=01,44` for some shots only, `--hud=none` to hide the HUD,
   `--weather=storm` for weather)
6. Title-screen shots: `godot --path . -- --capture-menu`

## Layout

```
docs/            design spec, roadmap, AI and server guides
src/core/        hashing, global game state, saving, stats, standing, crime
src/world/       world field, chunk generation and streaming, terrain, towns, buildings,
                 caves, dungeons, power, fire, shaders
src/env/         sky, sun, clouds, weather, climate, water, fog
src/persistence/ on-disk world store
src/items/       item definitions, inventory, recipes, storage
src/economy/     trader pricing and stock
src/npc/         people: generation, routines, dialogue, clothing
src/fauna/       wildlife, corpses
src/anim/        animation, IK and ragdolls
src/ai/          AI dialogue providers, voices, speech-to-text
src/net/         multiplayer and dedicated server
src/player/      first-person controller, held items, builder
src/vehicles/    vehicles, boats, and the manager that keeps them in the world
src/space/       the star system, orbit view and warp
src/audio/       sound, ambience and music
src/ui/          HUD, menus, settings, maps
tests/           headless test suite
installer/       NSIS Windows installer
tools/           build script, screenshot tour, preview and asset tools
```

## License

MIT. See [LICENSE](LICENSE). Models in `assets/models` are by Quaternius and Kenney, released
under CC0 (the starship is from Quaternius' Ultimate Spaceships Pack) (see
[assets/models/LICENSE-CC0.txt](assets/models/LICENSE-CC0.txt)). The built-in voices and
speech model have their own licences, listed in `tools/voice_server/LICENSES.txt`.
