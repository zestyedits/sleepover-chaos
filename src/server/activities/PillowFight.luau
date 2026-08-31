--!strict
-- PillowFight (GDD §6) — free-for-all, whack people with pillows for points, silly knockback.
-- Rare MEGA PILLOW FIGHT variant doubles points and cranks the chaos.
--
-- Every hit is decided on the server from character positions. `Tool.Activated` is the only thing
-- the client gets to assert, and "I swung" is all it means — never who was hit. A swing has to
-- clear four gates before it scores:
--
--   equipped   the tool is actually held, not sitting in a backpack
--   cooldown   per-attacker swing rate, plus per-victim immunity frames
--   facing     the victim is inside a ~70° cone in front of the attacker
--   sightline  no solid house geometry between them
--
-- ...and then exactly ONE victim (the closest) is hit. The old version scored against everyone in
-- range on every click, through walls and floors, which in a two-story house means the upstairs
-- bedroom is inside living-room range.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ActivityBase = require(Shared.framework.ActivityBase)
local RandomUtil = require(Shared.util.RandomUtil)

local NPCManager = require(script.Parent.Parent.systems.NPCManager)

local HIT_RANGE = 7
local SWING_COOLDOWN = 0.5 -- per attacker
local VICTIM_IFRAME = 0.6 -- per victim, so nobody gets chain-ragdolled or farmed
local FACING_DOT = 0.35 -- ~70° cone; you have to swing AT someone
local SPAM_ACTIVATIONS_PER_SECOND = 8 -- hard ceiling before we do any raycast work

local NPC_REACTIONS = {
	"AAAH!",
	"my hair!!",
	"not fair!",
	"pillow war!!",
	"ow ow ow",
}

local function rootOf(model: Instance?): BasePart?
	if not model then
		return nil
	end
	local root = (model :: Instance):FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

local function equipPillow(player: Player, trove: any): Tool?
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = "Pillow"
	tool.RequiresHandle = true
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(3, 1.5, 2)
	handle.Color = Color3.new(0.95, 0.9, 0.95)
	handle.Material = Enum.Material.Fabric
	handle.Parent = tool

	tool.Parent = backpack
	trove:Add(tool)
	return tool
end

-- Bodies are not walls: only genuinely solid house geometry should block a swing. Excluding all
-- characters and NPCs, and respecting CanCollide, keeps invisible triggers (activity anchors, bed
-- zones, hiding-spot volumes) from silently eating hits.
local function buildSightlineParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.RespectCanCollide = true

	local exclude: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	local guestFolder = Workspace:FindFirstChild("NPCGuests")
	if guestFolder then
		table.insert(exclude, guestFolder)
	end
	params.FilterDescendantsInstances = exclude
	return params
end

local function hasSightline(from: Vector3, to: Vector3, params: RaycastParams): boolean
	local delta = to - from
	return Workspace:Raycast(from, delta, params) == nil
end

