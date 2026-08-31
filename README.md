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
    world/HouseBuilder.luau          procedural greybox from HouseConfig
  client/
    init.client.luau + controllers/  Hud · Notifications · Scrapbook · CosmeticMenu · GhostStory
tests/           TestEZ specs for pure logic
```

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

## Verification

Headless checks (no Studio needed):

```sh
rojo build default.project.json -o build.rbxlx   # whole tree resolves & builds
stylua --check src tests                          # formatting
selene src tests                                  # lint / undefined globals
```

Logic tests (TestEZ, run in Studio): add [TestEZ](https://github.com/Roblox/testez) to a
`Packages` folder and point a runner at `tests/`. The specs cover the progression math
(`RankConfig`), the no-immediate-repeat selection (`RandomUtil`), and config integrity.

Manual smoke test (the GDD §18 success test): press Play solo and confirm the greybox house
appears, NPCs spawn, the round loop advances, Pillow Fight and Parent Check are playable, a
chaos event fires, and stars/scrapbook update in the HUD.

## Monetization note

Cosmetics only — nothing affects gameplay power (GDD §12). Robux product/game-pass ids in
`CosmeticConfig` are **placeholder `0`**; wire real Creator-Dashboard ids before enabling
purchases. Data persists via DataStores; in Studio without API access the game falls back to an
in-memory store so it stays fully playable offline.
