# Asset manifest

The record of every model that is allowed into the game, and the contract each one has to meet.

Nothing gets used because it looked nice in the Toolbox. It gets used because there is a row for it
here saying what room it lives in, how big it is, whether you can walk through it, and which piece of
gameplay breaks if it goes missing.

---

## 1. Where things live

| Folder | In git? | Synced to Studio? | What goes here |
| --- | --- | --- | --- |
| `assets/reference-houses/` | no | **no** | Whole houses kept for inspiration or as a layout base. Look at them, steal ideas, don't ship them. |
| `assets/furniture-source/` | no | **no** | Original packs, exactly as downloaded. The 200-piece bundle you took four chairs out of. |
| `assets/texture-materials/` | no | **no** | Source textures, `.png`/`.psd`, material sphere exports. |
| `assets/approved-imports/houses/` | **yes** | `ServerStorage.HouseModels` | Curated, game-ready houses. |
| `assets/approved-imports/furniture/` | **yes** | `ServerStorage.FurnitureModels` | Curated, game-ready props. One file per prop. |

The split is enforced, not just documented — `.gitignore` ignores the three raw folders and
re-includes `assets/approved-imports/**/*.rbxm{,x}`. Drop a pack in `furniture-source/` and git will
not offer to commit it. Promote a prop to `approved-imports/` and it commits normally.

> The blanket `*.rbxm` / `*.rbxmx` rules that keep Rojo build output out of git were also quietly
> eating everything in `assets/`. That's fixed; approved imports are re-included explicitly.

**There is a third place, and it is not in git at all:** `ServerStorage.ToolboxHouses`, created at
runtime, for models inserted straight from the Toolbox in Studio. It lives in the `.rbxl`. Fine for
prototyping, invisible to everyone else on the project. Anything that survives evaluation should be
saved to file and moved into `approved-imports/`.

## 2. Intake workflow

1. Drop the raw pack in `furniture-source/`. Keep the whole thing; don't pre-trim it.
2. Insert it in Studio **into `ServerStorage`, not `Workspace`**, and look at it.
3. Pull out only the pieces that fill a slot in §7. Everything else stays in the pack.
4. Run each keeper through the checklist in §6.
5. Right-click → *Save to File* → `assets/approved-imports/furniture/<Name>.rbxm`. One prop per file.
6. Add its row to §7 with the source and licence filled in. **No row, no import.**

Step 3 is the one that matters. A 200-piece pack imported wholesale costs part count, load time and
memory forever, in exchange for 190 props nobody placed.

## 3. What every approved asset records

| Field | Why it exists |
| --- | --- |
| **Source** | Toolbox asset ID, or the marketplace/pack name. Needed to re-download or to answer "where did this come from". |
| **Creator / Licence** | Toolbox models carry a real licence. Record the creator; flag anything not free-to-use. |
| **Room** | Where it belongs. Also tells you which map annotation needs updating if it moves. |
| **Scale** | Target bounding box in studs, W×H×D. See §4. |
| **Collision** | One of the policies in §5. |
| **Gameplay role** | The tag it carries and the system that reads it. Blank means pure decoration. |

## 4. Scale reference

**One Roblox stud ≈ one foot. An R6 avatar is 5 studs tall and 2 wide.** That is the only ruler that
matters — a prop that looks right next to a real character is right, regardless of what the pack
author intended.

Free models arrive at wildly different scales. Check before approving:

| Landmark | Height (studs) |
| --- | --- |
| Avatar total | 5.0 |
| Eye line | 4.5 |
| Counter / table top | 3.0 |
| Seat height | 1.7 |
| Doorway clear opening | 7 tall × **5 wide minimum** |

That 5-stud doorway minimum is not aesthetic. `NPCManager` pathfinds with `AgentRadius = 2`, so
anything narrower wedges every guest in the house.

## 5. Collision policies

| Policy | Meaning | Applies to |
| --- | --- | --- |
| `Solid` | `CanCollide = true` on the whole prop. Blocks movement and pathfinding. | Wardrobes, fridges, counters, walls |
| `Walkable` | Collidable but low or flat enough to stand on or step over. | Rugs (flat), low platforms, mattresses |
| `Pass-through` | `CanCollide = false`. Purely visual. | Curtains, wall art, string lights, plants |
| `Shell` | Visible mesh solid, plus an **invisible non-collidable trigger part inside** the cavity. | Every hiding spot — see §6 |

