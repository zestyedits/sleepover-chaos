--!strict
-- HouseLoader — the one entry point for "put a house in the world".
--
-- Two sources, one output contract. A PROCEDURAL map is emitted by HouseBuilder; a MODEL map is
-- cloned out of ServerStorage.HouseModels and then ANNOTATED — we walk MapConfig's paths and
-- apply the same CollectionService tags HouseBuilder would have applied itself.
--
-- Downstream nothing knows or cares which happened. Hide & Seek asks for SC_HidingSpot and gets
-- an answer either way, which is the whole reason gameplay was written against tags instead of
-- geometry in the first place.
--
-- Annotation is deliberately noisy on failure: a path that does not resolve is a warning at
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

local HouseLoader = {}

local currentMapId: string? = nil
local problems: { string } = {}

local function complain(message: string)
	table.insert(problems, message)
	warn(`[HouseLoader] {message}`)
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

local function resolvePart(root: Instance, path: string, role: string): BasePart?
	local node = resolve(root, path)
	if not node then
		complain(`{role}: no instance at "{path}"`)
		return nil
	end
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
	complain(`{role}: "{path}" is a {node.ClassName} with no usable BasePart`)
	return nil
end

--------------------------------------------------------------------------------------------------
-- Annotation
--------------------------------------------------------------------------------------------------

local function annotate(house: Instance, annotations: any)
	if not annotations then
		return
	end

	for _, room in annotations.rooms or {} do
		local node = resolve(house, room.path)
		if not node then
			complain(`room: no instance at "{room.path}"`)
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

	for _, path in annotations.spawns or {} do
		local node = resolve(house, path)
		if not node then
			complain(`spawn: no instance at "{path}"`)
			continue
		end
		if node:IsA("SpawnLocation") then
			node.Neutral = true
			node.Duration = 0
			CollectionService:AddTag(node, Tags.SpawnPoint)
		elseif node:IsA("BasePart") then
			-- A plain part is fine as a marker; give it a real SpawnLocation on top.
			local spawn = Instance.new("SpawnLocation")
			spawn.Name = `Spawn_{node.Name}`
			spawn.Size = Vector3.new(6, 1, 6)
			spawn.Transparency = 1
			spawn.CanCollide = false
			spawn.Anchored = true
			spawn.Neutral = true
			spawn.Duration = 0
			spawn.CFrame = node.CFrame + Vector3.new(0, node.Size.Y / 2 + 3, 0)
			spawn.Parent = node
			CollectionService:AddTag(spawn, Tags.SpawnPoint)
		else
			complain(`spawn: "{path}" is a {node.ClassName}, expected a part or SpawnLocation`)
		end
	end

	for _, anchor in annotations.anchors or {} do
		local part = resolvePart(house, anchor.path, "anchor")
		if part then
			-- Anchors are markers, not geometry: an invisible child avoids repurposing a solid
			-- prop and lets several activities share one location.
			local marker = Instance.new("Part")
			marker.Name = `{anchor.activity}Anchor`
			marker.Size = Vector3.new(2, 2, 2)
			marker.CFrame = part.CFrame
			marker.Transparency = 1
			marker.CanCollide = false
			marker.Anchored = true
			marker:SetAttribute("Activity", anchor.activity)
			marker:SetAttribute("Kind", anchor.kind or "main")
			marker.Parent = house
			CollectionService:AddTag(marker, Tags.ActivityAnchor)
		end
	end

	for _, spot in annotations.hidingSpots or {} do
		local part = resolvePart(house, spot.path, "hidingSpot")
		if part then
			part:SetAttribute("Role", "Hide")
			part:SetAttribute("Label", spot.label)
			part:SetAttribute("ActionText", "Hide")
			CollectionService:AddTag(part, Tags.HidingSpot)
			CollectionService:AddTag(part, Tags.Interactable)
		end
	end

	for _, source in annotations.snackSources or {} do
		local part = resolvePart(house, source.path, "snackSource")
		if part then
			part:SetAttribute("Role", "Snack")
			part:SetAttribute("Snack", source.snack)
			part:SetAttribute("Label", source.snack)
			part:SetAttribute("ActionText", "Grab")
			-- MidnightSnack restores to this after a raid.
			part:SetAttribute("BaseTransparency", part.Transparency)
			CollectionService:AddTag(part, Tags.SnackSource)
			CollectionService:AddTag(part, Tags.Interactable)
		end
	end

	for _, path in annotations.bedZones or {} do
		local part = resolvePart(house, path, "bedZone")
		if part then
			CollectionService:AddTag(part, Tags.BedZone)
		end
	end

	for _, path in annotations.lights or {} do
		local part = resolvePart(house, path, "light")
		if part then
			CollectionService:AddTag(part, Tags.HouseLight)
		end
	end

	if annotations.atticHatch then
		local hatch = resolvePart(house, annotations.atticHatch, "atticHatch")
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
		local ladder = resolvePart(house, annotations.atticLadder, "atticLadder")
		if ladder then
			CollectionService:AddTag(ladder, Tags.AtticLadder)
		end
	end
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

	local library = ServerStorage:FindFirstChild("HouseModels")
	local template = library and map.model and library:FindFirstChild(map.model)
	if not template then
		warn(
			`[HouseLoader] map "{id}" wants model "{map.model}" in ServerStorage.HouseModels, `
				.. "which is not there — falling back to the procedural house. Drop the .rbxmx "
				.. "into assets/houses/ and re-sync."
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
	house.Parent = Workspace

	annotate(house, map.annotations)
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
