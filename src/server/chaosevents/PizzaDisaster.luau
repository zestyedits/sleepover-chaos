--!strict
-- PizzaDisaster (GDD §7) — a pizza arrives at the door... completely wrong. A comedic beat: a
-- greybox pizza box appears with an interaction, everyone gets the "Wrong Pizza" memory.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChaosEventBase = require(Shared.framework.ChaosEventBase)
local Tags = require(Shared.Tags)

local InteractionService = require(script.Parent.Parent.systems.InteractionService)
local HouseBuilder = require(script.Parent.Parent.world.HouseBuilder)

local WRONG_TOPPINGS = {
	"anchovy & pineapple",
	"extra broccoli, no cheese",
	"gummy bears",
	"plain ketchup",
	"someone's homework",
}

return ChaosEventBase.extend("PizzaDisaster", {
	onStart = function(ctx)
		local topping = WRONG_TOPPINGS[math.random(1, #WRONG_TOPPINGS)]
		ctx.announce(`🍕 Pizza's here! ...it's {topping}. This is the WRONG order.`, "chaos")

		-- Spawn a pizza box at the living-room "door" anchor.
		local anchor = HouseBuilder.getAnchor(ctx.house, "PizzaDisaster", "door")
		local origin = anchor and anchor.Position or Vector3.new(0, 2, -14)

		local box = Instance.new("Part")
		box.Name = "WrongPizza"
		box.Size = Vector3.new(4, 1, 4)
		box.Color = Color3.new(0.8, 0.6, 0.35)
		box.Anchored = true
		box.CFrame = CFrame.new(origin + Vector3.new(0, 1, 0))
		box:SetAttribute("Role", "Pizza")
		box:SetAttribute("Label", `Wrong Pizza ({topping})`)
		box:SetAttribute("ActionText", "Inspect")
		CollectionService:AddTag(box, Tags.Interactable)
		box.Parent = ctx.house
		ctx.trove:Add(box)

		local unregister = InteractionService.register("Pizza", function(player)
			ctx.announce(`{player.Name} refuses to eat the {topping} pizza. Understandable.`, "info")
		end)
		ctx.trove:AddCleanup(unregister)

		local scrapbook = ctx.config.scrapbook
		if scrapbook then
			ctx.result.scrapbook = { scrapbook }
		end
	end,
})