Everything is `Anchored = true`. An unanchored prop falls through the floor on load, gets shoved
around during Pillow Fight, and desyncs. Free models are frequently shipped unanchored, so this is a
per-import check, not an assumption.

## 6. The hiding-furniture contract

Hiding spots are the one category with a real structural requirement, because
`HideAndSeek` and `ParentCheck` both put a player *inside* the prop.

- The visible mesh is `Solid`.
- Inside it sits a `Trigger` part: `CanCollide = false`, `Transparency = 1`, tagged
  `SC_HidingSpot` + `SC_Interactable`, with a `Label` attribute (`"In the pantry"`).
- The cavity must be **at least 3×5×3 studs** so an avatar fits without clipping through a wall.
- The prop needs a readable *closed* silhouette. "Behind the curtains" only works if the curtains
  read as something you could be behind from across the room.

Five spots is the target, and they should be five *different* verbs — under, inside, behind, in,
beneath. Five wardrobes in five rooms is one hiding spot repeated.

## 7. The MVP kit

Ordered by what breaks without it. **P0 is navigation, hiding, snacks, the attic, and the social
spaces.** Decoration density is deliberately not addressed yet — an under-furnished house that plays
correctly beats a dressed set that jams pathfinding.

Status: `TODO` needed, no candidate · `SOURCED` candidate found, not vetted · `APPROVED` in
`approved-imports/`, row complete.

### P0 — hiding (Hide & Seek, Parent Check)

Five distinct verbs. This is the single highest-value group: Hide & Seek is currently played against
greybox cubes.

| Slot | Room | Scale W×H×D | Collision | Tag / role | Status | Source · Licence |
| --- | --- | --- | --- | --- | --- | --- |
| Wardrobe / closet | Bedroom | 8 × 11 × 4 | `Shell` | `SC_HidingSpot` "In the closet" | TODO | |
| Bed with under-gap | Bedroom | 7 × 3 × 14 | `Shell` | `SC_HidingSpot` "Under the bed" + `SC_BedZone` | TODO | |
| Pantry / tall cupboard | Kitchen | 7 × 12 × 4 | `Shell` | `SC_HidingSpot` "In the pantry" | TODO | |
| Curtains | Living room | 8 × 11 × 0.5 | `Shell` | `SC_HidingSpot` "Behind the curtains" | TODO | |
| Laundry basket / hamper | Bathroom | 4 × 4 × 4 | `Shell` | `SC_HidingSpot` "In the laundry basket" | TODO | |
| Shower curtain + tub | Bathroom | 6 × 8 × 12 | `Shell` | `SC_HidingSpot` "Behind the shower curtain" | TODO | |

### P0 — snack interaction (Midnight Snack)

Needs four reachable sources on a kitchen counter run, at ~3 studs so the prompt sits at eye level.

| Slot | Room | Scale W×H×D | Collision | Tag / role | Status | Source · Licence |
| --- | --- | --- | --- | --- | --- | --- |
| Counter run | Kitchen | 12 × 4 × 3 | `Solid` | surface for snacks | TODO | |
| Fridge | Kitchen | 5 × 10 × 4 | `Solid` | `SC_SnackSource` "Soda" | TODO | |
| Snack bowl (chips) | Kitchen | 3 × 1.5 × 3 | `Pass-through` | `SC_SnackSource` "Chips" | TODO | |
| Cookie jar | Kitchen | 2 × 3 × 2 | `Pass-through` | `SC_SnackSource` "Cookies" | TODO | |
| Popcorn bowl | Kitchen | 3 × 2 × 3 | `Pass-through` | `SC_SnackSource` "Popcorn" | TODO | |

### P0 — social spaces (Pillow Fight, Ghost Story, Movie)

The rug is load-bearing: it is the Pillow Fight and Ghost Story anchor, and the thing that tells
players "the game happens here".

