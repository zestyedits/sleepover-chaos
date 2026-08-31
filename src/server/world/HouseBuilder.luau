--!strict
-- HouseBuilder — builds the one house from HouseConfig (GDD §4, §16, §17).
--
-- The house IS the playground: every activity and event stages itself inside it, so this module
-- is the only place that knows about geometry. Gameplay code finds what it needs through
-- CollectionService tags, never through names or coordinates.
--
-- Three primitives do most of the work, and each exists to solve a specific problem the old
-- room-rectangle model could not express:
--
--   makeWallRun    a wall with DOORWAYS in it — segments either side of each opening plus a
--                  header above. Without this you cannot have interior rooms that connect.
--   slabWithHole   a floor with a rectangular void — the stairwell opening, and the attic hatch.
--   buildStairs    a solid run of steps, so the two floors are physically connected and
--                  PathfindingService can route NPCs between them.
--
-- Output tree (under Workspace):
--   House/
--     Terrain/Ground
--     Rooms/<RoomId>/{Floor..., LightHost}   (folder tagged Room)
--     Structure/{Wall..., Header..., Step..., Railing..., Roof...}
--     Furniture/<Prop models>                (roles tagged per HouseConfig.furniture)
--     AtticAccess/{AtticHatch, AtticLadder}
--     Spawns/ · Anchors/

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HouseConfig = require(Shared.config.HouseConfig)
local Tags = require(Shared.Tags)

local Props = require(script.Parent.Props)

local HouseBuilder = {}

local WALL_COLOR = Color3.fromRGB(226, 218, 206)
-- Warm, slightly off-white. Neon is fully emissive, so this is deliberately not pure white --
-- and it has to stay Neon so Power Outage's swap to SmoothPlastic still reads as "lights off".
local CEILING_LIGHT_COLOR = Color3.fromRGB(235, 226, 198)
local TRIM_COLOR = Color3.fromRGB(158, 130, 104)
local STAIR_COLOR = Color3.fromRGB(168, 132, 96)

-- There is exactly one house, so the attic hatch state lives here rather than being re-derived.
-- Rebuilding the house replaces it.
type AtticState = { hatch: BasePart, ladder: BasePart, closed: CFrame, opened: CFrame }
local atticState: AtticState? = nil

--------------------------------------------------------------------------------------------------
-- Lookups
--------------------------------------------------------------------------------------------------

local function levelById(id: string)
	for _, level in HouseConfig.levels do
		if level.id == id then
			return level
		end
	end
	return nil
end

local function roomById(id: string)
	for _, room in HouseConfig.rooms do
		if room.id == id then
			return room
		end
	end
	return nil
end

-- Resolve a { worldX, heightAboveFloor, worldZ } placement against its room's level.
local function worldPos(roomId: string, at: { number }): Vector3
	local baseY = 0
	local room = roomById(roomId)
	if room then
		local level = levelById(room.level)
		baseY = level and level.baseY or 0
	end
	return Vector3.new(at[1] or 0, baseY + (at[2] or 0), at[3] or 0)
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

--------------------------------------------------------------------------------------------------
-- Slabs
--------------------------------------------------------------------------------------------------

local function slab(
	rect: { number },
	topY: number,
	thickness: number,
	color: Color3,
	material: Enum.Material,
	parent: Instance,
	name: string
)
	local minX, minZ, maxX, maxZ = rect[1], rect[2], rect[3], rect[4]
	local width, depth = maxX - minX, maxZ - minZ
	if width <= 0.001 or depth <= 0.001 then
		return -- degenerate strip; nothing to build
	end
	makePart({
		Name = name,
		Size = Vector3.new(width, thickness, depth),
		CFrame = CFrame.new((minX + maxX) / 2, topY - thickness / 2, (minZ + maxZ) / 2),
		Color = color,
		Material = material,
	}, parent)
end

