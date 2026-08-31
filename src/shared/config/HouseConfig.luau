--!strict
-- HouseConfig — declarative description of the one house (GDD §4, §17).
-- HouseBuilder reads this and emits the procedural greybox: floors, walls, spawns, and
-- tagged activity anchors / interactables. Everything happens inside this house — no obbies.
--
-- Coordinates are in studs. Each room is an axis-aligned box on the ground plane (y = 0 floor).
-- `size` is {x, z}; `position` is the room center on the XZ plane. Walls are generated around
-- the perimeter with doorway gaps toward the hallway.

export type RoomDef = {
	id: string,
	displayName: string,
	position: { number }, -- {x, z} center
	size: { number }, -- {width, depth}
	color: { number }, -- {r, g, b} 0-1 greybox floor tint
	secret: boolean?, -- attic/basement
}

export type AnchorDef = {
	activity: string, -- which activity/event uses this anchor
	room: string,
	offset: { number }, -- {x, y, z} offset from room center
	kind: string?, -- optional sub-role, e.g. "gather", "door"
}

local HouseConfig = {
	wallHeight = 12,
	wallThickness = 1,
	floorThickness = 1,

	-- The seven areas from GDD §4.
	rooms = {
		{
			id = "LivingRoom",
			displayName = "Living Room",
			position = { 0, 0 },
			size = { 40, 32 },
			color = { 0.75, 0.68, 0.6 },
		},
		{
			id = "Kitchen",
			displayName = "Kitchen",
			position = { 48, 0 },
			size = { 32, 28 },
			color = { 0.7, 0.74, 0.72 },
		},
		{
			id = "Bedroom",
			displayName = "Bedroom",
			position = { -44, 0 },
			size = { 36, 30 },
			color = { 0.72, 0.66, 0.78 },
		},
		{
			id = "Bathroom",
			displayName = "Bathroom",
			position = { -44, -34 },
			size = { 20, 18 },
			color = { 0.7, 0.78, 0.82 },
		},
		{
			id = "Hallway",
			displayName = "Hallway",
			position = { 0, -34 },
			size = { 48, 12 },
			color = { 0.66, 0.66, 0.66 },
		},
		{
			id = "Backyard",
			displayName = "Backyard",
			position = { 0, 40 },
			size = { 56, 34 },
			color = { 0.58, 0.72, 0.5 },
		},
		{
			id = "Attic",
			displayName = "Attic",
			position = { 48, 40 },
			size = { 24, 20 },
			color = { 0.5, 0.45, 0.42 },
			secret = true,
		},
	} :: { RoomDef },

	-- Spawn points: players arrive in the living room.
	spawns = {
		{ room = "LivingRoom", offset = { -8, 0, 8 } },
		{ room = "LivingRoom", offset = { 8, 0, 8 } },
		{ room = "LivingRoom", offset = { -8, 0, -8 } },
		{ room = "LivingRoom", offset = { 8, 0, -8 } },
	},

	-- Where each activity/event stages itself. HouseBuilder tags these parts so the
	-- activity modules can find their anchor without hard-coding positions.
	anchors = {
		{ activity = "PillowFight", room = "LivingRoom", offset = { 0, 0, 0 } },
		{ activity = "GhostStory", room = "LivingRoom", offset = { 0, 0, 6 }, kind = "gather" },
		{ activity = "MidnightSnack", room = "Kitchen", offset = { 0, 0, 0 } },
		{ activity = "ParentCheck", room = "Bedroom", offset = { 0, 0, 0 } },
		{ activity = "HideAndSeek", room = "Hallway", offset = { 0, 0, 0 }, kind = "seeker" },
		{ activity = "PizzaDisaster", room = "LivingRoom", offset = { 0, 0, -14 }, kind = "door" },
		{ activity = "StrangeNoise", room = "Attic", offset = { 0, 0, 0 } },
	} :: { AnchorDef },

	-- Bed zones (ParentCheck "get in bed" + Morning). One per sleeping spot in the bedroom.
	bedZones = {
		{ room = "Bedroom", offset = { -10, 0, 8 } },
		{ room = "Bedroom", offset = { 0, 0, 8 } },
		{ room = "Bedroom", offset = { 10, 0, 8 } },
		{ room = "Bedroom", offset = { -10, 0, -6 } },
	},

	-- Snack sources for MidnightSnack (GDD §6). Named snacks players are asked to fetch.
	snackSources = {
		{ room = "Kitchen", offset = { -10, 2, 6 }, snack = "Chips" },
		{ room = "Kitchen", offset = { 10, 2, 6 }, snack = "Cookies" },
		{ room = "Kitchen", offset = { -10, 2, -6 }, snack = "Soda" },
		{ room = "Kitchen", offset = { 10, 2, -6 }, snack = "Popcorn" },
	},

	-- Hiding spots for HideAndSeek / ParentCheck (GDD §6 "under bed, closet, curtains...").
	hidingSpots = {
		{ room = "Bedroom", offset = { -14, 1, -10 }, label = "Under the bed" },
		{ room = "LivingRoom", offset = { 16, 1, 12 }, label = "Behind the curtains" },
		{ room = "Bathroom", offset = { 6, 1, 4 }, label = "In the bathtub" },
		{ room = "Kitchen", offset = { -12, 1, -10 }, label = "In the pantry" },
		{ room = "Hallway", offset = { 18, 1, 0 }, label = "In the closet" },
	},
}

return HouseConfig
