--!strict
-- MidnightSnack (GDD §6) — sneak into the kitchen and gather the requested snacks without waking
-- the house. Max the shared noise meter and the lights snap on and the raid fails.
--
-- Two things make this actually playable:
--
-- 1. Every prop this activity touches is restored on cleanup. The snack sources are permanent
--    house fixtures shared by every run, so a `Taken` attribute left set would make the SECOND
--    raid unwinnable forever. Restores are registered on the trove at the moment of mutation, so
--    even a mid-run error reverts them.
--
-- 2. Noise is driven mostly by MOVEMENT, not by grabbing. Four grabs alone can never reach the
--    threshold, and a fail state you cannot trigger is not tension. Sprinting is loud, standing
--    still lets the meter fall — so the game is "how slowly can you bear to move".

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ActivityBase = require(Shared.framework.ActivityBase)
local Participant = require(Shared.Participant)
local Tags = require(Shared.Tags)

local BotDriver = require(script.Parent.Parent.systems.BotDriver)
local InteractionService = require(script.Parent.Parent.systems.InteractionService)
local NPCManager = require(script.Parent.Parent.systems.NPCManager)

local STATE_BROADCAST_INTERVAL = 0.2

local function snackSources(): { BasePart }
	local sources = {}
	for _, source in CollectionService:GetTagged(Tags.SnackSource) do
		if source:IsA("BasePart") then
			table.insert(sources, source)
		end
	end
	return sources
end

-- Put a snack source back exactly as the house built it.
local function restoreSource(source: BasePart, transparency: number)
	if not source.Parent then
		return
	end
	source:SetAttribute("Taken", nil)
	source.Transparency = transparency
	local prompt = InteractionService.getPrompt(source)
	if prompt then
		prompt.Enabled = true
	end
end