| Slot | Room | Scale W×H×D | Collision | Tag / role | Status | Source · Licence |
| --- | --- | --- | --- | --- | --- | --- |
| Large round rug | Living room | 15 × 0.1 × 15 | `Walkable` | `SC_ActivityAnchor` PillowFight + GhostStory | TODO | |
| Sofa | Living room | 13 × 5 × 6 | `Solid` | seating | TODO | |
| Beanbags ×3 | Living room | 5 × 3 × 5 | `Solid` | seating, scatter-friendly | TODO | |
| TV or projector screen | Living room | 14 × 9 × 0.5 | `Solid` | `SC_HouseLight` (Power Outage kills it) | TODO | |
| Sleeping bags ×4 | Living room | 4 × 1 × 9 | `Walkable` | `SC_BedZone` for the floor sleepers | TODO | |
| Floor lamp | Living room | 2 × 9 × 2 | `Solid` | `SC_HouseLight` — warm key light | TODO | |

### P0 — attic (Strange Noise)

**Currently blocked.** See §8 — none of the candidate houses has attic volume, so this group needs
built geometry before props matter.

| Slot | Room | Scale W×H×D | Collision | Tag / role | Status | Source · Licence |
| --- | --- | --- | --- | --- | --- | --- |
| Hatch panel | Landing ceiling | 6 × 0.5 × 6 | `Solid` | `SC_AtticHatch` + `SC_Door` | TODO | |
| Ladder | Landing | 3 × 12 × 1 | `Solid` (truss) | `SC_AtticLadder` | TODO | |
| Cardboard boxes ×4 | Attic | 5 × 4 × 5 | `Solid` | dressing + sightline blockers | TODO | |
| Old lamp | Attic | 2 × 7 × 2 | `Solid` | `SC_HouseLight` — the one light up there | TODO | |

### P1 — bedroom and dressing

Wanted for the cozy read, but nothing breaks without them.

| Slot | Room | Scale W×H×D | Collision | Tag / role | Status | Source · Licence |
| --- | --- | --- | --- | --- | --- | --- |
| Vanity + mirror | Bedroom | 6 × 9 × 2.5 | `Solid` | decoration | TODO | |
| Desk + chair | Bedroom | 7 × 4 × 3 | `Solid` | decoration | TODO | |
| Nightstand + lamp | Bedroom | 3 × 4 × 3 | `Solid` | `SC_HouseLight` | TODO | |
| Dresser | Bedroom | 6 × 5 × 3 | `Solid` | `SC_Contraband` host | TODO | |
| Bookshelf | Den | 6 × 10 × 2 | `Solid` | decoration | TODO | |
| String lights | Living room | — | `Pass-through` | `SC_HouseLight` — cozy fill | TODO | |
| Pedestal sink | Bathroom | 4 × 6 × 3 | `Solid` | decoration | TODO | |
| Toilet | Bathroom | 3 × 4 × 5 | `Solid` | decoration | TODO | |

## 8. Style guide

Warm cream, wood, lavender, soft blue, peach. Low-poly with a readable silhouette — the test is
whether you can name the object from across the room at night with only a lamp on, because that is
the actual lighting the game ships with.

| Role | Colour | RGB |
| --- | --- | --- |
| Walls / cream | warm off-white | `243, 231, 206` |
| Wood, light | oak | `196, 152, 104` |
| Wood, dark | walnut | `146, 106, 70` |
| Fabric, peach | sofa, cushions | `226, 178, 172` |
| Fabric, lavender | bedding, rug | `198, 186, 224` |
| Fabric, soft blue | accents | `168, 196, 216` |
| Lamp light | warm bulb | `255, 168, 92` |

Avoid: chrome, neon, anything photoreal-grey. Cold white PBR kitchens read as an office at night.

## 9. Open blockers

- **No attic in any candidate house.** Geo Homes has 12-stud storeys at y=+6 and +18 and a solid roof
  above — measured 0 st² of enclosed volume at roof level. Strange Noise needs an attic built, or a
  different secret area (basement, garage loft, treehouse) chosen instead.
- **Toolbox models have no usable names.** All four candidates are flat part soups —
  "Two Story Colored" has *zero* meaningfully-named descendants. `MapConfig`'s
  `path = "Interior/Bedroom/Bed_01"` scheme cannot address anything inside them, so annotation needs
  to move to positions or in-place tags.
- **A raw furniture pack is currently sitting in the place file** at `ServerStorage.Furniture`
  ("Furnitore", 133 parts). Per this manifest it belongs in `furniture-source/` as a file, with only
  the curated pieces promoted.
