--!strict
-- DevPanelController — Studio-only buttons that force-run a specific activity or chaos event.
--
-- This exists for playtesting, not for players. Testing Pillow Fight repeatedly against the
-- natural round loop means sitting through Arrive and Free Time and then hoping weighted-random
-- picks the one you wanted — minutes per attempt, for a thirty-second activity.
--
-- The IsStudio check here only hides the UI. The check that MATTERS is on the server, in
-- ActivityManager and EventManager: a client asserting "I am in Studio" is not evidence of
-- anything, so the server re-tests it before acting on either remote.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.net.Remotes)

local UIUtil = require(script.Parent.UIUtil)

local DevPanelController = {}

-- The three the current playtest pass cares about, in priority order.
local ACTIVITIES = {
	{ id = "PillowFight", label = "🛏️ Pillow Fight" },
	{ id = "ParentCheck", label = "🚨 Parent Check" },
	{ id = "MidnightSnack", label = "🍪 Snack Raid" },
	{ id = "HideAndSeek", label = "🔦 Hide & Seek" },
}

local EVENTS = {
	{ id = "PowerOutage", label = "⚡ Power Outage" },
	{ id = "StrangeNoise", label = "👀 Strange Noise" },
}

function DevPanelController.start(parent: ScreenGui)
	if not RunService:IsStudio() then
		return
	end

	local palette = UIUtil.palette
	local rows = #ACTIVITIES + #EVENTS + 1

	local panel = UIUtil.make("Frame", {
		Name = "DevPanel",
		Parent = parent,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.new(0, 170, 0, rows * 30 + 12),
		BackgroundColor3 = palette.bg,
		BackgroundTransparency = 0.2,
	}, {
		UIUtil.corner(10),
		UIUtil.padding(6),
		UIUtil.make("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame

	UIUtil.make("TextLabel", {
		Parent = panel,
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = palette.subtext,
		Text = "STUDIO ONLY",
	})

	local order = 0
	local function button(text: string, color: Color3, onClick: () -> ())
		order += 1
		local instance = UIUtil.make("TextButton", {
			Parent = panel,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = palette.panel,
			Font = Enum.Font.GothamMedium,
			TextScaled = true,
			TextColor3 = color,
			Text = text,
		}, { UIUtil.corner(6), UIUtil.padding(4) }) :: TextButton
		instance.MouseButton1Click:Connect(onClick)
	end

	for _, activity in ACTIVITIES do
		button(activity.label, palette.text, function()
			Remotes.event("DevRunActivity"):FireServer(activity.id)
		end)
	end
	for _, event in EVENTS do
		button(event.label, palette.chaos, function()
			Remotes.event("DevRunEvent"):FireServer(event.id)
		end)
	end
end

return DevPanelController
