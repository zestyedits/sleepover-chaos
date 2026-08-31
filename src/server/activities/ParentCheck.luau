--!strict
-- ParentCheck (GDD §6) — "MOM IS COMING." Players have the hide window to stash contraband
-- and get in bed, then pretend to sleep. Mechanically tiny, socially loud. A perfect check
-- (all contraband hidden + everyone in bed) is a rare scrapbook memory.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ActivityBase = require(Shared.framework.ActivityBase)
local Tags = require(Shared.Tags)

local InteractionService = require(script.Parent.Parent.systems.InteractionService)
local HouseBuilder = require(script.Parent.Parent.world.HouseBuilder)

local CONTRABAND_NAMES = { "Phone", "Candy Stash", "Prank Kit", "Walkie-Talkie", "Flashlight" }

-- Spawn a few contraband props near the bedroom for players to hide.
local function spawnContraband(ctx: any): { BasePart }
	local parts = {}
	local anchor = HouseBuilder.getAnchor(ctx.house, "ParentCheck")
	local origin = anchor and anchor.Position or Vector3.new(-44, 2, 0)
	for i = 1, math.min(#CONTRABAND_NAMES, math.max(2, #ctx.players + 1)) do
		local part = Instance.new("Part")
		part.Name = `Contraband_{i}`
		part.Size = Vector3.new(2, 1, 2)
		part.Color = Color3.new(0.9, 0.3, 0.3)
		part.Anchored = true
		part.CFrame = CFrame.new(origin + Vector3.new(math.random(-12, 12), 1, math.random(-10, 10)))
		part:SetAttribute("Role", "Contraband")
		part:SetAttribute("Label", CONTRABAND_NAMES[i])
		part:SetAttribute("ActionText", "Hide it!")
		CollectionService:AddTag(part, Tags.Interactable)
		part.Parent = ctx.house
		ctx.trove:Add(part)
		table.insert(parts, part)
	end
	return parts
end

local function playersInBed(ctx: any): number
	local bedZones = CollectionService:GetTagged(Tags.BedZone)
	local count = 0
	for _, player in ctx.players do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			for _, zone in bedZones do
				if zone:IsA("BasePart") and (root.Position - zone.Position).Magnitude <= 6 then
					count += 1
					break
				end
			end
		end
	end
	return count
end

return ActivityBase.extend("ParentCheck", {
	onStart = function(ctx)
		ctx.announce("MOM IS COMING! Hide everything and GET IN BED!", "chaos")

		local contraband = spawnContraband(ctx)
		ctx.result.tags.totalContraband = #contraband
		ctx.result.tags.hidden = 0

		-- Interacting with a contraband part "hides" it and scores the hider.
		local unregister = InteractionService.register("Contraband", function(player, part)
			if not part:GetAttribute("Hidden") then
				part:SetAttribute("Hidden", true)
				part.Transparency = 1
				local prompt = InteractionService.getPrompt(part)
				if prompt then
					prompt.Enabled = false
				end
				ctx.addScore(player, ctx.config.pointsPerHiddenItem or 2)
				ctx.result.tags.hidden += 1
			end
		end)
		ctx.trove:AddCleanup(unregister)
	end,

	checkWin = function(ctx)
		-- End early once everything is hidden AND everyone's in bed.
		local allHidden = ctx.result.tags.hidden >= ctx.result.tags.totalContraband
		local everyoneInBed = #ctx.players > 0 and playersInBed(ctx) >= #ctx.players
		return allHidden and everyoneInBed
	end,

	onFinish = function(ctx)
		-- Reward being in bed at the whistle.
		local inBed = playersInBed(ctx)
		for _, player in ctx.players do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				for _, zone in CollectionService:GetTagged(Tags.BedZone) do
					if zone:IsA("BasePart") and (root.Position - zone.Position).Magnitude <= 6 then
						ctx.addScore(player, ctx.config.pointsForInBed or 3)
						table.insert(ctx.result.winners, player)
						break
					end
				end
			end
		end

		local perfect = ctx.result.tags.hidden >= ctx.result.tags.totalContraband
			and #ctx.players > 0
			and inBed >= #ctx.players
		if perfect then
			ctx.result.scrapbook = { "perfect_parent_check" }
			ctx.announce("Perfect Parent Check! Nobody suspects a thing. 😴", "result")
		else
			ctx.announce("...Mom's suspicious. Better luck next time.", "result")
		end
	end,
})