-- A floor with a rectangular void cut out of it, emitted as up to four strips. This is what makes
-- a staircase possible (the upper slab needs an opening for it) and what the attic hatch sits in.
local function slabWithHole(
	rect: { number },
	hole: { number }?,
	topY: number,
	thickness: number,
	color: Color3,
	material: Enum.Material,
	parent: Instance,
	name: string
)
	local minX, minZ, maxX, maxZ = rect[1], rect[2], rect[3], rect[4]
	if not hole then
		slab(rect, topY, thickness, color, material, parent, name)
		return
	end

	-- Clamp the hole to the slab; a hole that misses entirely means a plain slab.
	local hMinX = math.max(minX, hole[1])
	local hMinZ = math.max(minZ, hole[2])
	local hMaxX = math.min(maxX, hole[3])
	local hMaxZ = math.min(maxZ, hole[4])
	if hMinX >= hMaxX or hMinZ >= hMaxZ then
		slab(rect, topY, thickness, color, material, parent, name)
		return
	end

	slab({ minX, minZ, maxX, hMinZ }, topY, thickness, color, material, parent, name)
	slab({ minX, hMaxZ, maxX, maxZ }, topY, thickness, color, material, parent, name)
	slab({ minX, hMinZ, hMinX, hMaxZ }, topY, thickness, color, material, parent, name)
	slab({ hMaxX, hMinZ, maxX, hMaxZ }, topY, thickness, color, material, parent, name)
end

--------------------------------------------------------------------------------------------------
-- Walls
--------------------------------------------------------------------------------------------------

-- Emit one axis-aligned wall as solid segments around its openings, with a header above each
-- doorway so the wall still reads as a wall rather than a gap.
local function buildWall(wall: any, parent: Instance)
	local level = levelById(wall.level)
	if not level then
		warn(`[HouseBuilder] wall references unknown level {wall.level}`)
		return
	end

	local baseY = level.baseY
	local height = wall.height or level.ceilingHeight
	local thickness = HouseConfig.wallThickness
	local x1, z1 = wall.from[1], wall.from[2]
	local x2, z2 = wall.to[1], wall.to[2]

	-- Walls are axis-aligned: whichever axis varies more is the run axis.
	local alongX = math.abs(x2 - x1) >= math.abs(z2 - z1)
	local a = if alongX then x1 else z1
	local b = if alongX then x2 else z2
	local runStart, runEnd = math.min(a, b), math.max(a, b)
	local fixed = if alongX then z1 else x1

	local function segment(
		fromRun: number,
		toRun: number,
		bottomY: number,
		topY: number,
		name: string
	)
		local length = toRun - fromRun
		local segmentHeight = topY - bottomY
		if length <= 0.001 or segmentHeight <= 0.001 then
			return
		end
		local mid = (fromRun + toRun) / 2
		local size = if alongX
			then Vector3.new(length, segmentHeight, thickness)
			else Vector3.new(thickness, segmentHeight, length)
		local position = if alongX
			then Vector3.new(mid, bottomY + segmentHeight / 2, fixed)
			else Vector3.new(fixed, bottomY + segmentHeight / 2, mid)
		makePart({
			Name = name,
			Size = size,
			CFrame = CFrame.new(position),
			Color = WALL_COLOR,
		}, parent)
	end

	local openings = table.clone(wall.openings or {})
	table.sort(openings, function(left, right)
		return left.at < right.at
	end)

	local cursor = runStart
	for _, opening in openings do
		local doorHeight = opening.height or HouseConfig.doorHeight
		local half = opening.width / 2
		segment(cursor, opening.at - half, baseY, baseY + height, "Wall")
		segment(opening.at - half, opening.at + half, baseY + doorHeight, baseY + height, "Header")
		cursor = opening.at + half
	end
	segment(cursor, runEnd, baseY, baseY + height, "Wall")
end

--------------------------------------------------------------------------------------------------
-- Stairs and railings
--------------------------------------------------------------------------------------------------

