--!strict
-- HouseLoader — the one entry point for "put a house in the world".
--
-- Two sources, one output contract. A PROCEDURAL map is emitted by HouseBuilder; a MODEL map is
-- cloned out of ServerStorage.HouseModels and then ANNOTATED — we walk MapConfig's refs and
-- apply the same CollectionService tags HouseBuilder would have applied itself.
--
-- Downstream nothing knows or cares which happened. Hide & Seek asks for SC_HidingSpot and gets
-- an answer either way, which is the whole reason gameplay was written against tags instead of
-- geometry in the first place.
--
-- Annotation is deliberately noisy on failure: a ref that does not resolve is a warning at
-- startup, and a house missing whole categories (no hiding spots, no snack sources, no anchors)
-- is reported as a summary. A silently half-wired house would present as unrelated gameplay bugs
-- twenty minutes into a playtest.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapConfig = require(Shared.config.MapConfig)
local Tags = require(Shared.Tags)

local HouseBuilder = require(script.Parent.HouseBuilder)
local Props = require(script.Parent.Props)

local HouseLoader = {}

-- Studio drops live here. Deliberately NOT in default.project.json: Rojo deletes instances it
-- manages that are absent from disk, so a Toolbox insert placed under the Rojo-managed
-- HouseModels folder would vanish on the next sync.
local TOOLBOX_FOLDER = "ToolboxHouses"
local SYNCED_FOLDER = "HouseModels"
local FURNITURE_FOLDER = "FurnitureModels"

local DEFAULT_MARKER_SIZE = Vector3.new(6, 6, 6)

-- How far above the floor a spawn pad sits. Enough that the pad is not co-planar with the slab
-- and z-fighting, small enough that nobody falls on arrival.
local SPAWN_CLEARANCE = 0.5

local currentMapId: string? = nil
local problems: { string } = {}

local function complain(message: string)
	table.insert(problems, message)
	warn(`[HouseLoader] {message}`)
end

--------------------------------------------------------------------------------------------------
-- The house frame
--------------------------------------------------------------------------------------------------

