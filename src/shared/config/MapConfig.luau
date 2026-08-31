--!strict
-- MapConfig — the registry of playable houses.
--
-- A map is either PROCEDURAL (HouseBuilder emits it from HouseConfig) or a MODEL. There are two
-- places a model can live, and which one you use depends on how you got it:
--
--   ServerStorage.ToolboxHouses   Studio drops. Insert straight from the Toolbox into this
--                                 folder and save the place. NOT Rojo-managed, so it survives
--                                 syncs -- but it lives in the .rbxl, not in git.
--   ServerStorage.HouseModels     Rojo-managed, synced from assets/approved-imports/houses/.
--                                 Version controlled. Anything here that is not on disk gets
--                                 DELETED on the next sync, so never drop a Toolbox model in here.
--
-- HouseLoader checks ToolboxHouses first, then HouseModels, so you can prototype with a Toolbox
-- insert and later export it to assets/ without touching config.
--
-- ── Why a model needs almost nothing from us ────────────────────────────────────────────────
-- Gameplay never inspects geometry. Hide & Seek asks CollectionService for SC_HidingSpot,
-- Midnight Snack asks for SC_SnackSource, Parent Check asks for SC_BedZone, and every activity
-- finds its staging point via SC_ActivityAnchor. So an imported house does not have to match any
-- particular layout, room count, or naming scheme. It only has to declare which of its parts
-- play which role — and that is what `annotations` below is.
--
-- ── Two ways to point at something: `path` and `at` ─────────────────────────────────────────
-- `path` is slash-separated from the model root, e.g. "Interior/Bedroom/Bed_01". It is the nicer
-- option and the one to use for a well-authored model.
--
-- It is also useless for most real Toolbox houses. Every candidate surveyed for this project was
-- a flat soup of instances literally named "Part" — one of them had ZERO meaningfully-named
-- descendants out of 111. There is nothing to write a path to.
--
-- So a ref can instead give `at = {x, y, z}`, a POSITION in the house's own frame:
--
--     X, Z   offset from the model's bounding-box centre
--     Y      height above the model's base (its lowest point)
--
-- HouseLoader drops an invisible marker there and tags that. Positions beat paths for imported
-- houses on three counts: they survive renaming, they survive swapping one wardrobe mesh for a
-- different one, and they can mark a place that is not any single part — the corner behind a
-- sofa, the middle of a rug, the spot where a hiding prop is *going* to be placed.
--
-- Measure them once against the model and they stay correct however the house is moved.

export type PathRef = string
export type Vec3 = { number } -- {x, y, z}

-- Anywhere a location is needed, either form works:
--   "Interior/Kitchen/Island"          a path, as a plain string
--   { path = "Interior/Kitchen" }      the same thing, spelled out
--   { at = {12, 6, -4} }               a position in the house frame
--   { at = {12, 6, -4}, size = {8, 6, 8} }   ... with an explicit trigger volume
export type PlaceRef = PathRef | {
	path: PathRef?,
	at: Vec3?,
	size: Vec3?, -- marker volume for `at` refs; defaults to 6x6x6
}

export type RoomRef = {
	path: PathRef?,
	at: Vec3?,
	size: Vec3?,
	displayName: string,
	secret: boolean?, -- hidden until an event opens it (the attic)
}

export type AnchorRef = {
	path: PathRef?,
	at: Vec3?,
	size: Vec3?,
	activity: string, -- PillowFight | ParentCheck | MidnightSnack | HideAndSeek | GhostStory
	-- | PizzaDisaster | StrangeNoise
	kind: string?, -- "main" (default), "gather", "door", "seeker"
}

export type HidingSpotRef = {
	path: PathRef?,
	at: Vec3?,
	size: Vec3?,
	label: string, -- shown on the prompt and in announcements: "In the pantry"
}

export type SnackSourceRef = {
	path: PathRef?,
	at: Vec3?,
	size: Vec3?,
	snack: string, -- "Chips", "Cookies", ...
}

