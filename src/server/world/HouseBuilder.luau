--!strict
-- HouseBuilder — procedurally builds the one greybox house from HouseConfig (GDD §4, §16, §17).
-- The house IS the playground; every activity/event stages itself inside it. Oversized readable
-- greybox blocks stand in for the art pass; real modular furniture/props come later (GDD §16).
--
-- Output tree (under Workspace):
--   House/
--     Rooms/<RoomId>/{Floor, Walls...}   (tagged Room)
--     Spawns/<SpawnPart>                  (tagged SpawnPoint)
--     Anchors/<Activity>Anchor           (tagged ActivityAnchor, Attribute Activity)
--     BedZones/<BedN>                     (tagged BedZone)
--     Interactables/...                   (tagged per role; wired by InteractionService)
--     Lights/<PointLight hosts>           (tagged HouseLight; toggled by PowerOutage)

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HouseConfig = require(Shared.config.HouseConfig)
local Tags = require(Shared.Tags)

local HouseBuilder = {}

local FLOOR_Y = 0

-- Look up a room def by id.
local function roomById(id: string)
	for _, room in HouseConfig.rooms do
		if room.id == id then
			return room
		end
	end
	return nil
end

-- Convert a room-relative { x, y, z } offset into a world Vector3.
local function worldPos(roomId: string, offset: { number }): Vector3
	local room = roomById(roomId)
	if not room then
		return Vector3.new(offset[1] or 0, offset[2] or 0, offset[3] or 0)
	end
	return Vector3.new(
		room.position[1] + (offset[1] or 0),
		FLOOR_Y + (offset[2] or 0),
		room.position[2] + (offset[3] or 0)
	)
end
HouseBuilder.worldPos = worldPos

local function makePart(props: { [string]: any }, parent: Instance): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Size = props.Size or Vector3.new(4, 4, 4)
	part.CFrame = props.CFrame or CFrame.new(props.Position or Vector3.zero)
	if props.Color then
		part.Color = props.Color
	end
	if props.Transparency then
		part.Transparency = props.Transparency
	end
	if props.CanCollide ~= nil then
		part.CanCollide = props.CanCollide
	end
	part.Name = props.Name or "Part"
	part.Parent = parent
	for _, tag in props.Tags or {} do
		CollectionService:AddTag(part, tag)
	end
	if props.Attributes then
		for key, value in props.Attributes do
			part:SetAttribute(key, value)
		end
	end
	return part
end

local function buildRoom(room: any, roomsFolder: Instance)
	local folder = Instance.new("Folder")
	folder.Name = room.id
	folder.Parent = roomsFolder
	CollectionService:AddTag(folder, Tags.Room)
	folder:SetAttribute("DisplayName", room.displayName)
	folder:SetAttribute("Secret", room.secret == true)

	local width, depth = room.size[1], room.size[2]
	local center = Vector3.new(room.position[1], FLOOR_Y, room.position[2])
	local color = Color3.new(room.color[1], room.color[2], room.color[3])

	-- Floor
	makePart({
		Name = "Floor",
		Size = Vector3.new(width, HouseConfig.floorThickness, depth),
		CFrame = CFrame.new(center - Vector3.new(0, HouseConfig.floorThickness / 2, 0)),
		Color = color,
		Material = Enum.Material.WoodPlanks,
	}, folder)

	-- Perimeter walls (four sides). Doorways are left implicit by the open greybox layout;
	-- rooms are spaced with gaps so avatars can walk between them.
	local wallH = HouseConfig.wallHeight
	local wallT = HouseConfig.wallThickness
	local wallColor = color:Lerp(Color3.new(1, 1, 1), 0.25)
	local halfW, halfD = width / 2, depth / 2
	local wallY = FLOOR_Y + wallH / 2

	-- Secret rooms get full walls; open rooms get low half-walls so the greybox reads as
	-- connected space you can wander (GDD §17 — one continuous house, no teleporting).
	local h = if room.secret then wallH else wallH * 0.4
	local y = if room.secret then wallY else FLOOR_Y + h / 2

	local walls = {
		{ size = Vector3.new(width, h, wallT), pos = center + Vector3.new(0, y - FLOOR_Y, -halfD) },
		{ size = Vector3.new(width, h, wallT), pos = center + Vector3.new(0, y - FLOOR_Y, halfD) },
		{ size = Vector3.new(wallT, h, depth), pos = center + Vector3.new(-halfW, y - FLOOR_Y, 0) },
		{ size = Vector3.new(wallT, h, depth), pos = center + Vector3.new(halfW, y - FLOOR_Y, 0) },
	}
	for i, wall in walls do
		makePart({
			Name = `Wall{i}`,
			Size = wall.size,
			CFrame = CFrame.new(wall.pos),
			Color = wallColor,
		}, folder)
	end

	-- A ceiling-mounted light host per room (toggled by PowerOutage).
	local lightHost = makePart({
		Name = "LightHost",
		Size = Vector3.new(3, 0.5, 3),
		CFrame = CFrame.new(center + Vector3.new(0, wallH - 1, 0)),
		Color = Color3.new(1, 0.95, 0.8),
		Material = Enum.Material.Neon,
		Tags = { Tags.HouseLight },
	}, folder)
	local light = Instance.new("PointLight")
	light.Brightness = 1.5
	light.Range = math.max(width, depth)
	light.Color = Color3.new(1, 0.95, 0.85)
	light.Parent = lightHost
