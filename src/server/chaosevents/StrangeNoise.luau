--!strict
-- StrangeNoise (GDD §7) — a spooky sound from the attic and a nudge to go investigate. Opens
-- the (normally secret) attic. Whoever's around earns the "Found the Secret Attic" memory.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChaosEventBase = require(Shared.framework.ChaosEventBase)
local Tags = require(Shared.Tags)

local HouseBuilder = require(script.Parent.Parent.world.HouseBuilder)

return ChaosEventBase.extend("StrangeNoise", {
	onStart = function(ctx)
		ctx.announce("...did you hear that? Something's moving in the attic. 👀", "chaos")

		-- Emit a creepy sound from the attic anchor.
		local anchor = HouseBuilder.getAnchor(ctx.house, "StrangeNoise")
			or HouseBuilder.getAnchor(ctx.house, "GhostStory")
		if anchor then
			local sound = Instance.new("Sound")
			sound.SoundId = "rbxassetid://9046606877" -- placeholder creak; swap in the art pass
			sound.Volume = 1
			sound.RollOffMaxDistance = 120
			sound.Looped = true
			sound.Parent = anchor
			ctx.trove:Add(sound)
			pcall(function()
				sound:Play()
			end)
		end

		-- "Open" the attic: brighten a marker so players notice the way up.
		if ctx.config.opensAttic then
			for _, roomFolder in CollectionService:GetTagged(Tags.Room) do
				if roomFolder:GetAttribute("Secret") then
					roomFolder:SetAttribute("Open", true)
					ctx.trove:AddCleanup(function()
						roomFolder:SetAttribute("Open", false)
					end)
				end
			end
		end

		local scrapbook = ctx.config.scrapbook
		if scrapbook then
			ctx.result.scrapbook = { scrapbook }
		end
	end,
})