-- A prop cloned out of ServerStorage.FurnitureModels and placed in the house.
--
-- This is how the curated asset kit becomes gameplay. An imported house arrives unfurnished, so
-- there is no existing bed to tag as a bed zone and no pantry to hide in — the prop and its
-- gameplay role arrive together, here.
export type FurnitureRef = {
	model: string, -- child name in ServerStorage.FurnitureModels
	at: Vec3,
	yaw: number?, -- degrees, clockwise
	role: string?, -- "HidingSpot" | "SnackSource" | "BedZone" | "Light" | "Anchor" | nil
	label: string?, -- HidingSpot prompt text
	snack: string?, -- SnackSource kind
	activity: string?, -- Anchor: which activity
	kind: string?, -- Anchor: "main" | "gather" | ...
}

export type Annotations = {
	rooms: { RoomRef }?,
	spawns: { PlaceRef }?, -- SpawnLocations, or plain parts/positions we convert into one
	anchors: { AnchorRef }?,
	hidingSpots: { HidingSpotRef }?,
	snackSources: { SnackSourceRef }?,
	bedZones: { PlaceRef }?,
	lights: { PlaceRef }?, -- anything Power Outage should switch off
	atticHatch: PlaceRef?, -- the panel Strange Noise swings open
	atticLadder: PlaceRef?, -- revealed with it
	furniture: { FurnitureRef }?, -- props placed from ServerStorage.FurnitureModels
}

export type MapDef = {
	id: string,
	displayName: string,
	source: "Procedural" | "Model",
	model: string?, -- child name in ToolboxHouses or HouseModels, for source = "Model"
	annotations: Annotations?,
	-- Toolbox models are a well-known vector for backdoor scripts, so HouseLoader strips every
	-- Script/LocalScript/ModuleScript out of a cloned house by default and reports the count.
	-- A house is geometry; it should not need code. Only set this if you have read them.
	allowScripts: boolean?,
}

