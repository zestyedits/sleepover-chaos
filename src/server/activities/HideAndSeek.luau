--!strict
-- HideAndSeek (GDD §6) — one seeker hunts; everyone else claims a hiding spot and defends it.
--
-- The rule that makes this a game rather than a race: reaching a spot is not the END state, it is
-- the POSITION YOU DEFEND. Hiders claim a tagged spot and must stay near it; the seeker gets a
-- "Search!" tool after a head start and reveals spots one at a time. The round ends when every
-- hider has been found, or at the whistle — survivors score.
--
-- Solo (fewer than two real players) there is nobody to hide from, so the mode flips to a
-- scavenger hunt: find all five hiding spots before the timer. Keeps the solo experience a real
-- objective instead of an instant win (GDD §13).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ActivityBase = require(Shared.framework.ActivityBase)
local RandomUtil = require(Shared.util.RandomUtil)
local Tags = require(Shared.Tags)

local InteractionService = require(script.Parent.Parent.systems.InteractionService)
local NPCManager = require(script.Parent.Parent.systems.NPCManager)

local STATE_BROADCAST_INTERVAL = 0.2

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root :: BasePart or nil
end

local function hidingSpots(): { BasePart }
	local spots = {}
	for _, spot in CollectionService:GetTagged(Tags.HidingSpot) do
		if spot:IsA("BasePart") then
			table.insert(spots, spot)
		end
	end
	return spots
end

local function spotLabel(spot: BasePart): string
	return spot:GetAttribute("Label") or spot.Name
end

