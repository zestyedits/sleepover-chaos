--!strict
-- HouseConfig — declarative description of the one house (GDD §4, §17).
--
-- The house is compact and TWO STORIES, connected by a real staircase, with a secret attic
-- reached through a hatch that only Strange Noise unlocks. Everything happens in here; there are
-- no teleports and no bespoke minigame maps.
--
--   Ground  y=0     LivingRoom · Den · Hallway spine · Kitchen · Stairwell   (+ porch, backyard)
--   Upper   y=14    Bedroom · Bathroom · Landing spine · GuestRoom · StairTop
--   Attic   y=26    one room, hatch + ladder down to the landing
--
-- ── Why walls are their own list ─────────────────────────────────────────────────────────────
-- Rooms deliberately do NOT imply walls. Deriving four walls from each room rectangle (the old
-- model) doubles up every shared boundary and gives you nowhere to put a doorway — which is
-- exactly why the previous house used half-height walls with gaps between floating rectangles,
-- and why its attic ended up a sealed box nobody could enter. Walls are authored explicitly with
-- their openings; rooms only describe a floor, a ceiling light, and metadata.
--
-- ── Coordinate conventions ──────────────────────────────────────────────────────────────────
--   rect       {minX, minZ, maxX, maxZ} in world studs
--   at         {worldX, heightAboveThatRoomsFloor, worldZ}
--   wall.at    the world coordinate along the wall's run axis (x for an east-west wall, z for a
--              north-south one), i.e. where the middle of the doorway sits
--   yaw        degrees, rotation about Y

export type LevelDef = {
	id: string,
	baseY: number, -- world Y of this level's floor surface
	ceilingHeight: number, -- interior height from floor surface to the slab above
}

export type RoomDef = {
	id: string,
	displayName: string,
	level: string,
	rect: { number }, -- {minX, minZ, maxX, maxZ}
	color: { number }, -- {r, g, b} 0-1 floor tint
	secret: boolean?, -- attic; hidden until an event opens it
	outdoor: boolean?, -- porch/backyard: floor only, no ceiling light
	floorHole: { number }?, -- {minX, minZ, maxX, maxZ} cut out of this room's slab
}

export type OpeningDef = {
	at: number, -- world coordinate along the wall's run axis (doorway centre)
	width: number,
	height: number?, -- defaults to doorHeight; the remainder becomes a header above the door
}

export type WallDef = {
	level: string,
	from: { number }, -- {x, z}
	to: { number }, -- {x, z}
	openings: { OpeningDef }?,
	height: number?, -- defaults to the level's ceilingHeight; low values make fences
}

export type FurnitureDef = {
	kind: string, -- a builder in server/world/Props.luau
	room: string,
	at: { number }, -- {worldX, heightAboveFloor, worldZ}
	yaw: number?,
	-- Optional gameplay roles. A prop carrying one of these gets the matching tag + prompt, so
	-- "In the pantry" is an actual pantry rather than a floating grey cube next to one.
	hides: string?, -- HidingSpot label (HideAndSeek / ParentCheck)
	snack: string?, -- SnackSource name (MidnightSnack)
	bedZone: boolean?, -- BedZone trigger (ParentCheck / Morning)
}

export type AnchorDef = {
	activity: string,
	room: string,
	at: { number },
	kind: string?, -- optional sub-role, e.g. "gather", "door"
}

