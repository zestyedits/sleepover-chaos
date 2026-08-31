--!strict
-- NPCManager — fills the sleepover with NPC guests so a solo player still has a party
-- (GDD §13). Behavior is deliberately basic: walk to the current phase/activity anchor, idle,
-- and react to a couple of events. No human-like AI. NPCs despawn as real players join so the
-- party stays near target size.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.config.GameConfig)
local Tags = require(Shared.Tags)

local HouseBuilder = require(script.Parent.Parent.world.HouseBuilder)

local NPCManager = {}

local NPC_NAMES = { "Ava", "Max", "Zoe", "Leo", "Mia", "Kai", "Ivy", "Ben", "Luna", "Finn" }
local guests: { Model } = {}
local guestFolder: Folder?
local currentTarget: Vector3? = nil

local function ensureFolder(): Folder
	if guestFolder and guestFolder.Parent then
		return guestFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "NPCGuests"
	folder.Parent = Workspace
	guestFolder = folder
	return folder
end

-- Build a very simple blocky guest rig (no external character assets needed).
local function buildGuest(name: string): Model
	local model = Instance.new("Model")
	model.Name = `Guest_{name}`

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CanCollide = false
	root.Parent = model

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.Color = Color3.fromHSV(math.random(), 0.6, 0.9)
	torso.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Color = Color3.new(1, 0.87, 0.73)
	head.Parent = model

	local legs = Instance.new("Part")
	legs.Name = "Legs"
	legs.Size = Vector3.new(2, 2, 1)
	legs.Color = Color3.new(0.3, 0.3, 0.4)
	legs.Parent = model

	-- Weld the blocks to the root.
	local function weld(part: Part, offset: CFrame)
		part.Anchored = false
		part.CanCollide = false
		local w = Instance.new("Weld")
		w.Part0 = root
		w.Part1 = part
		w.C0 = offset
		w.Parent = root
	end
	weld(torso, CFrame.new(0, 0, 0))
	weld(head, CFrame.new(0, 1.6, 0))
	weld(legs, CFrame.new(0, -2, 0))
	root.CanCollide = false

	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.WalkSpeed = 12
	humanoid.Parent = model

	local nameTag = Instance.new("BillboardGui")
	nameTag.Size = UDim2.fromScale(4, 1)
	nameTag.StudsOffset = Vector3.new(0, 3, 0)
	nameTag.AlwaysOnTop = true
	nameTag.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = name
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.Parent = nameTag

	model.PrimaryPart = root
	CollectionService:AddTag(model, Tags.NPCGuest)
	return model
end

local function spawnGuest()
	if #guests >= (GameConfig.targetPartySize - 1) then
		return
	end
	local name = NPC_NAMES[(#guests % #NPC_NAMES) + 1]
	local guest = buildGuest(name)

	-- Place at a spawn point.
	local house = Workspace:FindFirstChild("House")
	local spawnPos = Vector3.new(0, 5, 0)
	if house then
		local spawns = house:FindFirstChild("Spawns")
		if spawns then
			local list = spawns:GetChildren()
			local chosen = list[math.random(1, math.max(#list, 1))]
			if chosen and chosen:IsA("BasePart") then
				spawnPos = chosen.Position + Vector3.new(0, 3, 0)
			end
		end
	end
	guest:PivotTo(CFrame.new(spawnPos))
	guest.Parent = ensureFolder()
	table.insert(guests, guest)

	-- Simple wander/gather loop.
	task.spawn(function()
		while guest.Parent do
			local humanoid = guest:FindFirstChildOfClass("Humanoid")
			local root = guest.PrimaryPart
			if not humanoid or not root then
				break
			end
			local goal: Vector3
			if currentTarget then
				-- Gather loosely around the current activity anchor.
				goal = currentTarget + Vector3.new(math.random(-8, 8), 0, math.random(-8, 8))
			else
				-- Idle wander near the house center.
				goal = root.Position + Vector3.new(math.random(-12, 12), 0, math.random(-12, 12))
			end
			humanoid:MoveTo(goal)
			humanoid.MoveToFinished:Wait()
			task.wait(math.random(1, 3))
		end
	end)
end

local function despawnGuest()
	local guest = table.remove(guests)
	if guest then
		guest:Destroy()
	end
end

-- Keep guest count so that (real players + guests) ~ targetPartySize (GDD §13).
local function rebalance()
	local realCount = #Players:GetPlayers()
	local desiredGuests = math.max(0, GameConfig.targetPartySize - realCount)
	while #guests < desiredGuests do
		spawnGuest()
	end
	while #guests > desiredGuests do
		despawnGuest()
	end
end

-- Called by managers so NPCs congregate where the action is.
function NPCManager.setGatherPoint(position: Vector3?)
	currentTarget = position
end

-- React to events (GDD §13 "react to events"). Very light-touch.
function NPCManager.reactScatter()
	for _, guest in guests do
		local humanoid = guest:FindFirstChildOfClass("Humanoid")
		local root = guest.PrimaryPart
		if humanoid and root then
			humanoid:MoveTo(
				root.Position + Vector3.new(math.random(-20, 20), 0, math.random(-20, 20))
			)
		end
	end
end

function NPCManager.start()
	rebalance()
	Players.PlayerAdded:Connect(rebalance)
	Players.PlayerRemoving:Connect(function()
		task.defer(rebalance)
	end)
end

return NPCManager