-- Each step is a solid box from the floor up to its own tread height. Solid rather than floating
-- treads: nothing to fall between, and PathfindingService routes over it cleanly.
local function buildStairs(def: any, parent: Instance)
	local room = roomById(def.room)
	local level = room and levelById(room.level)
	local floorY = level and level.baseY or 0

	local x1, y1, z1 = def.from[1], def.from[2], def.from[3]
	local x2, y2, z2 = def.to[1], def.to[2], def.to[3]
	local runX, runZ = x2 - x1, z2 - z1
	local runLength = math.sqrt(runX * runX + runZ * runZ)
	if runLength <= 0.001 or def.steps < 1 then
		return
	end

	local alongX = math.abs(runX) >= math.abs(runZ)
	local depth = runLength / def.steps

	for i = 1, def.steps do
		local t = (i - 0.5) / def.steps
		local topY = floorY + y1 + (y2 - y1) * (i / def.steps)
		local bottomY = floorY + y1
		local stepHeight = topY - bottomY
		local size = if alongX
			then Vector3.new(depth, stepHeight, def.width)
			else Vector3.new(def.width, stepHeight, depth)
		makePart({
			Name = `Step{i}`,
			Size = size,
			CFrame = CFrame.new(x1 + runX * t, bottomY + stepHeight / 2, z1 + runZ * t),
			Color = STAIR_COLOR,
			Material = Enum.Material.WoodPlanks,
		}, parent)
	end
end

local function buildRailing(def: any, parent: Instance)
	local level = levelById(def.level)
	if not level then
		return
	end
	local x1, z1 = def.from[1], def.from[2]
	local x2, z2 = def.to[1], def.to[2]
	local dx, dz = x2 - x1, z2 - z1
	local length = math.sqrt(dx * dx + dz * dz)
	if length <= 0.001 then
		return
	end
	local alongX = math.abs(dx) >= math.abs(dz)
	makePart({
		Name = "Railing",
		Size = if alongX then Vector3.new(length, 3.5, 0.5) else Vector3.new(0.5, 3.5, length),
		CFrame = CFrame.new((x1 + x2) / 2, level.baseY + 1.75, (z1 + z2) / 2),
		Color = TRIM_COLOR,
		Material = Enum.Material.Wood,
	}, parent)
end

--------------------------------------------------------------------------------------------------
-- Rooms
--------------------------------------------------------------------------------------------------

local function buildRoom(room: any, roomsFolder: Instance)
	local level = levelById(room.level)
	if not level then
		warn(`[HouseBuilder] room {room.id} references unknown level {room.level}`)
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = room.id
	folder.Parent = roomsFolder
	CollectionService:AddTag(folder, Tags.Room)
	folder:SetAttribute("DisplayName", room.displayName)
	folder:SetAttribute("Level", room.level)
	folder:SetAttribute("Secret", room.secret == true)
	folder:SetAttribute("Open", not room.secret)
	if room.secret then
		CollectionService:AddTag(folder, Tags.SecretArea)
	end

	slabWithHole(
		room.rect,
		room.floorHole,
		level.baseY,
		HouseConfig.floorThickness,
		Color3.new(room.color[1], room.color[2], room.color[3]),
		if room.outdoor then Enum.Material.Grass else Enum.Material.WoodPlanks,
		folder,
		"Floor"
	)

	if room.outdoor then
		return -- no ceiling, so no ceiling light
	end

	-- A ceiling light per room. PowerOutage kills everything carrying the HouseLight tag.
	local centerX = (room.rect[1] + room.rect[3]) / 2
	local centerZ = (room.rect[2] + room.rect[4]) / 2
	local lightHost = makePart({
		Name = "LightHost",
		Size = Vector3.new(3, 0.5, 3),
		CFrame = CFrame.new(
			centerX,
			level.baseY + level.ceilingHeight - HouseConfig.floorThickness - 0.3,
			centerZ
		),
		Color = CEILING_LIGHT_COLOR,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Tags = { Tags.HouseLight },
	}, folder)
	-- The PointLight below lives INSIDE this part. With shadows enabled the host would cast a
	-- shadow straight down and occlude its own light, leaving the floor directly beneath the
	-- fixture darker than the rest of the room.
	lightHost.CastShadow = false

	-- Shadows default to FALSE on a PointLight, which is what actually turned all 16 house
	-- lights into whole-house lights — they lit straight through walls. With shadows on, walls
	-- occlude, so range can track the room again. It still needs a floor: the fixture hangs
	-- ~12.7 studs up, so a range much under 24 never reaches the far floor corners.
	local width = room.rect[3] - room.rect[1]
	local depth = room.rect[4] - room.rect[2]
	local light = Instance.new("PointLight")
	light.Brightness = 1.2
	light.Range = math.clamp(math.max(width, depth) * 0.85, 20, 34)
	light.Shadows = true
	light.Color = Color3.fromRGB(255, 244, 224)
	light.Parent = lightHost
