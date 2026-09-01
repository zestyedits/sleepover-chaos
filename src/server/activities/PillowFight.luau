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
local Participant = require(Shared.Participant)
local RandomUtil = require(Shared.util.RandomUtil)

type Participant = Participant.Participant

local BotDriver = require(script.Parent.Parent.systems.BotDriver)
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
	-- Ask NPCManager for the guests rather than looking up a folder by name. A name lookup finds
	-- whichever "NPCGuests" folder happens to be first, and if a stale one is ever left in the
	-- Workspace the swing raycast silently filters the wrong set -- every guest becomes a wall and
	-- no bot can be hit. Same failure mode as the spawn-folder bug: ask the owner, not the tree.
	for _, guest in NPCManager.getGuests() do
		table.insert(exclude, guest)
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
		-- One value for every hit. Bots swing back now, so the old discount on hitting a guest
		-- would have been a tax on fighting the opponents that actually fight you -- and with
		-- bots scoring, two different point values would have made the scoreboard incomparable.
		local pointsPerHit = settings.pointsPerHit or 2
		if mega then
			pointsPerHit *= settings.megaPointMultiplier or 2
			ctx.result.tags.mega = true
			ctx.announce("MEGA PILLOW FIGHT!!! The living room is chaos!", "chaos")
		else
			ctx.announce("Pillow Fight! Whack everyone!", "event")
		end

		local lastSwing: { [number]: number } = {}
		local lastHit: { [number]: number } = {}
		local activationWindow: { [Player]: { count: number, since: number } } = {}

		-- The swing itself, lifted out of the tool handler so a bot can call it.
		--
		-- Everything that makes a swing fair -- cooldown, range, facing cone, sightline, one
		-- victim per swing, victim i-frames -- lives in here, so a bot is held to exactly the
		-- rules a human is. The tool handler adds only the things that are specific to holding a
		-- physical tool: the spam gate and the equipped check.
		local function swing(attacker: Participant): boolean
			local now = os.clock()
			if lastSwing[attacker.id] and now - lastSwing[attacker.id] < SWING_COOLDOWN then
				return false
			end
			local attackerRoot = Participant.rootPart(attacker)
			if not attackerRoot then
				return false
			end
			lastSwing[attacker.id] = now

			local origin = attackerRoot.Position
			local look = attackerRoot.CFrame.LookVector
			local params = buildSightlineParams()

			-- Gather every candidate, then commit to exactly one: the closest that passes.
			local bestRoot: BasePart? = nil
			local bestDistance = math.huge
			local bestVictim: Participant? = nil

			for _, victim in ctx.participants do
				if victim.id ~= attacker.id then
					local root = Participant.rootPart(victim)
					local blocked = lastHit[victim.id] and now - lastHit[victim.id] < VICTIM_IFRAME
					if root and not blocked then
						local delta = root.Position - origin
						local distance = delta.Magnitude
						local inRange = distance <= HIT_RANGE
							and distance > 0.01
							and distance < bestDistance
						if
							inRange
							and look:Dot(delta.Unit) >= FACING_DOT
							and hasSightline(origin, root.Position, params)
						then
							bestRoot, bestDistance, bestVictim = root, distance, victim
						end
					end
				end
			end

			if not bestRoot or not bestVictim then
				return false
			end

			local victim = bestVictim :: Participant
			local push = (bestRoot.Position - origin).Unit * (if mega then 60 else 30)
				+ Vector3.new(0, if mega then 30 else 15, 0)

			lastHit[victim.id] = now
			ctx.addScore(attacker, pointsPerHit)

			if victim.isBot then
				local model = victim.model
				if model then
					NPCManager.bump(model, push)
					NPCManager.say(model, NPC_REACTIONS[math.random(1, #NPC_REACTIONS)])
				end
			else
				bestRoot.AssemblyLinearVelocity = push
			end
			return true
		end

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

				swing(Participant.fromPlayer(player))
			end)
		end

		-- Bots hunt the nearest person and swing. They score what a human scores for the same
		-- hit -- difficulty is how OFTEN they act, never what an action is worth, so the
		-- scoreboard stays directly comparable.
		BotDriver.run(ctx, {
			plan = function(_, bot)
				local target, targetRoot = BotDriver.nearestParticipant(ctx, bot, 45)
				if not target or not targetRoot then
					return nil
				end
				local root = Participant.rootPart(bot)
				-- Already close enough: swing now rather than walking a pointless step first.
				if root and (root.Position - targetRoot.Position).Magnitude <= HIT_RANGE - 1 then
					return { behavior = "Seek", onArrive = swing }
				end
				local anchor = targetRoot
				return {
					behavior = "Seek",
					goal = anchor,
					arriveRadius = HIT_RANGE - 1,
					onArrive = swing,
				}
			end,
		})

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
		-- A bot can top the board, so find the winner among participants rather than resolving
		-- the id to a Player -- that lookup returns nil for a bot and the announce would have
		-- read "nil won the pillow fight".
		local best, winnerId = 0, nil
		for id, score in ctx.result.scores do
			if score > best then
				best, winnerId = score, id
			end
		end
		local winner = nil
		for _, participant in ctx.participants do
			if participant.id == winnerId then
				winner = participant
			end
		end
		if winner and best > 0 then
			table.insert(ctx.result.winners, winner)
			-- Winner-only rewards are safe to set regardless: RewardService only grants to
			-- entries it can resolve to a Player, so a bot winner simply pays nobody.
			ctx.result.winnerScrapbook = { "won_pillow_fight" }
			ctx.result.winnerStats = { pillowFightWins = 1 }
			ctx.announce(`{winner.name} won the pillow fight with {best} points!`, "result")
		else
			ctx.announce("Pillow fight over. Nobody landed a thing.", "result")
		end
	end,

	onCleanup = function(_ctx)
		NPCManager.setBehavior("Idle")
	end,
})