local HouseConfig = {
	wallThickness = 1,
	floorThickness = 1,
	doorWidth = 8,
	doorHeight = 9,

	-- A ground plane under everything, so stepping off the porch is a small drop rather than a
	-- fall into the void. Sits just below the house slabs to avoid z-fighting with them.
	ground = {
		rect = { -90, -90, 90, 90 },
		y = -0.5,
		thickness = 2,
		color = { 0.42, 0.58, 0.36 },
	},

	levels = {
		{ id = "Ground", baseY = 0, ceilingHeight = 14 },
		{ id = "Upper", baseY = 14, ceilingHeight = 12 },
		{ id = "Attic", baseY = 26, ceilingHeight = 9 },
	} :: { LevelDef },

	-- Slabs that cap a level from above. The first one's hole is the attic footprint, which the
	-- Attic room fills with its own floor (itself holed for the hatch); the second caps the attic.
	roofs = {
		{ y = 26, rect = { -30, -24, 30, 24 }, hole = { -14, -12, 14, 12 } },
		{ y = 35, rect = { -14, -12, 14, 12 } },
	},

	rooms = {
		-- Ground floor ------------------------------------------------------------------
		{
			id = "LivingRoom",
			displayName = "Living Room",
			level = "Ground",
			rect = { -30, -24, -6, 6 },
			color = { 0.76, 0.68, 0.58 },
		},
		{
			id = "Den",
			displayName = "Den",
			level = "Ground",
			rect = { -30, 6, -6, 24 },
			color = { 0.72, 0.65, 0.62 },
		},
		{
			id = "Hallway",
			displayName = "Hallway",
			level = "Ground",
			rect = { -6, -24, 6, 24 },
			color = { 0.66, 0.64, 0.64 },
		},
		{
			id = "Kitchen",
			displayName = "Kitchen",
			level = "Ground",
			rect = { 6, -24, 30, 2 },
			color = { 0.72, 0.75, 0.72 },
		},
		{
			id = "Stairwell",
			displayName = "Stairwell",
			level = "Ground",
			rect = { 6, 2, 30, 24 },
			color = { 0.68, 0.66, 0.7 },
		},
		{
			id = "Porch",
			displayName = "Front Porch",
			level = "Ground",
			rect = { -10, -34, 10, -24 },
			color = { 0.6, 0.56, 0.52 },
			outdoor = true,
		},
		{
			id = "Backyard",
			displayName = "Backyard",
			level = "Ground",
			rect = { -28, 24, 28, 50 },
			color = { 0.55, 0.7, 0.47 },
			outdoor = true,
		},

		-- Upper floor -------------------------------------------------------------------
		{
			id = "Bedroom",
			displayName = "Bedroom",
			level = "Upper",
			rect = { -30, -24, -6, 6 },
			color = { 0.73, 0.66, 0.79 },
		},
		{
			id = "Bathroom",
			displayName = "Bathroom",
			level = "Upper",
			rect = { -30, 6, -6, 24 },
			color = { 0.7, 0.79, 0.83 },
		},
		{
			id = "Landing",
			displayName = "Landing",
			level = "Upper",
			rect = { -6, -24, 6, 24 },
			color = { 0.66, 0.64, 0.64 },
		},
		{
			id = "GuestRoom",
			displayName = "Guest Room",
			level = "Upper",
			rect = { 6, -24, 30, 2 },
			color = { 0.74, 0.7, 0.64 },
		},
		{
			-- The stairwell void. Its slab is holed so the staircase below is open to the sky
			-- of this floor; railings fence the drop.
			id = "StairTop",
			displayName = "Stair Landing",
			level = "Upper",
			rect = { 6, 2, 30, 24 },
			color = { 0.68, 0.66, 0.7 },
			floorHole = { 17, 2, 30, 20.5 },
		},

		-- Attic -------------------------------------------------------------------------
		{
			id = "Attic",
			displayName = "Attic",
			level = "Attic",
			rect = { -14, -12, 14, 12 },
			color = { 0.5, 0.45, 0.42 },
			secret = true,
			floorHole = { -3, 5, 3, 11 },
		},
	} :: { RoomDef },

	walls = {
		-- Ground exterior ---------------------------------------------------------------
		{
			level = "Ground",
			from = { -30, -24 },
			to = { 30, -24 },
			openings = { { at = 0, width = 8 } },
		},
		{
			level = "Ground",
			from = { -30, 24 },
			to = { 30, 24 },
			openings = { { at = -18, width = 8 } },
		},
		{ level = "Ground", from = { -30, -24 }, to = { -30, 24 } },
		{ level = "Ground", from = { 30, -24 }, to = { 30, 24 } },

		-- Ground interior. The hallway spine is the circulation: every ground room opens onto it.
		{
			level = "Ground",
			from = { -6, -24 },
			to = { -6, 24 },
			openings = { { at = -9, width = 8 }, { at = 15, width = 8 } },
		},
		{
			level = "Ground",
			from = { 6, -24 },
			to = { 6, 24 },
			openings = { { at = -11, width = 8 }, { at = 13, width = 10 } },
		},
		{
			level = "Ground",
			from = { -30, 6 },
			to = { -6, 6 },
			openings = { { at = -18, width = 8 } },
		},
		{
			level = "Ground",
			from = { 6, 2 },
			to = { 30, 2 },
			openings = { { at = 12, width = 6 } },
		},

		-- Upper exterior ----------------------------------------------------------------
		{ level = "Upper", from = { -30, -24 }, to = { 30, -24 } },
		{ level = "Upper", from = { -30, 24 }, to = { 30, 24 } },
		{ level = "Upper", from = { -30, -24 }, to = { -30, 24 } },
		{ level = "Upper", from = { 30, -24 }, to = { 30, 24 } },

		-- Upper interior ----------------------------------------------------------------
		{
			level = "Upper",
			from = { -6, -24 },
			to = { -6, 24 },
			openings = { { at = -9, width = 8 }, { at = 15, width = 8 } },
		},
		{
			level = "Upper",
			from = { 6, -24 },
			to = { 6, 24 },
			openings = { { at = -11, width = 8 }, { at = 13, width = 10 } },
		},
		{
			level = "Upper",
			from = { -30, 6 },
			to = { -6, 6 },
			openings = { { at = -18, width = 8 } },
		},
		{ level = "Upper", from = { 6, 2 }, to = { 30, 2 }, openings = { { at = 12, width = 6 } } },

		-- Outdoor fencing. Low `height` keeps the yard readable instead of walled in.
		{ level = "Ground", from = { -28, 50 }, to = { 28, 50 }, height = 4 },
		{ level = "Ground", from = { -28, 24 }, to = { -28, 50 }, height = 4 },
		{ level = "Ground", from = { 28, 24 }, to = { 28, 50 }, height = 4 },
		{ level = "Ground", from = { -10, -34 }, to = { -10, -24 }, height = 4 },
		{ level = "Ground", from = { 10, -34 }, to = { 10, -24 }, height = 4 },

		-- Attic (sealed; the hatch is the only way in) -----------------------------------
		{ level = "Attic", from = { -14, -12 }, to = { 14, -12 } },
		{ level = "Attic", from = { -14, 12 }, to = { 14, 12 } },
		{ level = "Attic", from = { -14, -12 }, to = { -14, 12 } },
		{ level = "Attic", from = { 14, -12 }, to = { 14, 12 } },
	} :: { WallDef },

	-- One staircase, ground to upper, rising along +z inside the Stairwell. The top step's
	-- surface is flush with the Upper slab so you walk straight off it onto the landing.
	stairs = {
		{
			room = "Stairwell",
			from = { 22, 0, 3 },
			to = { 22, 14, 20.5 },
			width = 8,
			steps = 14,
		},
	},

	-- Fencing around the stairwell drop. Nothing on the z = 20.5 edge — that is where you arrive.
	railings = {
		{ level = "Upper", from = { 17, 2 }, to = { 17, 20.5 } },
		{ level = "Upper", from = { 17, 2 }, to = { 30, 2 } },
	},

	-- The secret attic entrance. Sealed until StrangeNoise fires (GDD §7).
	atticAccess = {
		hatchCenter = { 0, 8 }, -- world x, z; must sit inside Attic.floorHole
		hatchSize = { 6, 0.5, 6 },
		ladderBottomY = 14,
		ladderTopY = 26,
	},

	-- Players arrive in the living room.
	spawns = {
		{ room = "LivingRoom", at = { -24, 0, -4 } },
		{ room = "LivingRoom", at = { -24, 0, 2 } },
		{ room = "LivingRoom", at = { -12, 0, -4 } },
		{ room = "LivingRoom", at = { -12, 0, 2 } },
	},

	-- Where each activity/event stages itself.
	anchors = {
		{ activity = "PillowFight", room = "LivingRoom", at = { -18, 0, -9 } },
		{ activity = "GhostStory", room = "LivingRoom", at = { -18, 0, -3 }, kind = "gather" },
		{ activity = "MidnightSnack", room = "Kitchen", at = { 16, 0, -8 } },
		{ activity = "ParentCheck", room = "Bedroom", at = { -18, 0, -10 } },
		{ activity = "HideAndSeek", room = "Hallway", at = { 0, 0, 0 }, kind = "seeker" },
		{ activity = "PizzaDisaster", room = "Porch", at = { 0, 0, -29 }, kind = "door" },
		{ activity = "StrangeNoise", room = "Attic", at = { 0, 0, -4 } },
	} :: { AnchorDef },

	-- Every prop in the house. Gameplay roles ride along on the props themselves (`hides`,
	-- `snack`, `bedZone`) so the hiding spots and snack sources are real furniture.
	furniture = {
		-- Living room -------------------------------------------------------------------
		{ kind = "Sofa", room = "LivingRoom", at = { -18, 0, 1 }, yaw = 180 },
		{ kind = "TV", room = "LivingRoom", at = { -18, 0, -21 }, yaw = 0 },
		{ kind = "Rug", room = "LivingRoom", at = { -18, 0, -8 } },
		{ kind = "CoffeeTable", room = "LivingRoom", at = { -18, 0, -8 } },
		{ kind = "Bookshelf", room = "LivingRoom", at = { -28, 0, -16 }, yaw = 90 },
		{ kind = "Lamp", room = "LivingRoom", at = { -9, 0, 2 } },
		{
			kind = "Curtains",
			room = "LivingRoom",
			at = { -28.5, 0, 0 },
			yaw = 90,
			hides = "Behind the curtains",
		},

		-- Den ---------------------------------------------------------------------------
		{ kind = "Rug", room = "Den", at = { -18, 0, 15 } },
		{ kind = "ToyChest", room = "Den", at = { -27, 0, 20 }, yaw = 90 },
		{ kind = "Bookshelf", room = "Den", at = { -10, 0, 22.5 }, yaw = 180 },
		{ kind = "Lamp", room = "Den", at = { -9, 0, 9 } },

		-- Hallway -----------------------------------------------------------------------
		{
			kind = "Closet",
			room = "Hallway",
			at = { 4, 0, 18 },
			yaw = -90,
			hides = "In the closet",
		},

		-- Kitchen -----------------------------------------------------------------------
		{ kind = "Counter", room = "Kitchen", at = { 28, 0, -14 }, yaw = 90 },
		{ kind = "Fridge", room = "Kitchen", at = { 28, 0, -22 }, yaw = 90 },
		{ kind = "Stove", room = "Kitchen", at = { 18, 0, -22.5 }, yaw = 0 },
		{ kind = "DiningTable", room = "Kitchen", at = { 15, 0, -6 } },
		{ kind = "Chair", room = "Kitchen", at = { 10, 0, -6 }, yaw = 90 },
		{ kind = "Chair", room = "Kitchen", at = { 20, 0, -6 }, yaw = -90 },
		{
			kind = "Pantry",
			room = "Kitchen",
			at = { 8.5, 0, -20 },
			yaw = 90,
			hides = "In the pantry",
		},
		-- Heights put each bowl on top of the surface under it: counter 3.7, table 3.2, stove 3.4.
		{ kind = "SnackBowl", room = "Kitchen", at = { 28, 3.7, -10 }, snack = "Chips" },
		{ kind = "SnackBowl", room = "Kitchen", at = { 28, 3.7, -17 }, snack = "Cookies" },
		{ kind = "SnackBowl", room = "Kitchen", at = { 15, 3.2, -6 }, snack = "Soda" },
		{ kind = "SnackBowl", room = "Kitchen", at = { 18, 3.4, -22.5 }, snack = "Popcorn" },

		-- Bedroom -----------------------------------------------------------------------
		{ kind = "Bed", room = "Bedroom", at = { -26, 0, -19 }, yaw = 90, bedZone = true },
		{ kind = "Bed", room = "Bedroom", at = { -26, 0, -8 }, yaw = 90, bedZone = true },
		{ kind = "Bed", room = "Bedroom", at = { -12, 0, -19 }, yaw = -90, bedZone = true },
		{
			kind = "Bed",
			room = "Bedroom",
			at = { -12, 0, -8 },
			yaw = -90,
			bedZone = true,
			hides = "Under the bed",
		},
		{ kind = "Nightstand", room = "Bedroom", at = { -26, 0, -13 } },
		{ kind = "Dresser", room = "Bedroom", at = { -27, 0, 4 }, yaw = 180 },
		{ kind = "Lamp", room = "Bedroom", at = { -18, 0, -22 } },

		-- Bathroom ----------------------------------------------------------------------
		{
			kind = "Bathtub",
			room = "Bathroom",
			at = { -26, 0, 18 },
			yaw = 90,
			hides = "In the bathtub",
		},
		{ kind = "Sink", room = "Bathroom", at = { -11, 0, 20 }, yaw = -90 },
		{ kind = "Toilet", room = "Bathroom", at = { -11, 0, 10 }, yaw = -90 },

		-- Guest room --------------------------------------------------------------------
		{ kind = "Bed", room = "GuestRoom", at = { 26, 0, -20 }, yaw = 90, bedZone = true },
		{ kind = "Dresser", room = "GuestRoom", at = { 12, 0, -22.5 }, yaw = 0 },
		{ kind = "Lamp", room = "GuestRoom", at = { 20, 0, -6 } },

		-- Attic -------------------------------------------------------------------------
		{ kind = "AtticBox", room = "Attic", at = { -10, 0, -8 }, yaw = 20 },
		{ kind = "AtticBox", room = "Attic", at = { -6, 0, -9 }, yaw = -35 },
		{ kind = "AtticBox", room = "Attic", at = { 10, 0, 6 }, yaw = 10 },
		{ kind = "Lamp", room = "Attic", at = { 10, 0, -8 } },
	} :: { FurnitureDef },
}

return HouseConfig