return ActivityBase.extend("PillowFight", {
	onStart = function(ctx)
		local settings = ctx.config
		local mega = RandomUtil.chance(settings.megaChance or 0)
		local pointsPerHit = settings.pointsPerHit or 2
		local pointsPerNpcHit = settings.pointsPerNpcHit or 1
		if mega then
			pointsPerHit *= settings.megaPointMultiplier or 2
			pointsPerNpcHit *= settings.megaPointMultiplier or 2
			ctx.result.tags.mega = true
			ctx.announce("MEGA PILLOW FIGHT!!! The living room is chaos!", "chaos")
		else
			ctx.announce("Pillow Fight! Whack everyone!", "event")
		end

		local lastSwing: { [Player]: number } = {}
		local lastHit: { [Instance]: number } = {}
		local activationWindow: { [Player]: { count: number, since: number } } = {}

		local function armPlayer(player: Player)
			local tool = equipPillow(player, ctx.trove)
			if not tool then
				return
			end

			ctx.trove:Connect(tool.Activated, function()
				local now = os.clock()

				-- Cheap spam gate first: never let a click-spammer buy raycasts.
				local window = activationWindow[player]
				if not window or now - window.since >= 1 then
					activationWindow[player] = { count = 1, since = now }
				else
					window.count += 1
					if window.count > SPAM_ACTIVATIONS_PER_SECOND then
						return
					end
				end

				-- The tool must actually be held. A backpack tool firing Activated is not a swing.
				if tool.Parent ~= player.Character then
					return
				end
				if lastSwing[player] and now - lastSwing[player] < SWING_COOLDOWN then
					return
				end

				local attackerRoot = rootOf(player.Character)
				if not attackerRoot then
					return
				end
				lastSwing[player] = now

				local origin = attackerRoot.Position
				local look = attackerRoot.CFrame.LookVector
				local params = buildSightlineParams()

				-- Gather every candidate, then commit to exactly one: the closest that passes.
				local bestRoot: BasePart? = nil
				local bestDistance = math.huge
				local bestPlayer: Player? = nil
				local bestModel: Instance? = nil

				local function consider(model: Instance, victimPlayer: Player?)
					local root = rootOf(model)
					if not root then
						return
					end
					local key: Instance = victimPlayer or model
					if lastHit[key] and now - lastHit[key] < VICTIM_IFRAME then
						return
					end
					local delta = root.Position - origin
					local distance = delta.Magnitude
					if distance > HIT_RANGE or distance <= 0.01 or distance >= bestDistance then
						return
					end
					if look:Dot(delta.Unit) < FACING_DOT then
						return
					end
					if not hasSightline(origin, root.Position, params) then
						return
					end
					bestRoot, bestDistance, bestPlayer, bestModel =
						root, distance, victimPlayer, model
				end

				for _, other in ctx.players do
					if other ~= player and other.Character then
						consider(other.Character, other)
					end
				end
				-- NPC guests are legitimate targets, worth less than a real player. This is what
				-- lets a solo player actually play Pillow Fight instead of swinging at air.
				for _, guest in NPCManager.getGuests() do
					consider(guest, nil)
				end

				if not bestRoot then
					return
				end

				local push = (bestRoot.Position - origin).Unit * (if mega then 60 else 30)
					+ Vector3.new(0, if mega then 30 else 15, 0)

				if bestPlayer then
					lastHit[bestPlayer] = now
					ctx.addScore(player, pointsPerHit)
					bestRoot.AssemblyLinearVelocity = push
				elseif bestModel then
					lastHit[bestModel] = now
					ctx.addScore(player, pointsPerNpcHit)
					NPCManager.bump(bestModel :: Model, push)
					NPCManager.say(
						bestModel :: Model,
						NPC_REACTIONS[math.random(1, #NPC_REACTIONS)]
					)
				end
			end)
		end

		for _, player in ctx.players do
			armPlayer(player)
		end

		-- Late arrivals get a pillow too. Without this a second Studio client that loads after
		-- onStart just watches, which is exactly the two-player playtest case.
		local active = true
		ctx.trove:AddCleanup(function()
			active = false
		end)
		ctx.onPlayerJoined(function(player)
			ctx.trove:Add(task.spawn(function()
				if player:WaitForChild("Backpack", 10) and active then
					armPlayer(player)
				end
			end))
		end)

		NPCManager.setBehavior("Gather")
	end,

	onFinish = function(ctx)
		-- Winner = highest score. Flag the win-only scrapbook memory + stat.
		local best, winner = 0, nil
		for uid, score in ctx.result.scores do
			if score > best then
				best = score
				winner = Players:GetPlayerByUserId(uid)
			end
		end
		if winner and best > 0 then
			table.insert(ctx.result.winners, winner)
			ctx.result.winnerScrapbook = { "won_pillow_fight" }
			ctx.result.winnerStats = { pillowFightWins = 1 }
			ctx.announce(`{winner.Name} won the pillow fight with {best} points!`, "result")
		else
			ctx.announce("Pillow fight over. Nobody landed a thing.", "result")
		end
	end,

	onCleanup = function(_ctx)
		NPCManager.setBehavior("Idle")
	end,
})