-- Positional refs are expressed relative to the house itself, not to the world, so that moving
-- the model does not silently invalidate every annotation.
--
--   X, Z  offset from the bounding-box centre
--   Y     height above the base (the model's lowest point)
--
-- Model:GetBoundingBox() would do most of this, but it returns an OBB aligned to the model's
-- pivot, and a house is allowed to be a Folder anyway. So this computes a true world-space AABB.
--
-- Note the abs-dot below rather than `part.Position +/- part.Size / 2`. That naive form silently
-- assumes every part is axis-aligned, and a house is full of rotated roof panels and angled
-- unions; on the first model tried here it overstated the bounds by 12 studs in X and 7 in Y,
-- which is enough to put every spawn point inside a wall.
local function originOf(house: Instance): CFrame
	local min: Vector3?, max: Vector3? = nil, nil
	for _, descendant in house:GetDescendants() do
		if descendant:IsA("BasePart") then
			local cframe, size = descendant.CFrame, descendant.Size / 2
			local right, up, look = cframe.RightVector, cframe.UpVector, cframe.LookVector
			-- World extent of a rotated box: project its half-size onto each world axis.
			local extent = Vector3.new(
				math.abs(right.X) * size.X + math.abs(up.X) * size.Y + math.abs(look.X) * size.Z,
				math.abs(right.Y) * size.X + math.abs(up.Y) * size.Y + math.abs(look.Y) * size.Z,
				math.abs(right.Z) * size.X + math.abs(up.Z) * size.Y + math.abs(look.Z) * size.Z
			)
			local lo, hi = cframe.Position - extent, cframe.Position + extent
			min = if min then (min :: Vector3):Min(lo) else lo
			max = if max then (max :: Vector3):Max(hi) else hi
		end
	end
	if not min or not max then
		complain(
			"house contains no parts — positional refs will resolve against the world origin"
		)
		return CFrame.new()
	end
	local lo, hi = min :: Vector3, max :: Vector3
	return CFrame.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
end

local function marker(
	house: Instance,
	origin: CFrame,
	at: { number },
	size: { number }?,
	name: string
): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = if size then Vector3.new(size[1], size[2], size[3]) else DEFAULT_MARKER_SIZE
	part.CFrame = origin * CFrame.new(at[1] or 0, at[2] or 0, at[3] or 0)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.Anchored = true
	part.Parent = house
	return part
end

-- Resolve a slash-separated path relative to the model root.
local function resolve(root: Instance, path: string): Instance?
	local node: Instance? = root
	for segment in path:gmatch("[^/]+") do
		if not node then
			return nil
		end
		node = (node :: Instance):FindFirstChild(segment)
	end
	return node
end

local function partFrom(node: Instance, label: string, role: string): BasePart?
	if node:IsA("BasePart") then
		return node
	end
	-- A Model is a reasonable thing to point at; use its PrimaryPart, else any part inside it.
	if node:IsA("Model") then
		local part = node.PrimaryPart or node:FindFirstChildWhichIsA("BasePart", true)
		if part then
			return part
		end
	end
	complain(`{role}: "{label}" is a {node.ClassName} with no usable BasePart`)
	return nil
end

local function describe(ref: any): string
	if type(ref) == "string" then
		return ref
	end
	if ref.path then
		return ref.path
	end
	if ref.at then
		return `at {ref.at[1]},{ref.at[2]},{ref.at[3]}`
	end
	return "<malformed ref>"
end

-- A ref is either a path string, {path = ...}, or {at = {x, y, z}}. Returns the instance the tag
-- should land on: an existing part for a path, a fresh invisible marker for a position.
local function resolveNode(house: Instance, origin: CFrame, ref: any, role: string): Instance?
	if type(ref) == "string" then
		local node = resolve(house, ref)
		if not node then
			complain(`{role}: no instance at "{ref}"`)
		end
		return node
	end
	if type(ref) ~= "table" then
		complain(`{role}: expected a path or a position, got {typeof(ref)}`)
		return nil
	end
	if ref.path then
		local node = resolve(house, ref.path)
		if not node then
			complain(`{role}: no instance at "{ref.path}"`)
		end
		return node
	end
	if ref.at then
		return marker(house, origin, ref.at, ref.size, `{role}Marker`)
	end
	complain(`{role}: ref has neither a "path" nor an "at"`)
	return nil
end

local function resolvePart(house: Instance, origin: CFrame, ref: any, role: string): BasePart?
	local node = resolveNode(house, origin, ref, role)
	if not node then
		return nil
	end
	return partFrom(node, describe(ref), role)
end

--------------------------------------------------------------------------------------------------
-- Annotation
--------------------------------------------------------------------------------------------------

local function tagHidingSpot(part: BasePart, label: string)
	part:SetAttribute("Role", "Hide")
	part:SetAttribute("Label", label)
	part:SetAttribute("ActionText", "Hide")
	CollectionService:AddTag(part, Tags.HidingSpot)
	CollectionService:AddTag(part, Tags.Interactable)
end

local function tagSnackSource(part: BasePart, snack: string)
	part:SetAttribute("Role", "Snack")
	part:SetAttribute("Snack", snack)
	part:SetAttribute("Label", snack)
	part:SetAttribute("ActionText", "Grab")
	-- MidnightSnack restores to this after a raid.
	part:SetAttribute("BaseTransparency", part.Transparency)
	CollectionService:AddTag(part, Tags.SnackSource)
	CollectionService:AddTag(part, Tags.Interactable)
end

local function tagAnchor(house: Instance, cframe: CFrame, activity: string, kind: string?)
	-- Anchors are markers, not geometry: an invisible part avoids repurposing a solid prop and
	-- lets several activities share one location.
	local part = Instance.new("Part")
	part.Name = `{activity}Anchor`
	part.Size = Vector3.new(2, 2, 2)
	part.CFrame = cframe
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.Anchored = true
	part:SetAttribute("Activity", activity)
	part:SetAttribute("Kind", kind or "main")
	part.Parent = house
	CollectionService:AddTag(part, Tags.ActivityAnchor)
end

local function makeSpawn(parent: Instance, cframe: CFrame, name: string)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = name
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.CFrame = cframe
	spawn.Parent = parent
	CollectionService:AddTag(spawn, Tags.SpawnPoint)
end

local function annotate(house: Instance, origin: CFrame, annotations: any)
	if not annotations then
		return
	end

	for _, room in annotations.rooms or {} do
		local node = resolveNode(house, origin, room, "room")
		if not node then
			continue
		end
		CollectionService:AddTag(node, Tags.Room)
		node:SetAttribute("DisplayName", room.displayName)
		node:SetAttribute("Secret", room.secret == true)
		node:SetAttribute("Open", not room.secret)
		if room.secret then
			CollectionService:AddTag(node, Tags.SecretArea)
		end
	end

	for index, ref in annotations.spawns or {} do
		-- A positional spawn already names a point on the floor, so the pad goes straight there.
		-- Routing it through the generic marker path instead would centre a 6x6x6 box on the
		-- floor and then lift the pad by half of it, dropping every player 4 studs on arrival.
		if type(ref) == "table" and ref.at and not ref.path then
			local at = ref.at
			makeSpawn(
				house,
				origin * CFrame.new(at[1] or 0, (at[2] or 0) + SPAWN_CLEARANCE, at[3] or 0),
				`Spawn_{index}`
			)
			continue
		end

		local node = resolveNode(house, origin, ref, "spawn")
		if not node then
			continue
		end
		if node:IsA("SpawnLocation") then
			node.Neutral = true
			node.Duration = 0
			CollectionService:AddTag(node, Tags.SpawnPoint)
		elseif node:IsA("BasePart") then
			-- Pointing at a real prop means "spawn on top of this", so here the lift by half the
			-- part's height is what you want.
			makeSpawn(
				node,
				node.CFrame + Vector3.new(0, node.Size.Y / 2 + SPAWN_CLEARANCE, 0),
				`Spawn_{index}`
			)
		else
			complain(`spawn: a {node.ClassName} is not a part or SpawnLocation`)
		end
	end

	for _, anchor in annotations.anchors or {} do
		local part = resolvePart(house, origin, anchor, "anchor")
		if part then
			tagAnchor(house, part.CFrame, anchor.activity, anchor.kind)
		end
	end

	for _, spot in annotations.hidingSpots or {} do
		local part = resolvePart(house, origin, spot, "hidingSpot")
		if part then
			tagHidingSpot(part, spot.label)
		end
	end

	for _, source in annotations.snackSources or {} do
		local part = resolvePart(house, origin, source, "snackSource")
		if part then
			tagSnackSource(part, source.snack)
		end
	end

	for _, ref in annotations.bedZones or {} do
		local part = resolvePart(house, origin, ref, "bedZone")
		if part then
			CollectionService:AddTag(part, Tags.BedZone)
		end
	end

	for _, ref in annotations.lights or {} do
		local part = resolvePart(house, origin, ref, "light")
		if part then
			CollectionService:AddTag(part, Tags.HouseLight)
		end
	end

	-- Nobody hand-lists forty light fixtures. If the map did not name any, adopt every light the
	-- model already ships with, so Power Outage has something to switch off.
	--
	-- Without this an imported house blacks out only the global Lighting while every fixture in
	-- the building stays lit, which reads as a bug rather than a blackout. Listing `lights`
	-- explicitly opts out and wins.
	if not annotations.lights or #annotations.lights == 0 then
		local adopted = 0
		for _, descendant in house:GetDescendants() do
			if descendant:IsA("Light") then
				local host = descendant.Parent
				if
					host
					and host:IsA("BasePart")
					and not CollectionService:HasTag(host, Tags.HouseLight)
				then
					CollectionService:AddTag(host, Tags.HouseLight)
					adopted += 1
				end
			end
		end
		if adopted > 0 then
			print(`[HouseLoader] adopted {adopted} built-in light fixture(s) for Power Outage`)
		end
	end

	if annotations.atticHatch then
		local hatch = resolvePart(house, origin, annotations.atticHatch, "atticHatch")
		if hatch then
			-- Swing about the panel's -Z edge, matching the procedural house, and store both
			-- poses on the part so setAtticOpen stays data-driven.
			local hinge = hatch.CFrame * CFrame.new(0, 0, -hatch.Size.Z / 2)
			hatch:SetAttribute("ClosedCFrame", hatch.CFrame)
			hatch:SetAttribute(
				"OpenedCFrame",
				hinge * CFrame.Angles(math.rad(-105), 0, 0) * hinge:Inverse() * hatch.CFrame
			)
			CollectionService:AddTag(hatch, Tags.AtticHatch)
			CollectionService:AddTag(hatch, Tags.Door)
		end
	end

	if annotations.atticLadder then
		local ladder = resolvePart(house, origin, annotations.atticLadder, "atticLadder")
		if ladder then
			CollectionService:AddTag(ladder, Tags.AtticLadder)
		end
	end
end

--------------------------------------------------------------------------------------------------
-- Furniture
--------------------------------------------------------------------------------------------------

-- Anchor everything. A free model that ships unanchored falls through the floor on load, gets
-- shoved across the room by a pillow swing, and desyncs between clients. This is common enough
-- in Toolbox content that it is done unconditionally rather than trusted per-asset.
local function anchorAll(root: Instance): number
	local loosened = 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant.Anchored then
			descendant.Anchored = true
			loosened += 1
		end
	end
	return loosened
end

-- The prop is solid; the thing a player hides *inside* it is a non-collidable volume within it.
-- A well-prepared asset ships a child named "Trigger" (see ASSET_MANIFEST section 6); anything
-- else gets one synthesised so a half-prepared prop still works.
local function hidingTrigger(model: Instance, fallbackCFrame: CFrame): BasePart
	local existing = model:FindFirstChild("Trigger", true)
	if existing and existing:IsA("BasePart") then
		existing.CanCollide = false
		existing.Transparency = 1
		return existing
	end
	local trigger = Instance.new("Part")
	trigger.Name = "Trigger"
	trigger.Size = Vector3.new(4, 5, 4)
	trigger.CFrame = fallbackCFrame
	trigger.Transparency = 1
	trigger.CanCollide = false
	trigger.Anchored = true
	trigger.Parent = model
	return trigger
end

-- Clone props out of ServerStorage.FurnitureModels and place them in the house.
--
-- This is how the curated asset kit becomes gameplay. An imported house arrives unfurnished, so
-- there is no existing bed to tag as a bed zone and no pantry to hide in — the prop and its
-- gameplay role arrive together.
local function placeFurniture(house: Instance, origin: CFrame, list: any)
	if not list or #list == 0 then
		return
	end
	local library = ServerStorage:FindFirstChild(FURNITURE_FOLDER)

	local placed, fromKit = 0, 0
	for _, item in list do
		local cframe = origin
			* CFrame.new(item.at[1] or 0, item.at[2] or 0, item.at[3] or 0)
			* CFrame.Angles(0, math.rad(item.yaw or 0), 0)

		-- An approved import wins; otherwise fall back to the procedural greybox kit.
		--
		-- Same name, either source. That means a house can be fully playable on greybox props
		-- today, and each one upgrades to a real asset the moment a file of that name lands in
		-- assets/approved-imports/furniture/ — no config change, no re-measuring. It also means
		-- a missing asset degrades to a grey box rather than to a missing hiding spot.
		local prop: Instance?
		local template = library and library:FindFirstChild(item.model)
		if template then
			prop = template:Clone()
			if prop:IsA("Model") then
				(prop :: Model):PivotTo(cframe)
			elseif prop:IsA("BasePart") then
				(prop :: BasePart).CFrame = cframe
			end
		elseif Props.exists(item.model) then
			prop = (Props.build(item.model, cframe))
			fromKit += 1
		end

		if not prop then
			complain(
				`furniture: "{item.model}" is neither in ServerStorage.{FURNITURE_FOLDER} nor a `
					.. "known greybox prop kind"
			)
			continue
		end
		anchorAll(prop)
		prop.Parent = house
		CollectionService:AddTag(prop, Tags.Furniture)
		placed += 1

		-- One prop can carry several roles. A bed is both the thing Parent Check wants you in and
		-- the thing Hide & Seek wants you under, so `role` accepts a list as well as a string.
		local roles = if type(item.role) == "table" then item.role else { item.role }
		for _, role in roles do
			if role == "HidingSpot" then
				local trigger = hidingTrigger(prop, cframe * CFrame.new(0, 2.5, 0))
				tagHidingSpot(trigger, item.label or prop.Name)
			elseif role == "SnackSource" then
				local part = partFrom(prop, item.model, "furniture")
				if part then
					tagSnackSource(part, item.snack or item.model)
				end
			elseif role == "BedZone" then
				local part = partFrom(prop, item.model, "furniture")
				if part then
					CollectionService:AddTag(part, Tags.BedZone)
				end
			elseif role == "Light" then
				local part = partFrom(prop, item.model, "furniture")
				if part then
					CollectionService:AddTag(part, Tags.HouseLight)
				end
			elseif role == "Anchor" then
				tagAnchor(house, cframe, item.activity or "PillowFight", item.kind)
			elseif role ~= nil then
				complain(`furniture: "{item.model}" has unknown role "{role}"`)
			end
		end
	end

	if placed > 0 then
		print(
			`[HouseLoader] placed {placed} furniture prop(s), {fromKit} from the greybox kit `
				.. `(swap one in by dropping a matching name into {FURNITURE_FOLDER})`
		)
	end
end

--------------------------------------------------------------------------------------------------
-- Sourcing
--------------------------------------------------------------------------------------------------

-- Make sure the Toolbox drop folder exists so there is somewhere obvious to insert into. It is
-- created here rather than declared in the Rojo project precisely so Rojo will not manage it.
function HouseLoader.ensureToolboxFolder(): Folder
	local existing = ServerStorage:FindFirstChild(TOOLBOX_FOLDER)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = TOOLBOX_FOLDER
	folder.Parent = ServerStorage
	return folder
end

-- Toolbox drops win over synced ones, so you can prototype with an insert and later export the
-- same name to assets/approved-imports/houses/ without editing config.
local function findTemplate(modelName: string): (Instance?, string?)
	for _, folderName in { TOOLBOX_FOLDER, SYNCED_FOLDER } do
		local folder = ServerStorage:FindFirstChild(folderName)
		local template = folder and folder:FindFirstChild(modelName)
		if template then
			return template, folderName
		end
	end
	return nil, nil
end

-- A house is geometry. Free Toolbox models are a well-known carrier for backdoor scripts, and
-- nothing about a house needs code to run, so strip it unless the map explicitly opts in.
local function stripScripts(house: Instance): number
	local removed = 0
	for _, descendant in house:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			removed += 1
			descendant:Destroy()
		end
	end
	return removed
end

--------------------------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------------------------

-- Report what the loaded house can and cannot support, so a half-wired model announces itself at
-- startup instead of as "Hide & Seek does nothing" mid-playtest.
local function validate(house: Instance)
	local function countTagged(tag: string): number
		local n = 0
		for _, instance in CollectionService:GetTagged(tag) do
			if instance:IsDescendantOf(house) then
				n += 1
			end
		end
		return n
	end

	local hiding = countTagged(Tags.HidingSpot)
	local snacks = countTagged(Tags.SnackSource)
	local beds = countTagged(Tags.BedZone)
	local spawns = countTagged(Tags.SpawnPoint)

	if spawns == 0 then
		complain("no spawn points — players will fall out of the world")
	end
	if hiding < 2 then
		complain(`only {hiding} hiding spots — Hide & Seek and Parent Check need several`)
	end
	if snacks == 0 then
		complain("no snack sources — Midnight Snack cannot be completed")
	end
	if beds == 0 then
		complain("no bed zones — Parent Check cannot be completed")
	end

	for _, activity in
		{ "PillowFight", "ParentCheck", "MidnightSnack", "HideAndSeek", "GhostStory" }
	do
		if
			not HouseBuilder.getAnchor(house, activity)
			and not HouseBuilder.getAnchor(house, activity, "gather")
		then
			complain(`no anchor for {activity} — it will fall back to a default position`)
		end
	end

	print(
		`[HouseLoader] "{currentMapId}" ready: {spawns} spawns, {hiding} hiding spots, `
			.. `{snacks} snacks, {beds} beds, {#problems} problem(s)`
	)
end

--------------------------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------------------------

-- Build or load the configured house and return it. Safe to call repeatedly; replaces any
-- existing House in Workspace.
function HouseLoader.load(mapId: string?): Instance
	table.clear(problems)
	local id = mapId or MapConfig.default
	local map = MapConfig.get(id)

	if not map then
		warn(`[HouseLoader] unknown map "{id}", falling back to the procedural house`)
		currentMapId = "Greybox"
		return HouseBuilder.build()
	end

	currentMapId = map.id

	if map.source == "Procedural" then
		return HouseBuilder.build()
	end

	HouseLoader.ensureToolboxFolder()
	local template, foundIn = findTemplate(map.model or "")
	if not template then
		warn(
			`[HouseLoader] map "{id}" wants a model named "{map.model}", which is in neither `
				.. `ServerStorage.{TOOLBOX_FOLDER} nor ServerStorage.{SYNCED_FOLDER}. Falling back `
				.. "to the procedural house. Insert it from the Toolbox into "
				.. `ServerStorage.{TOOLBOX_FOLDER} and save the place, or put a .rbxmx in `
				.. "assets/approved-imports/houses/ and re-sync."
		)
		currentMapId = "Greybox"
		return HouseBuilder.build()
	end

	local existing = Workspace:FindFirstChild("House")
	if existing then
		existing:Destroy()
	end
	-- Same template cleanup HouseBuilder does: a stock Baseplate is coplanar with most house
	-- floors and z-fights, and a stray SpawnLocation competes with the map's own.
	for _, child in Workspace:GetChildren() do
		if child:IsA("SpawnLocation") or (child:IsA("BasePart") and child.Name == "Baseplate") then
			child:Destroy()
		end
	end

	local house = template:Clone()
	house.Name = "House"

	if not map.allowScripts then
		local removed = stripScripts(house)
		if removed > 0 then
			warn(
				`[HouseLoader] stripped {removed} script(s) from "{map.model}". A house model `
					.. "should be geometry only; set allowScripts on the map if you have read "
					.. "them and want them kept."
			)
		end
	end

	local loosened = anchorAll(house)
	if loosened > 0 then
		warn(`[HouseLoader] anchored {loosened} loose part(s) in "{map.model}"`)
	end

	house.Parent = Workspace
	print(`[HouseLoader] loaded "{map.model}" from ServerStorage.{foundIn}`)

	-- Measured before anything is added, so markers and props cannot drag the frame around.
	local origin = originOf(house)

	annotate(house, origin, map.annotations)
	if map.annotations then
		placeFurniture(house, origin, map.annotations.furniture)
	end
	validate(house)
	return house
end

function HouseLoader.getCurrentMapId(): string?
	return currentMapId
end

-- Problems found during the last load. Empty means the house is fully wired.
function HouseLoader.getProblems(): { string }
	return table.clone(problems)
end

return HouseLoader
