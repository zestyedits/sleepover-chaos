--!strict
-- NPCManager — fills the sleepover with NPC guests so a solo player still has a party (GDD §13).
--
-- Guests are built as REAL R6 rigs. The previous version welded four parts together with
-- CanCollide = false on all of them, which looks like a character but is not one: a Humanoid
-- needs a Motor6D joint hierarchy and something collidable underneath it before its state machine
-- will ground itself. Without that the whole party free-falls through the floor on spawn.
--
-- Movement goes through PathfindingService, not bare Humanoid:MoveTo. The house has real
-- doorways and a staircase, and a straight-line MoveTo just walks a guest into a wall and stalls.
--
-- Behaviour is deliberately shallow — guests are atmosphere, not opponents. They gather where the
-- action is, claim a hiding spot during Hide & Seek, go to bed during Parent Check, scatter when
-- the lights die, and can be whacked in a pillow fight. That is enough to make solo feel like a
-- sleepover instead of an empty house.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.config.GameConfig)
local Tags = require(Shared.Tags)
local Trove = require(Shared.util.Trove)

local NPCManager = {}

export type Behavior = "Idle" | "Gather" | "Hide" | "Bed" | "Scatter"

local NPC_NAMES = { "Ava", "Max", "Zoe", "Leo", "Mia", "Kai", "Ivy", "Ben", "Luna", "Finn" }
local SHIRT_COLORS = {
	Color3.fromRGB(244, 143, 177),
	Color3.fromRGB(129, 199, 132),
	Color3.fromRGB(100, 181, 246),
	Color3.fromRGB(255, 213, 79),
	Color3.fromRGB(186, 143, 244),
}

local WAYPOINT_TIMEOUT = 4
local ARRIVAL_DISTANCE = 4
local BUBBLE_SECONDS = 2.5

local guests: { Model } = {}
local troves: { [Model]: any } = {}
local assignments: { [Model]: BasePart } = {} -- sticky Hide/Bed target per guest
local guestFolder: Folder? = nil
local currentBehavior: Behavior = "Idle"
local currentTarget: Vector3? = nil

--------------------------------------------------------------------------------------------------
-- Rig construction
--------------------------------------------------------------------------------------------------

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

local function makeLimb(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = true
	part.Parent = parent
	return part
end

local function joint(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = c0
	motor.C1 = c1
	motor.Parent = part0
end

-- The canonical R6 joint frames. These exact offsets are what make the Humanoid stand, walk, and
-- animate correctly; approximating them produces a rig that T-poses or sinks into the floor.
local function buildGuest(name: string, shirt: Color3): Model
	local model = Instance.new("Model")
	model.Name = `Guest_{name}`

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	-- Verified in Studio: once the Humanoid binds an R6 rig the engine normalises limb collision
	-- itself, ending up with Torso + Head collidable and root/arms/legs off. Setting CanCollide
	-- on the limbs below is therefore harmless, and what matters is only that SOMETHING is
	-- collidable — the old welded rig had zero, which is why the party fell through the floor.
	root.CanCollide = false
	root.Parent = model

	local torso = makeLimb("Torso", Vector3.new(2, 2, 1), shirt, model)
	local head = makeLimb("Head", Vector3.new(2, 1, 1), Color3.fromRGB(255, 222, 189), model)
	local leftArm = makeLimb("Left Arm", Vector3.new(1, 2, 1), Color3.fromRGB(255, 222, 189), model)
	local rightArm =
		makeLimb("Right Arm", Vector3.new(1, 2, 1), Color3.fromRGB(255, 222, 189), model)
	local pants = Color3.fromRGB(70, 72, 92)
	local leftLeg = makeLimb("Left Leg", Vector3.new(1, 2, 1), pants, model)
	local rightLeg = makeLimb("Right Leg", Vector3.new(1, 2, 1), pants, model)

	local upright = CFrame.fromEulerAnglesXYZ(-math.pi / 2, 0, math.pi)
	local rightFacing = CFrame.fromEulerAnglesXYZ(0, math.pi / 2, 0)
	local leftFacing = CFrame.fromEulerAnglesXYZ(0, -math.pi / 2, 0)

	joint("RootJoint", root, torso, upright, upright)
	joint("Neck", torso, head, CFrame.new(0, 1, 0) * upright, CFrame.new(0, -0.5, 0) * upright)
	joint(
		"Right Shoulder",
		torso,
		rightArm,
		CFrame.new(1, 0.5, 0) * rightFacing,
		CFrame.new(-0.5, 0.5, 0) * rightFacing
	)
	joint(
		"Left Shoulder",
		torso,
		leftArm,
		CFrame.new(-1, 0.5, 0) * leftFacing,
		CFrame.new(0.5, 0.5, 0) * leftFacing
	)
	joint(
		"Right Hip",
		torso,
		rightLeg,
		CFrame.new(1, -1, 0) * rightFacing,
		CFrame.new(0.5, 1, 0) * rightFacing
	)
	joint(
		"Left Hip",
		torso,
		leftLeg,
		CFrame.new(-1, -1, 0) * leftFacing,
		CFrame.new(-0.5, 1, 0) * leftFacing
	)

	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head

	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.WalkSpeed = 12
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model

	local animator = Instance.new("Animator")
	animator.Parent = humanoid

	local nameTag = Instance.new("BillboardGui")
	nameTag.Name = "NameTag"
	nameTag.Size = UDim2.fromScale(4, 1)
	nameTag.StudsOffset = Vector3.new(0, 2.4, 0)
	nameTag.AlwaysOnTop = true
	nameTag.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = name
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.Parent = nameTag

	model.PrimaryPart = root
	CollectionService:AddTag(model, Tags.NPCGuest)
	return model
end

--------------------------------------------------------------------------------------------------
-- Movement
--------------------------------------------------------------------------------------------------

-- Walk to one point and report whether we got there. Deliberately polls instead of waiting on
-- MoveToFinished: if the guest is despawned mid-walk that signal never fires and the behaviour
-- thread would park forever.
local function stepTo(guest: Model, humanoid: Humanoid, root: BasePart, goal: Vector3): boolean
	humanoid:MoveTo(goal)
	local deadline = os.clock() + WAYPOINT_TIMEOUT
	while os.clock() < deadline do
		if not guest.Parent or not humanoid.Parent then
			return false
		end
		if (root.Position - goal).Magnitude <= ARRIVAL_DISTANCE then
			return true
		end
		task.wait(0.15)
	end
	return false
end

local function walkTo(guest: Model, humanoid: Humanoid, root: BasePart, goal: Vector3)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		AgentMaxSlope = 45,
	})

	local computed = pcall(function()
		path:ComputeAsync(root.Position, goal)
	end)

	if not computed or path.Status ~= Enum.PathStatus.Success then
		-- No route (goal inside furniture, guest stuck in a doorway). Nudge directly and let the
		-- next behaviour tick try again rather than freezing the guest in place.
		stepTo(guest, humanoid, root, goal)
		return
	end

	for _, waypoint in path:GetWaypoints() do
		if not guest.Parent then
			return
		end
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		if not stepTo(guest, humanoid, root, waypoint.Position) then
			return -- lost the path; recompute on the next tick
		end
	end
