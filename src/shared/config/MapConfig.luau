--!strict
-- MapConfig — the registry of playable houses.
--
-- A map is either PROCEDURAL (HouseBuilder emits it from HouseConfig) or a MODEL. There are two
-- places a model can live, and which one you use depends on how you got it:
--
--   ServerStorage.ToolboxHouses   Studio drops. Insert straight from the Toolbox into this
--                                 folder and save the place. NOT Rojo-managed, so it survives
--                                 syncs -- but it lives in the .rbxl, not in git.
--   ServerStorage.HouseModels     Rojo-managed, synced from assets/houses/*.rbxmx. Version
--                                 controlled. Anything here that is not on disk gets DELETED on
--                                 the next sync, so never drop a Toolbox model in here.
--
-- HouseLoader checks ToolboxHouses first, then HouseModels, so you can prototype with a Toolbox
-- insert and later export it to assets/houses/ without touching config.
--
-- ── Why a model needs almost nothing from us ────────────────────────────────────────────────
-- Gameplay never inspects geometry. Hide & Seek asks CollectionService for SC_HidingSpot,
-- Midnight Snack asks for SC_SnackSource, Parent Check asks for SC_BedZone, and every activity
-- finds its staging point via SC_ActivityAnchor. So an imported house does not have to match any
-- particular layout, room count, or naming scheme. It only has to declare which of its parts
-- play which role — and that is what `annotations` below is.
--
-- ── Paths ───────────────────────────────────────────────────────────────────────────────────
-- Every `path` is slash-separated and relative to the model's root, e.g.
-- "Interior/Bedroom/Bed_01/Mattress". HouseLoader resolves them with FindFirstChild at each
-- step and warns loudly about any it cannot find, so a typo shows up as a startup warning
-- rather than a silently missing hiding spot.

export type PathRef = string

export type RoomRef = {
	path: PathRef,
	displayName: string,
	secret: boolean?, -- hidden until an event opens it (the attic)
}

export type AnchorRef = {
	path: PathRef,
	activity: string, -- PillowFight | ParentCheck | MidnightSnack | HideAndSeek | GhostStory
	-- | PizzaDisaster | StrangeNoise
	kind: string?, -- "main" (default), "gather", "door", "seeker"
}

export type HidingSpotRef = {
	path: PathRef,
	label: string, -- shown on the prompt and in announcements: "In the pantry"
}

export type SnackSourceRef = {
	path: PathRef,
	snack: string, -- "Chips", "Cookies", ...
}

export type Annotations = {
	rooms: { RoomRef }?,
	spawns: { PathRef }?, -- SpawnLocations, or plain parts we convert into one
	anchors: { AnchorRef }?,
	hidingSpots: { HidingSpotRef }?,
	snackSources: { SnackSourceRef }?,
	bedZones: { PathRef }?,
	lights: { PathRef }?, -- anything Power Outage should switch off
	atticHatch: PathRef?, -- the panel Strange Noise swings open
	atticLadder: PathRef?, -- revealed with it
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
	default = "Greybox",

	maps = {
		{
			id = "Greybox",
			displayName = "Greybox House",
			source = "Procedural",
			-- No annotations: HouseBuilder tags everything as it builds.
		},

		-- ── Drop-in template ────────────────────────────────────────────────────────────────
		-- Copy this, set `model` to your file's name, fill in the paths, and point `default`
		-- at its id. Every field is optional except id/displayName/source/model, so you can
		-- wire one activity at a time and check it in Studio as you go.
		--
		-- {
		-- 	id = "CozyCottage",
		-- 	displayName = "Cozy Cottage",
		-- 	source = "Model",
		-- 	model = "CozyCottage", -- ServerStorage.ToolboxHouses.CozyCottage, or
		-- 	                       -- assets/houses/CozyCottage.rbxmx
		-- 	annotations = {
		-- 		rooms = {
		-- 			{ path = "Interior/LivingRoom", displayName = "Living Room" },
		-- 			{ path = "Interior/Attic", displayName = "Attic", secret = true },
		-- 		},
		-- 		spawns = { "Spawns/A", "Spawns/B", "Spawns/C", "Spawns/D" },
		-- 		anchors = {
		-- 			{ path = "Interior/LivingRoom/Rug", activity = "PillowFight" },
		-- 			{ path = "Interior/LivingRoom/Rug", activity = "GhostStory", kind = "gather" },
		-- 			{ path = "Interior/Kitchen/Island", activity = "MidnightSnack" },
		-- 			{ path = "Interior/Bedroom/Floor", activity = "ParentCheck" },
		-- 			{ path = "Interior/Hall/Center", activity = "HideAndSeek", kind = "seeker" },
		-- 			{ path = "Exterior/FrontDoor", activity = "PizzaDisaster", kind = "door" },
		-- 			{ path = "Interior/Attic/Center", activity = "StrangeNoise" },
		-- 		},
		-- 		hidingSpots = {
		-- 			{ path = "Interior/Bedroom/Bed_01", label = "Under the bed" },
		-- 			{ path = "Interior/Kitchen/Pantry", label = "In the pantry" },
		-- 			{ path = "Interior/Hall/Closet", label = "In the closet" },
		-- 			{ path = "Interior/Bathroom/Tub", label = "In the bathtub" },
		-- 			{ path = "Interior/LivingRoom/Curtains", label = "Behind the curtains" },
		-- 		},
		-- 		snackSources = {
		-- 			{ path = "Interior/Kitchen/Bowl_01", snack = "Chips" },
		-- 			{ path = "Interior/Kitchen/Bowl_02", snack = "Cookies" },
		-- 			{ path = "Interior/Kitchen/Fridge/Soda", snack = "Soda" },
		-- 			{ path = "Interior/Kitchen/Counter/Popcorn", snack = "Popcorn" },
		-- 		},
		-- 		bedZones = {
		-- 			"Interior/Bedroom/Bed_01/Mattress",
		-- 			"Interior/Bedroom/Bed_02/Mattress",
		-- 		},
		-- 		lights = { "Interior/LivingRoom/Lamp", "Interior/Kitchen/Ceiling" },
		-- 		atticHatch = "Interior/Attic/Hatch",
		-- 		atticLadder = "Interior/Attic/Ladder",
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
