--!strict
-- Tags — CollectionService tag string constants.
-- HouseBuilder applies these to greybox parts; systems query them instead of relying on
-- names or paths, so the house layout can change freely without breaking gameplay code.

local Tags = {
	-- Structural / navigation
	Room = "SC_Room",
	SpawnPoint = "SC_SpawnPoint",
	BedZone = "SC_BedZone", -- "get in bed" target for ParentCheck / Morning
	SecretArea = "SC_SecretArea", -- attic/basement

	-- Per-activity anchors (invisible parts marking where an activity happens)
	ActivityAnchor = "SC_ActivityAnchor", -- has an Attribute "Activity" naming which one

	-- Interactables (ProximityPrompt hosts, registered with InteractionService)
	Interactable = "SC_Interactable", -- has Attributes describing the interaction
	HidingSpot = "SC_HidingSpot", -- HideAndSeek / ParentCheck
	SnackSource = "SC_SnackSource", -- MidnightSnack
	Contraband = "SC_Contraband", -- ParentCheck hideable items
	Door = "SC_Door", -- PizzaDisaster spawn, attic door

	-- Light sources toggled by PowerOutage
	HouseLight = "SC_HouseLight",

	-- NPC guests
	NPCGuest = "SC_NPCGuest",
}

return Tags
