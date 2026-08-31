# Sleepover Chaos

A cozy-chaotic Roblox social game: every sleepover becomes a different ridiculous story.
This repo is the **MVP build** — one house, five activities, three chaos events, progression,
a scrapbook, and cosmetics — all driven by one reusable event framework so new content is a
small module plus a config entry.

Built from the v0.1 Game Design Doc. See the doc's pillars (cozy + chaos, always something
happening, random stories, fair monetization) for the "why" behind each system.

## Project layout

Rojo maps three source trees into Roblox services:

| Path | Roblox location | What lives here |
| --- | --- | --- |
| `src/shared` | `ReplicatedStorage/Shared` | framework, configs, types, utils, remotes |
| `src/server` | `ServerScriptService/Server` | authoritative game logic |
| `src/client` | `StarterPlayerScripts/Client` | HUD, notifications, menus (presentation only) |

```
src/
  shared/
    framework/   Lifecycle · ActivityBase · ChaosEventBase   ← the reusable spine (GDD §5)
    config/      Game · House · Activity · Event · Cosmetic · Scrapbook · Rank
    net/Remotes  single source of truth for every RemoteEvent/Function
    util/        Signal · Trove · RandomUtil
    Types · Tags
  server/
    init.server.luau                 boots systems in dependency order
    systems/     GameRoundManager · ActivityManager · EventManager · PlayerDataService
                 · RewardService · NPCManager · InteractionService · CosmeticService
    activities/  PillowFight · ParentCheck · MidnightSnack · HideAndSeek · GhostStory
    chaosevents/ PowerOutage · StrangeNoise · PizzaDisaster
    world/       HouseBuilder (structure) · Props (furniture kit)
  client/
    init.client.luau + controllers/  Hud · Notifications · Scrapbook · CosmeticMenu
                                     · GhostStory · DevPanel (Studio only)
tests/           TestEZ specs for pure logic
```

## The house

One compact two-story house, built procedurally by `HouseBuilder` from `HouseConfig`:

```
GROUND  y=0                    UPPER  y=+14              ATTIC y=+26
+-----------+-----------+      +-----------+-----------+  +---------+
| Living    | Kitchen   |      | Bedroom   | GuestRoom |  | Attic   |
| sofa TV   | counters  |      | beds      | bed       |  | boxes   |
| curtains  | pantry    |      | under-bed |           |  +---------+
+--- Hallway spine -----+      +--- Landing spine -----+   hatch +
| Den       | STAIRS UP |      | Bathroom  | stairwell |   ladder
| closet    |           |      | bathtub   | + railing |
+-----------+-----------+      +-----------+-----------+
     front door / porch                back yard
```

Two things about `HouseConfig` are worth knowing before editing it:

- **Rooms do not imply walls.** Walls are their own list, authored with explicit `openings`. A
  room rectangle cannot express a doorway, which is why the earlier single-floor version had to
  use half-height walls and gaps between disconnected rectangles.
- **Gameplay roles ride on furniture.** A hiding spot is a `hides = "In the pantry"` field on an
  actual pantry prop; snack sources and bed zones work the same way. There is no separate list of
  floating trigger cubes to keep in sync with the props.

## The event framework (start here)

`src/shared/framework/Lifecycle.luau` runs **every** activity and chaos event through one
phased lifecycle (GDD §5):

```
notify → countdown → begin(onStart) → run(onUpdate + checkWin until win OR timer)
       → results(onFinish) → rewards → cleanup(onCleanup) → reset
```

- Activities extend `ActivityBase`; chaos events extend `ChaosEventBase`. Each is ~one screen
  of code — the framework owns the loop, the run context, scoring, and guaranteed cleanup.
- `ActivityManager` / `EventManager` own the pools and drive the runs. Individual
  activities never control the whole game (GDD §14).
- Adding content = new module in `activities/` or `chaosevents/` + one entry in
  `ActivityConfig` / `EventConfig`. No manager changes.

Everything happens inside the one procedurally-built house (`HouseBuilder`) — no teleporting
into obbies (GDD §17).

## Getting started (Roblox Studio)

1. Install the tooling (pinned in `rokit.toml`):
   ```sh
   # via Rokit (https://github.com/rojo-rbx/rokit)
   rokit install
   # or via cargo
   cargo install rojo stylua selene
   ```