return ActivityBase.extend("HideAndSeek", {
	onStart = function(ctx)
		local settings = ctx.config
		local spots = hidingSpots()

		-- Guard flag for the delayed seeker-arming task. The trove cancels the thread, but the
		-- flag also covers the window between the run loop stopping and cleanup running.
		local active = true
		ctx.trove:AddCleanup(function()
			active = false
		end)

		-- Solo: no seeker exists, so hunt the spots instead of hiding from someone.
		local soloHunt = #ctx.players < 2
		ctx.result.tags.soloHunt = soloHunt
		ctx.result.tags.totalSpots = #spots

		if soloHunt then
			local found: { [BasePart]: boolean } = {}
			ctx.result.tags.foundCount = 0

			ctx.trove:AddCleanup(InteractionService.register("Hide", function(player, part)
				if found[part] then
					return
				end
				found[part] = true
				ctx.result.tags.foundCount += 1
				ctx.addScore(player, settings.pointsForFindingSpot or 1)
				ctx.announce(
					`Found "{spotLabel(part)}"! ({ctx.result.tags.foundCount}/{#spots})`,
					"info"
				)
			end))

			ctx.announce(`Find all {#spots} hiding spots before the timer runs out!`, "event")
			NPCManager.setBehavior("Hide")
			return
		end

		-- Multiplayer: one seeker, everyone else hides.
		local seeker = RandomUtil.pick(ctx.players)
		local hiddenAt: { [Player]: BasePart } = {}
		local occupant: { [BasePart]: Player } = {}
		local caught: { [Player]: boolean } = {}

		ctx.result.tags.seeker = seeker
		ctx.result.tags._hiddenAt = hiddenAt
		ctx.result.tags._occupant = occupant
		ctx.result.tags._caught = caught

		local function release(player: Player)
			local spot = hiddenAt[player]
			if spot then
				occupant[spot] = nil
				hiddenAt[player] = nil
			end
		end

		local function catch(victim: Player, how: string)
			if caught[victim] then
				return
			end
			caught[victim] = true
			release(victim)
			ctx.addScore(seeker, settings.pointsPerCatch or 2)
			ctx.announce(`{seeker.Name} found {victim.Name} {how}!`, "event")
		end

		-- Claiming a spot. One hider per spot, so the party spreads out across the house.
		ctx.trove:AddCleanup(InteractionService.register("Hide", function(player, part)
			if player == seeker or caught[player] then
				return
			end
			local holder = occupant[part]
			if holder and holder ~= player then
				return -- already taken; go find your own
			end
			if hiddenAt[player] == part then
				return
			end
			release(player)
			hiddenAt[player] = part
			occupant[part] = player
			-- Deliberately vague: the seeker learns that someone is hidden, never where.
			ctx.announce(`{player.Name} slipped out of sight...`, "info")
		end))

		ctx.announce(`{seeker.Name} is the SEEKER! Everyone hide!`, "chaos")
		NPCManager.setBehavior("Hide")

		-- Arm the seeker after the head start. Owned by the trove so an expired or aborted run
		-- can never spawn a "Search!" tool into the next activity.
		ctx.trove:Add(task.delay(settings.seekerHeadStart or 12, function()
			if not active or not seeker.Parent then
				return
			end

			local tool = Instance.new("Tool")
			tool.Name = "Search!"
			tool.RequiresHandle = true
			tool.CanBeDropped = false
			local handle = Instance.new("Part")
			handle.Name = "Handle"
			handle.Size = Vector3.new(1, 1, 1)
			handle.Color = Color3.new(1, 0.4, 0.4)
			handle.Parent = tool
			tool.Parent = seeker.Backpack
			ctx.trove:Add(tool)

			ctx.announce("The seeker is coming! Hold your breath...", "event")

			ctx.trove:Connect(tool.Activated, function()
				if not active then
					return
				end
				local seekerRoot = rootOf(seeker)
				if not seekerRoot then
					return
				end

				-- Searching a hiding spot beats tagging: check the nearest spot in range first.
				local nearestSpot, nearestSpotDist = nil, math.huge
				for _, spot in spots do
					local distance = (spot.Position - seekerRoot.Position).Magnitude
					if distance < nearestSpotDist then
						nearestSpot, nearestSpotDist = spot, distance
					end
				end

				if nearestSpot and nearestSpotDist <= (settings.searchRange or 9) then
					local hider = occupant[nearestSpot]
					if hider and not caught[hider] then
						catch(hider, `hiding in "{spotLabel(nearestSpot)}"`)
					else
						ctx.announce(`Nothing in "{spotLabel(nearestSpot)}"...`, "info")
					end
					return
				end

				-- Otherwise tag the closest hider caught out in the open.
				local target, targetDist = nil, math.huge
				for _, other in ctx.players do
					if other ~= seeker and not caught[other] and not hiddenAt[other] then
						local root = rootOf(other)
						if root then
							local distance = (root.Position - seekerRoot.Position).Magnitude
							if distance < targetDist then
								target, targetDist = other, distance
							end
						end
					end
				end
				if target and targetDist <= (settings.tagRange or 7) then
					catch(target, "out in the open")
				end
			end)
		end))
	end,

	onUpdate = function(dt, ctx)
		local hiddenAt = ctx.result.tags._hiddenAt
		local occupant = ctx.result.tags._occupant
		local caught = ctx.result.tags._caught

		-- Hiding is a position you hold, not a checkpoint you touch: wander off and you are
		-- exposed again. This is what gives the seeker phase stakes.
		if hiddenAt then
			local hideRadius = ctx.config.hideRadius or 10
			for player, spot in hiddenAt do
				local root = rootOf(player)
				if not root or (root.Position - spot.Position).Magnitude > hideRadius then
					hiddenAt[player] = nil
					-- Free the spot as well. Leaving it claimed would both lock the next hider
					-- out of it and let the seeker "find" someone who already walked away.
					if occupant then
						occupant[spot] = nil
					end
					ctx.announce(`{player.Name} broke cover!`, "info")
				end
			end
		end

		-- Throttled HUD push — an invisible found-counter is not tension, it is a surprise.
		local elapsed = (ctx.result.tags._stateClock or 0) + dt
		if elapsed < STATE_BROADCAST_INTERVAL then
			ctx.result.tags._stateClock = elapsed
			return
		end
		ctx.result.tags._stateClock = 0

		if ctx.result.tags.soloHunt then
			ctx.broadcastState({
				label = "Spots found",
				found = ctx.result.tags.foundCount or 0,
				total = ctx.result.tags.totalSpots or 0,
			})
		elseif caught then
			local foundCount, hiderCount = 0, 0
			for _, player in ctx.players do
				if player ~= ctx.result.tags.seeker then
					hiderCount += 1
					if caught[player] then
						foundCount += 1
					end
				end
			end
			ctx.broadcastState({ label = "Hiders found", found = foundCount, total = hiderCount })
		end
	end,

	checkWin = function(ctx)
		if ctx.result.tags.soloHunt then
			local total = ctx.result.tags.totalSpots or 0
			return total > 0 and (ctx.result.tags.foundCount or 0) >= total
		end

		-- Multiplayer ends early ONLY when the seeker has found everyone. Anything short of that
		-- runs to the whistle, which is what gives hiders something to survive.
		local caught = ctx.result.tags._caught
		local seeker = ctx.result.tags.seeker
		if not caught or not seeker or #ctx.players < 2 then
			return false
		end
		local hiders = 0
		for _, player in ctx.players do
			if player ~= seeker then
				hiders += 1
				if not caught[player] then
					return false
				end
			end
		end
		return hiders > 0
	end,

	onFinish = function(ctx)
		if ctx.result.tags.soloHunt then
			local total = ctx.result.tags.totalSpots or 0
			local found = ctx.result.tags.foundCount or 0
			if total > 0 and found >= total then
				for _, player in ctx.players do
					table.insert(ctx.result.winners, player)
				end
				ctx.announce("Every hiding spot found. You know this house. 🔦", "result")
			else
				ctx.announce(`Time! You found {found} of {total} hiding spots.`, "result")
			end
			return
		end

		local seeker = ctx.result.tags.seeker
		local caught = ctx.result.tags._caught or {}
		local survivors = 0
		for _, player in ctx.players do
			if player ~= seeker and not caught[player] then
				survivors += 1
				ctx.addScore(player, ctx.config.pointsForSurviving or 3)
				table.insert(ctx.result.winners, player)
			end
		end

		if survivors == 0 and seeker then
			table.insert(ctx.result.winners, seeker)
			ctx.announce(`{seeker.Name} found EVERYONE. Nobody escaped.`, "result")
		else
			ctx.announce(`Hide & Seek over! {survivors} survived the hunt.`, "result")
		end
	end,

	onCleanup = function(_ctx)
		NPCManager.setBehavior("Idle")
	end,
})
