--!strict
-- MidnightSnack (GDD §6) — sneak into the kitchen and gather requested snacks without waking
-- the house. Each grab spikes a shared noise meter; the meter decays over time. Max it out and
-- the lights snap on and the raid fails. Collect every requested snack to win the midnight feast.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ActivityBase = require(Shared.framework.ActivityBase)
local Tags = require(Shared.Tags)

local InteractionService = require(script.Parent.Parent.systems.InteractionService)

return ActivityBase.extend("MidnightSnack", {
	onStart = function(ctx)
		ctx.announce("Midnight Snack Raid! Grab the snacks... quietly.", "event")

		-- Build the request list from the tagged snack sources present in the house.
		local sources = CollectionService:GetTagged(Tags.SnackSource)
		local requested: { [string]: boolean } = {}
		local requestNames = {}
		for _, source in sources do
			if source:IsA("BasePart") then
				local snack = source:GetAttribute("Snack")
				if snack then
					requested[snack] = true
					table.insert(requestNames, snack)
				end
			end
		end
		ctx.result.tags.requested = #requestNames
		ctx.result.tags.collected = 0
		ctx.result.tags.noise = 0
		if #requestNames > 0 then
			ctx.announce(`Shopping list: {table.concat(requestNames, ", ")}`, "info")
		end

		local settings = ctx.config
		local collected: { [string]: boolean } = {}

		local unregister = InteractionService.register("Snack", function(player, part)
			local snack = part:GetAttribute("Snack")
			if not snack or collected[snack] or part:GetAttribute("Taken") then
				return
			end
			collected[snack] = true
			part:SetAttribute("Taken", true)
			part.Transparency = 0.7
			local prompt = InteractionService.getPrompt(part)
			if prompt then
				prompt.Enabled = false
			end

			ctx.addScore(player, settings.pointsPerSnack or 2)
			ctx.result.tags.collected += 1
			ctx.result.tags.noise += settings.noisePerGrab or 18
		end)
		ctx.trove:AddCleanup(unregister)
	end,

	onUpdate = function(dt, ctx)
		-- Noise decays while nobody is grabbing (GDD §6 sneaking tension).
		local decay = (ctx.config.noiseDecayPerSecond or 6) * dt
		ctx.result.tags.noise = math.max(0, ctx.result.tags.noise - decay)
	end,

	checkWin = function(ctx)
		-- Bust if too loud.
		if ctx.result.tags.noise >= (ctx.config.noiseFailThreshold or 100) then
			ctx.announce("The lights turned ON! Everyone SCATTER!", "chaos")
			ctx.abort()
			return true
		end
		-- Win when all requested snacks are collected.
		return ctx.result.tags.requested > 0
			and ctx.result.tags.collected >= ctx.result.tags.requested
	end,

	onFinish = function(ctx)
		if ctx.result.completed and ctx.result.tags.collected >= ctx.result.tags.requested then
			ctx.result.scrapbook = { "midnight_feast" }
			ctx.announce("Midnight feast secured! 🍪", "result")
			for _, player in ctx.players do
				table.insert(ctx.result.winners, player)
			end
		end
	end,
})