2. Serve to Studio with the Rojo plugin, or build a place file:
   ```sh
   rojo serve            # live-sync into Studio via the Rojo plugin
   rojo build -o SleepoverChaos.rbxlx
   ```
3. Press **Play**. You'll spawn in the living room; NPC guests fill the party; the round loop
   cycles Arrive → Activity → Free Time → Random Event → Activity → Late-Night Chaos → Morning.

## Rojo → Studio sync

**The plugin and the CLI must be the same version.** They are not merely "compatible if close":
7.7.0 changed the handshake wire format from JSON to msgpack, so a 7.7.0 plugin talking to a
7.4.x server decodes the JSON body's first byte `{` (`0x7B`) as a msgpack positive fixint, gets
the number `123` back instead of a table, and dies on the next line:

```
ApiContext:28: attempt to index number with 'protocolVersion'
... function rejectWrongProtocolVersion
```

That error looks like a network or firewall problem and is not one — the bytes arrived fine, the
plugin just could not parse them. A firewall block produces a *connection* error, never a decode
error.

Keep them in lockstep by installing the plugin **from the pinned CLI**, which writes
`%LOCALAPPDATA%/Roblox/Plugins/RojoManagedPlugin.rbxm`:

```sh
rokit install          # gets the CLI version pinned in rokit.toml
rojo plugin install    # writes the MATCHING plugin, overwriting any other version
```

Restart Studio afterwards, so the newly written plugin file is the one actually loaded.

Then, from the repo root:

```sh
rojo serve default.project.json     # listens on localhost:34872
```

and press **Connect** in the Rojo plugin. Confirm the server is healthy independently of Studio
with `curl -i http://localhost:34872/api/rojo` — a 200 with `content-type: application/msgpack`
is a working 7.7.0 server.

After connecting, these three roots must exist *before* you press Play:

| Roblox location | Source |
| --- | --- |
| `ReplicatedStorage/Shared` | `src/shared` |
| `ServerScriptService/Server` | `src/server` |
| `StarterPlayer/StarterPlayerScripts/Client` | `src/client` |

`rojo sourcemap default.project.json` prints the same tree from the CLI side, which is the quick
way to tell a *project mapping* problem apart from a *connection* problem.

In Studio a **dev panel** appears on the left with buttons to force-run a specific activity or
chaos event. Waiting for weighted-random to pick the one you want costs minutes per attempt, so
use the panel when iterating. It is hidden outside Studio, and both `DevRunActivity` and
`DevRunEvent` are re-checked against `RunService:IsStudio()` on the server.

## Verification

Headless checks (no Studio needed) — all three must be clean:

```sh
rojo build default.project.json -o build.rbxlx   # whole tree resolves & builds
stylua --check src tests                          # formatting
selene src tests                                  # lint / undefined globals
```

`.gitattributes` pins `eol=lf` because `stylua.toml` sets `line_endings = "Unix"`; without it a
Windows checkout under `core.autocrlf=true` fails the format check on every file. `testez.yml`
is a selene std shim so the TestEZ globals in `tests/` are not reported as undefined.

Logic tests (TestEZ, run in Studio): add [TestEZ](https://github.com/Roblox/testez) to a
`Packages` folder and point a runner at `tests/`. The specs cover the progression math
(`RankConfig`), the no-immediate-repeat selection (`RandomUtil`), config integrity, and the house
geometry (`HouseConfig.spec` — non-overlapping rooms, doorways inside their wall runs, props
inside their rooms, stairs landing flush on a floor, the hatch covering the attic opening).

Manual smoke test (the GDD §18 success test): press Play solo and confirm the house appears,
NPCs spawn and stay on the floor, the round loop advances, Pillow Fight and Parent Check are
playable, a chaos event fires, and stars/scrapbook update in the HUD. Walk ground → upstairs →
attic: the hatch stays sealed until Strange Noise fires.

## Monetization note

Cosmetics only — nothing affects gameplay power (GDD §12). Robux product/game-pass ids in
`CosmeticConfig` are **placeholder `0`**; wire real Creator-Dashboard ids before enabling
purchases. Data persists via DataStores; in Studio without API access the game falls back to an
in-memory store so it stays fully playable offline.
