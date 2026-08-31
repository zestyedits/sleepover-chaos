--!strict
-- CosmeticMenuController — browse and equip cosmetics (GDD §11). A toggleable panel listing the
-- catalog with owned / star-cost state. Equipping sends RequestEquip; the SERVER validates and
-- (for star items) buys-then-equips. Cosmetic only — nothing here touches gameplay power (§12).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.net.Remotes)
local CosmeticConfig = require(Shared.config.CosmeticConfig)

local UIUtil = require(script.Parent.UIUtil)

local CosmeticMenuController = {}

local panel: Frame
local rows: { [string]: TextLabel } = {}
local owned: { [string]: boolean } = {}
local equipped: { [string]: string? } = {}
local stars = 0

local function refresh()
	for id, statusLabel in rows do
		local def = CosmeticConfig.get(id)
		if not def then
			continue
		end
		if equipped[def.slot] == id then
			statusLabel.Text = "Equipped"
			statusLabel.TextColor3 = UIUtil.palette.good
		elseif owned[id] then
			statusLabel.Text = "Owned · Equip"
			statusLabel.TextColor3 = UIUtil.palette.accent2
		elseif def.starCost then
			statusLabel.Text = `⭐ {def.starCost}`
			statusLabel.TextColor3 = (stars >= def.starCost) and UIUtil.palette.warn
				or UIUtil.palette.subtext
		else
			statusLabel.Text = "Robux (soon)"
			statusLabel.TextColor3 = UIUtil.palette.subtext
		end
	end
end

local function build(parent: ScreenGui)
	panel = UIUtil.make("Frame", {
		Name = "CosmeticPanel",
		Parent = parent,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 480, 0, 440),
		BackgroundColor3 = UIUtil.palette.bg,
		Visible = false,
	}, { UIUtil.corner(14), UIUtil.padding(12) }) :: Frame

	UIUtil.make("TextLabel", {
		Parent = panel,
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = UIUtil.palette.text,
		Text = "👗 Closet",
	})

	local scroll = UIUtil.make("ScrollingFrame", {
		Parent = panel,
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 1, -44),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, {
		UIUtil.make("UIListLayout", { Padding = UDim.new(0, 6) }),
	}) :: ScrollingFrame

	for _, def in CosmeticConfig.catalog do
		local row = UIUtil.make("Frame", {
			Parent = scroll,
			Size = UDim2.new(1, -6, 0, 44),
			BackgroundColor3 = UIUtil.palette.panel,
			BackgroundTransparency = 0.3,
		}, { UIUtil.corner(8), UIUtil.padding(6) }) :: Frame

		UIUtil.make("TextLabel", {
			Parent = row,
			Size = UDim2.new(0.5, 0, 1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = UIUtil.palette.text,
			Text = `{def.displayName}  ·  {def.slot}`,
		})

		local button = UIUtil.make("TextButton", {
			Parent = row,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.new(0, 150, 0.85, 0),
			BackgroundColor3 = UIUtil.palette.bg,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextColor3 = UIUtil.palette.subtext,
			Text = "…",
			AutoButtonColor = true,
		}, { UIUtil.corner(6), UIUtil.padding(4) }) :: TextButton

		button.MouseButton1Click:Connect(function()
			-- Server decides whether this is a buy, an equip, or a no-op.
			Remotes.event("RequestEquip"):FireServer(def.slot, def.id)
		end)

		rows[def.id] = button
	end
end

function CosmeticMenuController.toggle()
	panel.Visible = not panel.Visible
end

function CosmeticMenuController.start(parent: ScreenGui)
	build(parent)
	Remotes.event("DataUpdated").OnClientEvent:Connect(function(view)
		if not view then
			return
		end
		stars = view.stars or 0
		owned = view.cosmetics and view.cosmetics.owned or {}
		equipped = view.cosmetics and view.cosmetics.equipped or {}
		refresh()
	end)
end

return CosmeticMenuController