end

--------------------------------------------------------------------------------------------------
-- Furniture (and the gameplay roles that ride on it)
--------------------------------------------------------------------------------------------------

local function buildFurniture(house: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Furniture"
	folder.Parent = house

	for _, item in HouseConfig.furniture do
		local base = CFrame.new(worldPos(item.room, item.at))
			* CFrame.Angles(0, math.rad(item.yaw or 0), 0)
		local model, primary = Props.build(item.kind, base)
		if not model or not primary then
			continue
		end
		model.Parent = folder
		model:SetAttribute("Room", item.room)
		CollectionService:AddTag(primary, Tags.Furniture)

		-- Hiding spots ARE furniture. "In the pantry" is only a real instruction if there is a
		-- visible pantry to run to, so the prompt lives on the prop itself.
		if item.hides then
			primary:SetAttribute("Role", "Hide")
			primary:SetAttribute("Label", item.hides)
			primary:SetAttribute("ActionText", "Hide")
			CollectionService:AddTag(primary, Tags.HidingSpot)
			CollectionService:AddTag(primary, Tags.Interactable)
		end

		if item.snack then
			primary:SetAttribute("Role", "Snack")
			primary:SetAttribute("Snack", item.snack)
			primary:SetAttribute("Label", item.snack)
			primary:SetAttribute("ActionText", "Grab")
			-- MidnightSnack restores to this after a raid.
			primary:SetAttribute("BaseTransparency", primary.Transparency)
			CollectionService:AddTag(primary, Tags.SnackSource)
			CollectionService:AddTag(primary, Tags.Interactable)
		end

		if item.bedZone then
			CollectionService:AddTag(primary, Tags.BedZone)
		end

		-- Lamps are part of the blackout group, so Power Outage darkens the whole house and not
		-- just the ceiling fixtures.
		if item.kind == "Lamp" then
			CollectionService:AddTag(primary, Tags.HouseLight)
			primary.CastShadow = false -- same self-shadowing problem as the ceiling fixtures
			local light = Instance.new("PointLight")
			light.Brightness = 0.85
			light.Range = 15
			light.Color = Color3.fromRGB(255, 236, 200)
			light.Parent = primary
		end
	end
end

--------------------------------------------------------------------------------------------------
-- Attic access
--------------------------------------------------------------------------------------------------

local function buildAtticAccess(house: Instance)
	local access = HouseConfig.atticAccess
	local atticLevel = levelById("Attic")
	if not access or not atticLevel then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "AtticAccess"
	folder.Parent = house

	local centerX, centerZ = access.hatchCenter[1], access.hatchCenter[2]
	local size = Vector3.new(access.hatchSize[1], access.hatchSize[2], access.hatchSize[3])
	local hatchY = atticLevel.baseY - size.Y / 2
	local closed = CFrame.new(centerX, hatchY, centerZ)

	-- Swing about the panel's -Z edge, so opening it reads as a flap thrown back rather than a
	-- part blinking out of existence.
	local hinge = CFrame.new(centerX, hatchY, centerZ - size.Z / 2)
	local opened = hinge * CFrame.Angles(math.rad(-105), 0, 0) * hinge:Inverse() * closed

	local hatch = makePart({
		Name = "AtticHatch",
		Size = size,
		CFrame = closed,
		Color = TRIM_COLOR,
		Material = Enum.Material.WoodPlanks,
		Tags = { Tags.AtticHatch, Tags.Door },
	}, folder)

	local ladder = Instance.new("TrussPart")
	ladder.Name = "AtticLadder"
	ladder.Size = Vector3.new(2, access.ladderTopY - access.ladderBottomY, 2)
	ladder.CFrame = CFrame.new(centerX, (access.ladderBottomY + access.ladderTopY) / 2, centerZ)
	ladder.Anchored = true
	ladder.Color = TRIM_COLOR
	ladder.Parent = folder
	CollectionService:AddTag(ladder, Tags.AtticLadder)

	atticState = { hatch = hatch, ladder = ladder, closed = closed, opened = opened }
	HouseBuilder.setAtticOpen(false)
end

-- The single owner of the attic's physical state. StrangeNoise calls this; nothing else touches
-- the hatch or ladder directly.
function HouseBuilder.setAtticOpen(open: boolean)
	local state = atticState
	if not state or not state.hatch.Parent or not state.ladder.Parent then
		return
	end

	state.hatch.CFrame = if open then state.opened else state.closed
	state.hatch.CanCollide = not open
	state.ladder.CanCollide = open
	state.ladder.Transparency = if open then 0 else 1

	for _, folder in CollectionService:GetTagged(Tags.SecretArea) do
		folder:SetAttribute("Open", open)
	end
end

function HouseBuilder.isAtticOpen(): boolean
	local state = atticState
	return state ~= nil and state.ladder.CanCollide
end

--------------------------------------------------------------------------------------------------
-- Spawns and anchors
--------------------------------------------------------------------------------------------------

local function buildSpawns(house: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Spawns"
	folder.Parent = house
	for i, spawnDef in HouseConfig.spawns do
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = `Spawn{i}`
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.CFrame = CFrame.new(worldPos(spawnDef.room, spawnDef.at) + Vector3.new(0, 3, 0))
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
			CFrame = CFrame.new(worldPos(anchor.room, anchor.at) + Vector3.new(0, 1, 0)),
			Transparency = 1,
			CanCollide = false,
			Tags = { Tags.ActivityAnchor },
			Attributes = {
				Activity = anchor.activity,
				Kind = anchor.kind or "main",
				Room = anchor.room,
			},
		}, folder)
	end
