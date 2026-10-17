# Procedural World dedicated server

Run your own always-on world that friends join from the game's **Join Server** screen.
The server has no window; it runs in a terminal (or as a service) on Linux, Windows or
macOS and keeps the world saved.

## Start it

1. Download the server for your system from the Releases page:
   `ProceduralWorldServer-<version>-linux-x86_64.tar.gz`, `-windows.zip` or `-macos.zip`.
2. Unpack it anywhere.
3. Start it:
   - **Linux:** `./start-server.sh`
   - **Windows:** double-click `start-server.bat`
   - **macOS:** double-click `start-server.command` (the first time, right-click it and
     choose Open, since the server isn't notarized by Apple).
4. The first start writes `server.cfg` and makes the world in `worlds/world`. Stop the
   server (type `stop`), edit `server.cfg`, and start it again.

Players join with the server's address, e.g. `203.0.113.7` or `myhost.example:24600`.
For players outside your home network, forward **UDP port 24600** (or the port you set)
on your router to the computer running the server.

## server.cfg

```ini
[server]
name="Ben's World"
description="Medieval survival, PvP off near spawn."
port=24600
max_players=16
password=""           ; empty = anyone can join
admin_password="..."  ; players type /admin <this> in chat to run server commands
world="world"         ; folder under worlds/
seed=""               ; for a new world: a number or any text; empty = random
data_dir=""           ; where worlds/ lives; empty = beside the server
lan_discovery=true

[options]
time="normal"         ; normal, day (always day), night (always night)
day_minutes=24.0      ; real minutes per game day
pvp=true
xp_mult=1.0
loot_mult=1.0
death_penalty="bag"   ; bag (your pack drops where you fall) or keep
building=true
alliances=true
max_alliance=8

[ai]
provider="off"        ; off, ollama, lmstudio, strata, anthropic, openai, openrouter or custom
base_url=""           ; empty = the provider's usual address
model=""              ; empty = the provider's usual model
api_key=""
max_rpm=30            ; model requests a minute across all players
```

With `[ai]` set, the server's villagers think and talk with that model for every player
whose own game has no AI set up (players with their own keep using theirs).

Flags override the file for one run: `--name= --description= --port= --max-players=
--password= --admin-password= --world= --seed= --data= --config=path --set option=value`.
For example `./start-server.sh --port=25000 --set pvp=off`.

## Commands

Type these in the server's terminal. Admins in game type them in chat after a `/`,
once they have signed in with `/admin <admin_password>`.

| Command | What it does |
|---|---|
| `help` | list commands |
| `status` | name, world, players, options |
| `players` | who is online, where, and their ping |
| `say <text>` | message everyone |
| `kick <name> [reason]` | disconnect a player |
| `ban <name>` / `unban <name>` / `bans` | ban a player (and their address) |
| `save` | save now (it also saves every minute and on stop) |
| `get [option]` / `set <option> <value>` | read or change an option (saved to server.cfg) |
| `name <text>` / `description <text>` | rename the server, change its description |
| `maxplayers <n>` / `password [text or none]` | player limit and join password |
| `stop` | save and shut down |

## Playing together

Each town's people and each patch of wildlife is run by one player's game (whoever got
there first, then the nearest of the others), and everyone else sees them move, talk
and fight as that game says. Animals and townsfolk go after whichever player is
nearest. Edits to the world (building, doors, bags, kills, finds) and to towns (trades,
debts, what people remember) are merged on the server, so two players changing the
same place at once both keep their changes. With `pvp=false` players can't hurt each
other.

## Finding a server

Join Server lists servers on your local network by themselves (servers answer on UDP
port 24599 while `lan_discovery=true`), plus your favourites and the servers you joined
before, each with its description, players, ping and whether it needs a password.
Other players reach a server over the internet by its address (forward the game port,
24600 by default, for UDP).

## Alliances

With `alliances=true`, players found an alliance from Players and alliance on the
pause menu and invite others who are online (up to `max_alliance` members). Allies
can't hurt each other even with PvP on, can open each other's locked doors, see each
other on the map and the minimap, and talk with `/a <message>` in chat. The leader can
remove members or hand over leadership; when the leader leaves, the next member leads.

## What is saved where

Everything lives in `worlds/<world>/` beside the server: the land (`chunks/`), the
people of each town (`people/`), each player's character (`players/`), the world clock
(`world.dat`), alliances (`alliances.dat`) and bans (`bans.dat`). Back up that folder to back up the world. Players
are known by a secret key their game makes, so nobody can take over someone's
character by using their name.

## Running from source

`godot --headless --path . -- --server` runs the server from the project folder; its
data then lives in the game's user folder under `server/`. Two copies of the game on
one computer can join as two players with `-- --identity=second` on one of them.
