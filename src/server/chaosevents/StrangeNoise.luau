--!strict
-- StrangeNoise (GDD §7) — something moves in the attic, and the hatch above the upstairs landing
-- swings open. Whoever goes up earns the "Found the Secret Attic" memory.
--
-- This event PHYSICALLY opens the house. The previous version only set an `Open` attribute on the
-- room folder, which changed nothing a player could see, walk through, or climb — and the attic
-- had no entrance to open in the first place. HouseBuilder now owns a hatch and a ladder, and
-- setAtticOpen is the one call that moves them.
--
-- The attic stays open for the rest of the sleepover rather than resealing on cleanup. A discovery
-- that reverts twenty-five seconds later is not a discovery; GameRoundManager reseals it at the
-- start of the next session.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChaosEventBase = require(Shared.framework.ChaosEventBase)
local Tags = require(Shared.Tags)

local NPCManager = require(script.Parent.Parent.systems.NPCManager)
local HouseBuilder = require(script.Parent.Parent.world.HouseBuilder)

-- Play the creak from the hatch itself when we can: that is the thing the player has to walk to.
local function noiseSource(ctx: any): BasePart?
	local hatch = CollectionService:GetTagged(Tags.AtticHatch)[1]
	if hatch and hatch:IsA("BasePart") then
		return hatch
	end
	return HouseBuilder.getAnchor(ctx.house, "StrangeNoise")
		or HouseBuilder.getAnchor(ctx.house, "GhostStory")
end

return ChaosEventBase.extend("StrangeNoise", {
	onStart = function(ctx)
		ctx.announce("...did you hear that? Something's moving in the attic. 👀", "chaos")

		local source = noiseSource(ctx)
		if source then
			local sound = Instance.new("Sound")
			sound.SoundId = "rbxassetid://9046606877" -- placeholder creak; swap in the art pass
			sound.Volume = 1
			sound.RollOffMaxDistance = 140
			sound.Looped = true
			sound.Parent = source
			ctx.trove:Add(sound)
			pcall(function()
				sound:Play()
			end)
		end

		if ctx.config.opensAttic then
			HouseBuilder.setAtticOpen(true)
			ctx.announce("The attic hatch just swung open. There's a ladder. 🪜", "event")
		end

		NPCManager.react("what WAS that")

		local scrapbook = ctx.config.scrapbook
		if scrapbook then
			ctx.result.scrapbook = { scrapbook }
		end
	end,
})
