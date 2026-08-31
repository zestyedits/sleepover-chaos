# House models

Drop a house here as **`YourHouse.rbxmx`** (or `.rbxm`). Rojo syncs this folder to
`ServerStorage/HouseModels`, so the file name becomes the model name.

```
assets/houses/CozyCottage.rbxmx   ->   ServerStorage.HouseModels.CozyCottage
```

Then add an entry to [`src/shared/config/MapConfig.luau`](../../src/shared/config/MapConfig.luau)
and point `MapConfig.default` at its `id`. There's a commented template in that file to copy.

## The only thing a house has to do

**Nothing structural.** Gameplay never inspects geometry — it asks CollectionService for tags.
So the house can have any layout, any room count, any naming scheme, any number of floors. It
just has to tell us which of its parts play which role, and that's data in `MapConfig`, not code.

| What the game needs | Why | Without it |
| --- | --- | --- |
| `spawns` | where players arrive | players fall out of the world |
| `anchors` | where each activity stages itself | activities fall back to a default position |
| `hidingSpots` (4+) | Hide & Seek, Parent Check | Hide & Seek has nothing to hide behind |
| `snackSources` (3+) | Midnight Snack | the raid can't be completed |
| `bedZones` | Parent Check, Morning | "get in bed" can't be satisfied |
| `lights` | Power Outage | the blackout doesn't darken anything |
| `rooms` | labels, and the secret-area flag | cosmetic only |
| `atticHatch` / `atticLadder` | Strange Noise | the attic stays sealed |

Only `spawns` is truly required. Everything else degrades to "that activity is less good"
rather than "the game breaks" — so you can wire one activity at a time and test as you go.

## Paths

Every `path` is slash-separated from the model root:

```lua
{ path = "Interior/Bedroom/Bed_01/Mattress", label = "Under the bed" }
```

`HouseLoader` resolves each with `FindFirstChild` and **warns on startup** for anything it can't
find, then prints a summary:

```
[HouseLoader] "CozyCottage" ready: 4 spawns, 5 hiding spots, 4 snacks, 3 beds, 0 problem(s)
```

If a path points at a `Model` rather than a `BasePart`, the loader uses its `PrimaryPart`, or the
first `BasePart` inside it. So you can usually point at whole props (`Bed_01`) instead of hunting
for the exact part.

## Picking a model

Things that make a house work well here, roughly in order:

1. **Enclosed interior with a roof.** Open-plan showcase builds leak skylight and wreck the
   night-time lighting.
2. **Doorways wide enough to path through.** NPC guests use `PathfindingService` with an agent
   radius of 2, so anything under ~5 studs wide will jam them.
3. **Distinct hideable props** — a wardrobe, a pantry, a tub, curtains, a bed with a gap under
   it. These are what Hide & Seek is actually made of.
4. **Two storeys with real stairs** rather than a teleporter, so the house reads as one
   continuous space.
5. **Reasonable part count.** Under ~3000 parts keeps Studio responsive during playtests.

Interiors are meant to be edited. The annotation layer means you can move furniture around
freely and only need to touch `MapConfig` if you *rename or delete* something a path points at.

## Multiple houses

`MapConfig.maps` is a list, so several houses can coexist. Keep `Greybox` — it's the procedural
fallback, and `HouseLoader` drops back to it if a model is missing or its name is wrong, which
keeps the game bootable while a new house is half-wired.