end

local function buildSpawns(house: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Spawns"
	folder.Parent = house
	for i, spawnDef in HouseConfig.spawns do
		local pos = worldPos(spawnDef.room, spawnDef.offset) + Vector3.new(0, 3, 0)
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = `Spawn{i}`
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.CFrame = CFrame.new(pos)
		spawn.Parent = folder
		CollectionService:AddTag(spawn, Tags.SpawnPoint)
	end
end

local function buildAnchors(house: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Anchors"
	folder.Parent = house
	for _, anchor in HouseConfig.anchors do
		makePart({
			Name = `{anchor.activity}Anchor`,
			Size = Vector3.new(2, 2, 2),
			CFrame = CFrame.new(worldPos(anchor.room, anchor.offset) + Vector3.new(0, 1, 0)),
			Transparency = 1,
			CanCollide = false,
			Tags = { Tags.ActivityAnchor },
			Attributes = { Activity = anchor.activity, Kind = anchor.kind or "main", Room = anchor.room },
		}, folder)
	end
end

local function buildBedZones(house: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "BedZones"
	folder.Parent = house
	for i, bed in HouseConfig.bedZones do
		-- A visible greybox "bed" plus an invisible trigger zone above it.
		makePart({
			Name = `Bed{i}`,
			Size = Vector3.new(7, 1.5, 4),
			CFrame = CFrame.new(worldPos(bed.room, bed.offset) + Vector3.new(0, 0.75, 0)),
			Color = Color3.new(0.85, 0.8, 0.9),
			Material = Enum.Material.Fabric,
		}, folder)
		makePart({
			Name = `BedZone{i}`,
			Size = Vector3.new(7, 4, 4),
			CFrame = CFrame.new(worldPos(bed.room, bed.offset) + Vector3.new(0, 2, 0)),
			Transparency = 1,
			CanCollide = false,
			Tags = { Tags.BedZone },
			Attributes = { Index = i },
		}, folder)
	end
end

local function buildInteractables(house: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Interactables"
	folder.Parent = house

	-- Snack sources (MidnightSnack)
	for i, snack in HouseConfig.snackSources do
		makePart({
			Name = `Snack_{snack.snack}`,
			Size = Vector3.new(2.5, 2.5, 2.5),
			CFrame = CFrame.new(worldPos(snack.room, snack.offset)),
			Color = Color3.new(0.9, 0.8, 0.4),
			Material = Enum.Material.SmoothPlastic,
			Tags = { Tags.SnackSource, Tags.Interactable },
			Attributes = { Snack = snack.snack, Role = "Snack" },
		}, folder)
	end

	-- Hiding spots (HideAndSeek / ParentCheck)
	for i, spot in HouseConfig.hidingSpots do
		makePart({
			Name = `Hide_{i}`,
			Size = Vector3.new(3, 3, 3),
			CFrame = CFrame.new(worldPos(spot.room, spot.offset)),
			Color = Color3.new(0.4, 0.4, 0.5),
			Transparency = 0.3,
			Tags = { Tags.HidingSpot, Tags.Interactable },
			Attributes = { Label = spot.label, Role = "Hide" },
		}, folder)
	end
end

-- Build (or rebuild) the whole house. Returns the House model.
function HouseBuilder.build(): Instance
	local existing = Workspace:FindFirstChild("House")
	if existing then
		existing:Destroy()
	end

	local house = Instance.new("Model")
	house.Name = "House"

	local roomsFolder = Instance.new("Folder")
	roomsFolder.Name = "Rooms"
	roomsFolder.Parent = house
	for _, room in HouseConfig.rooms do
		buildRoom(room, roomsFolder)
	end

	house.Parent = Workspace

	buildSpawns(house)
	buildAnchors(house)
	buildBedZones(house)
	buildInteractables(house)

	return house
end

-- Find the anchor part for a given activity id (used by activity modules).
function HouseBuilder.getAnchor(house: Instance, activity: string, kind: string?): BasePart?
	local anchors = house:FindFirstChild("Anchors")
	if not anchors then
		return nil
	end
	for _, part in anchors:GetChildren() do
		if part:GetAttribute("Activity") == activity then
			if kind == nil or part:GetAttribute("Kind") == kind then
				return part :: BasePart
			end
		end
	end
	return nil
end

return HouseBuilder
