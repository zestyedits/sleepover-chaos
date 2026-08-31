--!strict
-- HideAndSeek (GDD §6) — one seeker; everyone else finds a hiding spot. Reaching a tagged
-- hiding spot makes you safe; the seeker tags un-hidden players by swinging their "found you!"
-- prompt tool nearby. Survivors score at the whistle. With fewer than two real players there is
-- no seeker — everyone just races to hide (keeps the solo experience working, GDD §13).

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ActivityBase = require(Shared.framework.ActivityBase)
local RandomUtil = require(Shared.util.RandomUtil)
local Tags = require(Shared.Tags)

local InteractionService = require(script.Parent.Parent.systems.InteractionService)

local TAG_RANGE = 8

return ActivityBase.extend("HideAndSeek", {
	onStart = function(ctx)
		local settings = ctx.config
		local hidden: { [Player]: boolean } = {}
		local caught: { [Player]: boolean } = {}
		ctx.result.tags.seeker = nil

		-- Reaching a hiding spot makes a player safe.
		local unregister = InteractionService.register("Hide", function(player, part)
			if not caught[player] then
				hidden[player] = true
				ctx.announce(`{player.Name} found a hiding spot!`, "info")
			end
		end)
		ctx.trove:AddCleanup(unregister)
		ctx.result.tags._hidden = hidden
		ctx.result.tags._caught = caught

		-- Choose a seeker only if there are at least two real players.
		if #ctx.players >= 2 then
			local seeker = RandomUtil.pick(ctx.players)
			ctx.result.tags.seeker = seeker
			ctx.announce(`{seeker.Name} is the SEEKER! Everyone hide!`, "chaos")

			-- Give the seeker a tagging tool after the head start.
			task.delay(settings.seekerHeadStart or 8, function()
				if not seeker.Parent then
					return
				end
				local tool = Instance.new("Tool")
				tool.Name = "Tag!"
				tool.RequiresHandle = true
				local handle = Instance.new("Part")
				handle.Name = "Handle"
				handle.Size = Vector3.new(1, 1, 1)
				handle.Color = Color3.new(1, 0.4, 0.4)
				handle.Parent = tool
				tool.Parent = seeker.Backpack
				ctx.trove:Add(tool)
				ctx.announce("The seeker is coming! GO GO GO!", "event")

				ctx.trove:Connect(tool.Activated, function()
					local seekerRoot = seeker.Character
						and seeker.Character:FindFirstChild("HumanoidRootPart")
					if not seekerRoot then
						return
					end
					for _, other in ctx.players do
						if other ~= seeker and not caught[other] and not hidden[other] then
							local root = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
							if root and (root.Position - (seekerRoot :: BasePart).Position).Magnitude <= TAG_RANGE then
								caught[other] = true
								ctx.addScore(seeker, settings.pointsPerCatch or 2)
								ctx.announce(`{seeker.Name} caught {other.Name}!`, "event")
							end
						end
					end
				end)
			end)
		else
			ctx.announce("Find the best hiding spot before the timer runs out!", "event")
		end
	end,

	checkWin = function(ctx)
		-- End early if every non-seeker is either hidden or caught.
		local seeker = ctx.result.tags.seeker
		local hidden = ctx.result.tags._hidden
		local caught = ctx.result.tags._caught
		if not hidden then
			return false
		end
		for _, player in ctx.players do
			if player ~= seeker and not hidden[player] and not caught[player] then
				return false
			end
		end
		return #ctx.players > 0
	end,

	onFinish = function(ctx)
		local seeker = ctx.result.tags.seeker
		local caught = ctx.result.tags._caught or {}
		for _, player in ctx.players do
			if player ~= seeker and not caught[player] then
				ctx.addScore(player, ctx.config.pointsForSurviving or 3)
				table.insert(ctx.result.winners, player)
			end
		end
		ctx.announce("Hide & Seek over! Survivors take the win.", "result")
	end,
})
