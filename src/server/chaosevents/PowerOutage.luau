--!strict
-- PowerOutage (GDD §7) — the classic. Kill every house light, drop the ambient lighting, send
-- the NPC guests scattering, then restore it all on cleanup. A "small system change, not an
-- entire new game" — pure onStart/onCleanup. Awards the rare "Survived Blackout" memory.

local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChaosEventBase = require(Shared.framework.ChaosEventBase)
local Tags = require(Shared.Tags)

local NPCManager = require(script.Parent.Parent.systems.NPCManager)

return ChaosEventBase.extend("PowerOutage", {
	onStart = function(ctx)
		ctx.announce("⚡ The power just went OUT. Who touched the breaker?!", "chaos")

		-- Snapshot + darken global lighting; restore via trove.
		local prevBrightness = Lighting.Brightness
		local prevClock = Lighting.ClockTime
		local prevAmbient = Lighting.Ambient
		Lighting.Brightness = 0
		Lighting.ClockTime = 0
		Lighting.Ambient = Color3.new(0.03, 0.03, 0.06)
		ctx.trove:AddCleanup(function()
			Lighting.Brightness = prevBrightness
			Lighting.ClockTime = prevClock
			Lighting.Ambient = prevAmbient
		end)

		-- Turn off every tagged house light; remember which to re-enable.
		for _, host in CollectionService:GetTagged(Tags.HouseLight) do
			if host:IsA("BasePart") then
				local light = host:FindFirstChildOfClass("PointLight")
				local wasEnabled = light and light.Enabled
				local prevMaterial = host.Material
				if light then
					light.Enabled = false
				end
				host.Material = Enum.Material.SmoothPlastic
				ctx.trove:AddCleanup(function()
					if light then
						light.Enabled = wasEnabled == nil and true or wasEnabled
					end
					host.Material = prevMaterial
				end)
			end
		end

		-- NPCs panic (GDD §13 react to events).
		NPCManager.reactScatter()

		-- Everyone present earns the blackout memory.
		local scrapbook = ctx.config.scrapbook
		if scrapbook then
			ctx.result.scrapbook = { scrapbook }
		end
	end,
})