local MapConfig = {
	-- Which map the session loads. Change this to play a different house.
	--
	-- Safe to point at a model that is not present: HouseLoader falls back to the procedural
	-- Greybox house and says so, rather than booting into an empty world.
	default = "GeoHomes",

	maps = {
		{
			id = "Greybox",
			displayName = "Greybox House",
			source = "Procedural",
			-- No annotations: HouseBuilder tags everything as it builds.
		},

		{
			id = "GeoHomes",
			displayName = "Geo Homes House",
			source = "Model",
			-- Currently a Toolbox insert in ServerStorage.ToolboxHouses. Save it to
			-- assets/approved-imports/houses/ to get it into git under the same name.
			model = "Geo Homes House",

			-- Every position below was MEASURED, not guessed. The standable volume of each storey
			-- was flood-filled, then each room's point was chosen as its furthest-from-any-wall
			-- cell rather than its centroid — the great room is L-shaped, and its centroid lands
			-- inside a support column. Each was then re-checked against a 4x5x4 clearance box
			-- (an avatar plus elbow room) with floor below and ceiling above.
			--
			-- Storeys are 12 studs: ground floor at y=+6, upper at y=+18.
			annotations = {
				rooms = {
					{ at = { -4, 6, 22 }, size = { 40, 10, 64 }, displayName = "Living Room" },
					{ at = { 22, 6, -16 }, size = { 22, 10, 24 }, displayName = "Garage" },
					{ at = { 24, 6, 34 }, size = { 16, 10, 38 }, displayName = "Den" },
					{ at = { -2, 18, 0 }, size = { 32, 10, 28 }, displayName = "Landing" },
					{ at = { -20, 18, 24 }, size = { 16, 10, 20 }, displayName = "Bedroom" },
					{ at = { 24, 18, 24 }, size = { 16, 10, 30 }, displayName = "Guest Room" },
					{ at = { 24, 18, -12 }, size = { 16, 10, 18 }, displayName = "Bathroom" },
				},

				-- Spread across the ground-floor living space so four players do not stack.
				spawns = {
					{ at = { -14, 6, 4 } },
					{ at = { -14, 6, 16 } },
					{ at = { -4, 6, 16 } },
					{ at = { -4, 6, 26 } },
				},

				anchors = {
					-- The great room is the social space: pillow fights and ghost stories both
					-- stage here. This is its most open point, with 10 studs of clearance.
					{ at = { -4, 6, 22 }, activity = "PillowFight" },
					{ at = { -4, 6, 22 }, activity = "GhostStory", kind = "gather" },
					{ at = { -4, 6, 22 }, activity = "Movie", kind = "gather" },
					-- Kitchen end of the same open plan. Close to the pillow anchor because it
					-- IS the same room; what actually locates the raid is where the snack
					-- sources get placed, on the counters.
					{ at = { -8, 6, 28 }, activity = "MidnightSnack" },
					{ at = { -20, 18, 24 }, activity = "ParentCheck" },
					{ at = { -2, 18, 0 }, activity = "HideAndSeek", kind = "seeker" },
					-- The front entry is a 76 st^2 vestibule with only 2 studs of clearance, so
					-- it fails the 4-stud check. That is fine: a door anchor is a marker for
					-- where the pizza arrives, not a place anyone has to stand.
					{ at = { -10, 6, -26 }, activity = "PizzaDisaster", kind = "door" },
				},

				-- Hiding spots, snack sources and bed zones are deliberately absent: this house
				-- ships unfurnished, so there is nothing yet to tag. They arrive with the props,
				-- through `furniture` below. HouseLoader will warn about each missing category at
				-- startup until then, which is the intended signal rather than a bug.
				furniture = {},
			},
		},

		-- ── Drop-in template ────────────────────────────────────────────────────────────────
		-- Copy this, set `model` to your file's name, fill in the refs, and point `default`
		-- at its id. Every field is optional except id/displayName/source/model, so you can
		-- wire one activity at a time and check it in Studio as you go.
		--
		-- {
		-- 	id = "CozyCottage",
		-- 	displayName = "Cozy Cottage",
		-- 	source = "Model",
		-- 	model = "CozyCottage",
		-- 	annotations = {
		-- 		rooms = {
		-- 			{ path = "Interior/LivingRoom", displayName = "Living Room" },
		-- 			{ at = { 0, 26, 0 }, size = { 20, 8, 20 }, displayName = "Attic",
		-- 			  secret = true },
		-- 		},
		-- 		spawns = { "Spawns/A", { at = { -6, 0, 4 } } },
		-- 		anchors = {
		-- 			{ path = "Interior/LivingRoom/Rug", activity = "PillowFight" },
		-- 			{ at = { 0, 0, 12 }, activity = "MidnightSnack" },
		-- 		},
		-- 		hidingSpots = {
		-- 			{ path = "Interior/Kitchen/Pantry", label = "In the pantry" },
		-- 			{ at = { 8, 0, -4 }, size = { 5, 7, 5 }, label = "Behind the curtains" },
		-- 		},
		-- 		snackSources = {
		-- 			{ path = "Interior/Kitchen/Bowl_01", snack = "Chips" },
		-- 		},
		-- 		bedZones = { "Interior/Bedroom/Bed_01/Mattress" },
		-- 		lights = { "Interior/LivingRoom/Lamp" },
		-- 		atticHatch = { at = { 0, 12, 0 } },
		-- 		atticLadder = { at = { 0, 8, 2 } },
		-- 		furniture = {
		-- 			{ model = "Wardrobe", at = { -10, 0, 6 }, yaw = 90,
		-- 			  role = "HidingSpot", label = "In the closet" },
		-- 			{ model = "ChipBowl", at = { 2, 3, 12 }, role = "SnackSource",
		-- 			  snack = "Chips" },
		-- 			{ model = "FloorLamp", at = { -14, 0, 2 }, role = "Light" },
		-- 		},
		-- 	},
		-- },
	} :: { MapDef },
}

function MapConfig.get(id: string): MapDef?
	for _, map in MapConfig.maps do
		if map.id == id then
			return map
		end
	end
	return nil
end

return MapConfig