end

--------------------------------------------------------------------------------------------------
-- Goals per behaviour
--------------------------------------------------------------------------------------------------

local function taggedParts(tag: string): { BasePart }
	local parts = {}
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("BasePart") then
			table.insert(parts, instance)
		end
	end
	return parts
end

-- Claim a spot no other guest has taken, so the party spreads across the house instead of
-- stacking on one bed.
local function claim(guest: Model, tag: string): BasePart?
	local existing = assignments[guest]
	if existing and existing.Parent then
		return existing
	end

	local taken: { [BasePart]: boolean } = {}
	for other, part in assignments do
		if other ~= guest then
			taken[part] = true
		end
	end

	local options = taggedParts(tag)
	local free = {}
	for _, part in options do
		if not taken[part] then
			table.insert(free, part)
		end
	end
	local pool = if #free > 0 then free else options
	if #pool == 0 then
		return nil
	end
	local chosen = pool[math.random(1, #pool)]
	assignments[guest] = chosen
	return chosen
end

local function goalFor(guest: Model, root: BasePart): Vector3?
	if currentBehavior == "Gather" and currentTarget then
		return currentTarget + Vector3.new(math.random(-8, 8), 0, math.random(-8, 8))
	elseif currentBehavior == "Hide" then
		local spot = claim(guest, Tags.HidingSpot)
		return spot and spot.Position or nil
	elseif currentBehavior == "Bed" then
		local bed = claim(guest, Tags.BedZone)
		return bed and bed.Position or nil
	elseif currentBehavior == "Scatter" then
		return root.Position + Vector3.new(math.random(-24, 24), 0, math.random(-24, 24))
	end
	-- Idle: mill around wherever you are.
	return root.Position + Vector3.new(math.random(-12, 12), 0, math.random(-12, 12))
end

local function behaviorLoop(guest: Model)
	while guest.Parent do
		local humanoid = guest:FindFirstChildOfClass("Humanoid")
		local root = guest.PrimaryPart
		if not humanoid or not root then
			return
		end

		local goal = goalFor(guest, root)
		if goal then
			walkTo(guest, humanoid, root, goal)
		end

		-- Guests that have arrived somewhere they are supposed to stay (a bed, a hiding spot)
		-- wait longer, so they settle instead of jittering in place.
		local settled = currentBehavior == "Hide" or currentBehavior == "Bed"
		task.wait(if settled then math.random(4, 7) else math.random(1, 3))
	end
end

--------------------------------------------------------------------------------------------------
-- Spawning
--------------------------------------------------------------------------------------------------

local function spawnPosition(): Vector3
	local house = Workspace:FindFirstChild("House")
	local spawns = house and house:FindFirstChild("Spawns")
	if spawns then
		local list = spawns:GetChildren()
		if #list > 0 then
			local chosen = list[math.random(1, #list)]
			if chosen:IsA("BasePart") then
				return chosen.Position + Vector3.new(math.random(-4, 4), 4, math.random(-4, 4))
			end
		end
	end
	return Vector3.new(0, 6, 0)
end

local function spawnGuest()
	local index = #guests + 1
	local name = NPC_NAMES[((index - 1) % #NPC_NAMES) + 1]
	local guest = buildGuest(name, SHIRT_COLORS[((index - 1) % #SHIRT_COLORS) + 1])

	guest:PivotTo(CFrame.new(spawnPosition()))
	guest.Parent = ensureFolder()
	table.insert(guests, guest)

	-- One trove per guest owns its behaviour thread. Previously the thread was untracked, so a
	-- guest despawned mid-walk left a coroutine parked on a signal that would never fire again.
	local guestTrove = Trove.new()
	troves[guest] = guestTrove
	guestTrove:Add(guest)
	guestTrove:Add(task.spawn(function()
		behaviorLoop(guest)
	end))
end

local function despawnGuest()
	local guest = table.remove(guests)
	if not guest then
		return
	end
	assignments[guest] = nil
	local guestTrove = troves[guest]
	troves[guest] = nil
	if guestTrove then
		guestTrove:Clean()
	else
		guest:Destroy()
	end
end

-- Keep guest count so that (real players + guests) ~ targetPartySize (GDD §13).
local function rebalance()
	local desiredGuests = math.max(0, GameConfig.targetPartySize - #Players:GetPlayers())
	while #guests < desiredGuests do
		spawnGuest()
	end
	while #guests > desiredGuests do
		despawnGuest()
	end
end

--------------------------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------------------------

function NPCManager.getGuests(): { Model }
	local live = {}
	for _, guest in guests do
		if guest.Parent then
			table.insert(live, guest)
		end
	end
	return live
end

-- Speech bubble over one guest. Rolled by hand rather than via the legacy Chat service, which
-- does nothing when the experience uses TextChatService.
function NPCManager.say(guest: Model, text: string)
	local head = guest:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local existing = head:FindFirstChild("SpeechBubble")
	if existing then
		existing:Destroy()
	end

	local bubble = Instance.new("BillboardGui")
	bubble.Name = "SpeechBubble"
	bubble.Size = UDim2.fromScale(6, 1.4)
	bubble.StudsOffset = Vector3.new(0, 4, 0)
	bubble.AlwaysOnTop = true
	bubble.Parent = head

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 0.1
	frame.Parent = bubble
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.9, 0.8)
	label.Position = UDim2.fromScale(0.05, 0.1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(40, 40, 55)
	label.Text = text
	label.Parent = frame

	-- Debris rather than the guest's trove: a guest can be whacked dozens of times in one pillow
	-- fight, and troving each bubble would grow that trove for the guest's whole life. The bubble
	-- is parented to the head, so it also dies with the guest either way.
	Debris:AddItem(bubble, BUBBLE_SECONDS)
end

-- Everyone reacts at once: a line and a little hop.
function NPCManager.react(line: string)
	for _, guest in NPCManager.getGuests() do
		NPCManager.say(guest, line)
		local humanoid = guest:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Jump = true
		end
	end
end

-- Knock a guest around (pillow hits).
function NPCManager.bump(guest: Model, impulse: Vector3)
	local root = guest.PrimaryPart
	if root then
		root.AssemblyLinearVelocity = impulse
	end
end

-- Switch what the whole party is doing. `position` only matters for "Gather".
function NPCManager.setBehavior(behavior: Behavior, position: Vector3?)
	if behavior ~= currentBehavior then
		table.clear(assignments) -- sticky spot claims belong to one behaviour only
	end
	currentBehavior = behavior
	if position then
		currentTarget = position
	elseif behavior ~= "Gather" then
		currentTarget = nil
	end
end

-- Back-compat wrappers so existing callers keep working.
function NPCManager.setGatherPoint(position: Vector3?)
	if position then
		NPCManager.setBehavior("Gather", position)
	else
		NPCManager.setBehavior("Idle")
	end
end

function NPCManager.reactScatter()
	NPCManager.setBehavior("Scatter")
	NPCManager.react("AAAAH!")
end

function NPCManager.start()
	rebalance()
	Players.PlayerAdded:Connect(function()
		rebalance()
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(rebalance)
	end)
end

return NPCManager
