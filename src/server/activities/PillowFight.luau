--!strict
-- PillowFight (GDD §6) — free-for-all, hit players with pillows for points, silly knockback.
-- Rare MEGA PILLOW FIGHT variant doubles points and cranks the chaos. About one screen of
-- logic because ActivityBase + Lifecycle handle the run, scoring context, and cleanup.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ActivityBase = require(Shared.framework.ActivityBase)
local RandomUtil = require(Shared.util.RandomUtil)

local HIT_RANGE = 9
local HIT_COOLDOWN = 0.55

local function givePillow(player: Player, trove: any): Tool?
	local character = player.Character
	if not character then
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

	tool.Parent = player.Backpack
	trove:Add(tool)
	return tool
end

return ActivityBase.extend("PillowFight", {
	onStart = function(ctx)
		local settings = ctx.config
		local mega = RandomUtil.chance(settings.megaChance or 0)
		local pointsPerHit = settings.pointsPerHit or 1
		if mega then
			pointsPerHit *= settings.megaPointMultiplier or 2
			ctx.result.tags.mega = true
			ctx.announce("MEGA PILLOW FIGHT!!! The living room is chaos!", "chaos")
		else
			ctx.announce("Pillow Fight! Whack everyone!", "event")
		end

		local cooldowns: { [Player]: number } = {}

		for _, player in ctx.players do
			local tool = givePillow(player, ctx.trove)
			if tool then
				ctx.trove:Connect(tool.Activated, function()
					local now = os.clock()
					if cooldowns[player] and now - cooldowns[player] < HIT_COOLDOWN then
						return
					end
					cooldowns[player] = now

					local attackerChar = player.Character
					local attackerRoot = attackerChar
						and attackerChar:FindFirstChild("HumanoidRootPart")
					if not attackerRoot then
						return
					end

					-- Hit anyone in range (FFA). Award a point + knockback per victim.
					for _, other in Players:GetPlayers() do
						if other == player then
							continue
						end
						local otherChar = other.Character
						local otherRoot = otherChar and otherChar:FindFirstChild("HumanoidRootPart")
						if not otherRoot then
							continue
						end
						local delta = (otherRoot :: BasePart).Position
							- (attackerRoot :: BasePart).Position
						if delta.Magnitude <= HIT_RANGE then
							ctx.addScore(player, pointsPerHit)
							local push = delta.Unit * (mega and 60 or 30)
								+ Vector3.new(0, mega and 30 or 15, 0);
							(otherRoot :: BasePart).AssemblyLinearVelocity = push
						end
					end
				end)
			end
		end
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
			ctx.announce(`{winner.Name} won the pillow fight with {best} hits!`, "result")
		end
	end,
})