return ActivityBase.extend("MidnightSnack", {
	onStart = function(ctx)
		local settings = ctx.config
		ctx.announce("Midnight Snack Raid! Grab the snacks... quietly.", "event")

		local sources = snackSources()
		local requestNames = {}
		for _, source in sources do
			local snack = source:GetAttribute("Snack")
			if snack then
				table.insert(requestNames, snack)
			end
			-- Any source may be stale from a run that errored before its restore fired.
			-- Clear it now so the raid always starts from a known-good kitchen.
			if source:GetAttribute("Taken") then
				restoreSource(source, source:GetAttribute("BaseTransparency") or 0)
			end
		end

		ctx.result.tags.requested = #requestNames
		ctx.result.tags.collected = 0
		ctx.result.tags.noise = 0
		if #requestNames > 0 then
			ctx.announce(`Shopping list: {table.concat(requestNames, ", ")}`, "info")
		end

		local collected: { [string]: boolean } = {}

		ctx.trove:AddCleanup(InteractionService.register("Snack", function(actor, part)
			local snack = part:GetAttribute("Snack")
			if not snack or collected[snack] or part:GetAttribute("Taken") then
				return
			end

			-- Snapshot BEFORE mutating and hand the restore to the trove immediately, so the
			-- kitchen resets even if this run dies partway through.
			local originalTransparency = part.Transparency
			ctx.trove:AddCleanup(function()
				restoreSource(part, originalTransparency)
			end)

			collected[snack] = true
			part:SetAttribute("Taken", true)
			part.Transparency = 0.7
			local prompt = InteractionService.getPrompt(part)
			if prompt then
				prompt.Enabled = false
			end

			ctx.addScore(actor, settings.pointsPerSnack or 2)
			ctx.result.tags.collected += 1
			ctx.result.tags.noise += settings.noisePerGrab or 22
			ctx.announce(`{actor.name} swiped the {snack}!`, "info")
		end))

		NPCManager.setBehavior("Gather")

		-- Bots raid too. They walk to the nearest untaken snack and go through the very same
		-- handler above -- InteractionService.simulate re-checks reach and the prompt's enabled
		-- state, so a bot cannot take a shortcut a human could not.
		--
		-- They also walk SLOWER than their default 12 for the duration. Against a quietSpeed of
		-- 7 a normal-speed guest generates noise constantly and would bust the raid single
		-- handedly within seconds.
		for _, bot in ctx.bots() do
			local humanoid = bot.model and bot.model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				local previous = humanoid.WalkSpeed
				humanoid.WalkSpeed = 6
				ctx.trove:AddCleanup(function()
					if humanoid.Parent then
						humanoid.WalkSpeed = previous
					end
				end)
			end
		end

		BotDriver.run(ctx, {
			plan = function(_, bot)
				local target = BotDriver.nearestPart(bot, snackSources(), function(part)
					return not part:GetAttribute("Taken")
				end)
				if not target then
					return nil
				end
				return {
					behavior = "Seek",
					goal = target,
					arriveRadius = 7,
					onArrive = function(actingBot)
						InteractionService.simulate("Snack", actingBot, target)
					end,
				}
			end,
		})
	end,

	onUpdate = function(dt, ctx)
		local settings = ctx.config
		-- Defaulted: Lifecycle pcalls onStart, so a failure there must not turn into a warning
		-- storm from the heartbeat loop.
		local noise = ctx.result.tags.noise or 0

		-- Movement is the dominant noise source. Horizontal speed only: falling off a counter
		-- should not read as stomping.
		local quietSpeed = settings.quietSpeed or 7
		local perSpeedUnit = settings.noisePerSpeedUnit or 0.35
		-- Everyone in the house makes noise, bots included -- otherwise a bot could sprint the
		-- kitchen clean while the meter sat at zero, and the humans would carry all the risk for
		-- a shared objective. Bots count half, because they are not the ones choosing to hurry.
		for _, participant in ctx.participants do
			local root = Participant.rootPart(participant)
			if root then
				local velocity = root.AssemblyLinearVelocity
				local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
				if speed > quietSpeed then
					local weight = if participant.isBot then 0.5 else 1
					noise += (speed - quietSpeed) * perSpeedUnit * weight * dt
				end
			end
		end

		-- ...and it decays whenever the house is quiet, so a bad moment is recoverable.
		noise = math.max(0, noise - (settings.noiseDecayPerSecond or 5) * dt)
		ctx.result.tags.noise = noise

		local elapsed = (ctx.result.tags._stateClock or 0) + dt
		if elapsed < STATE_BROADCAST_INTERVAL then
			ctx.result.tags._stateClock = elapsed
			return
		end
		ctx.result.tags._stateClock = 0
		ctx.broadcastState({
			label = "Noise",
			meter = noise,
			meterMax = settings.noiseFailThreshold or 100,
			found = ctx.result.tags.collected,
			total = ctx.result.tags.requested,
		})
	end,

	checkWin = function(ctx)
		if (ctx.result.tags.noise or 0) >= (ctx.config.noiseFailThreshold or 100) then
			ctx.announce("The lights turned ON! Everyone SCATTER!", "chaos")
			NPCManager.setBehavior("Scatter")
			ctx.abort()
			return true
		end
		return (ctx.result.tags.requested or 0) > 0
			and (ctx.result.tags.collected or 0) >= ctx.result.tags.requested
	end,

	onFinish = function(ctx)
		if ctx.result.completed and ctx.result.tags.collected >= ctx.result.tags.requested then
			ctx.result.scrapbook = { "midnight_feast" }
			ctx.announce("Midnight feast secured! 🍪", "result")
			-- A shared objective: the raid succeeded or it did not, so everyone who was in the
			-- kitchen shares the win. Listing bots here is harmless — RewardService only pays
			-- entries it can resolve to a Player, and the memory is the humans' either way.
			for _, participant in ctx.participants do
				table.insert(ctx.result.winners, participant)
			end
		end
	end,

	onCleanup = function(_ctx)
		-- Backstop. The per-grab trove restores handle the normal path; this catches a source
		-- that was somehow marked outside the handler, so the kitchen is never left broken.
		for _, source in snackSources() do
			if source:GetAttribute("Taken") then
				restoreSource(source, source:GetAttribute("BaseTransparency") or 0)
			end
		end
		NPCManager.setBehavior("Idle")
	end,
})