end

--------------------------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------------------------

function HouseBuilder.build(): Instance
	local existing = Workspace:FindFirstChild("House")
	if existing then
		existing:Destroy()
	end
	atticState = nil

	local house = Instance.new("Model")
	house.Name = "House"

	local terrain = Instance.new("Folder")
	terrain.Name = "Terrain"
	terrain.Parent = house
	local groundDef = HouseConfig.ground
	slab(
		groundDef.rect,
		groundDef.y,
		groundDef.thickness,
		Color3.new(groundDef.color[1], groundDef.color[2], groundDef.color[3]),
		Enum.Material.Grass,
		terrain,
		"Ground"
	)

	local roomsFolder = Instance.new("Folder")
	roomsFolder.Name = "Rooms"
	roomsFolder.Parent = house
	for _, room in HouseConfig.rooms do
		buildRoom(room, roomsFolder)
	end

	local structure = Instance.new("Folder")
	structure.Name = "Structure"
	structure.Parent = house
	for _, wall in HouseConfig.walls do
		buildWall(wall, structure)
	end
	for _, stair in HouseConfig.stairs do
		buildStairs(stair, structure)
	end
	for _, railing in HouseConfig.railings do
		buildRailing(railing, structure)
	end
	for _, roof in HouseConfig.roofs do
		slabWithHole(
			roof.rect,
			roof.hole,
			roof.y,
			HouseConfig.floorThickness,
			TRIM_COLOR,
			Enum.Material.WoodPlanks,
			structure,
			"Roof"
		)
	end

	house.Parent = Workspace

	buildFurniture(house)
	buildAtticAccess(house)
	buildSpawns(house)
	buildAnchors(house)

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
