--!strict
-- ScrapbookController — the persistent memory collection UI (GDD §10). A toggleable panel that
-- lists every achievement from ScrapbookConfig, showing which the player has unlocked. Long-term
-- collection without grinding — you just play and memories accrue.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.net.Remotes)
local ScrapbookConfig = require(Shared.config.ScrapbookConfig)

local UIUtil = require(script.Parent.UIUtil)

local ScrapbookController = {}

local panel: Frame
local rows: { [string]: { frame: Frame, status: TextLabel } } = {}
local unlocked: { [string]: number } = {}

local function refresh()
	for id, row in rows do
		local isUnlocked = unlocked[id] ~= nil
		local def = ScrapbookConfig.get(id)
		row.status.Text = isUnlocked and "✅" or "🔒"
		row.frame.BackgroundTransparency = isUnlocked and 0.05 or 0.5
		if def and def.rare then
			row.frame.BackgroundColor3 = isUnlocked and UIUtil.palette.accent or UIUtil.palette.panel
		end
	end
end

local function build(parent: ScreenGui)
	panel = UIUtil.make("Frame", {
		Name = "ScrapbookPanel",
		Parent = parent,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 460, 0, 420),
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
		Text = "📖 Sleepover Scrapbook",
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

	for _, def in ScrapbookConfig.achievements do
		local row = UIUtil.make("Frame", {
			Parent = scroll,
			Size = UDim2.new(1, -6, 0, 54),
			BackgroundColor3 = UIUtil.palette.panel,
			BackgroundTransparency = 0.5,
		}, { UIUtil.corner(8), UIUtil.padding(8) }) :: Frame

		local status = UIUtil.make("TextLabel", {
			Parent = row,
			Size = UDim2.new(0, 32, 1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			Text = "🔒",
		}) :: TextLabel

		UIUtil.make("TextLabel", {
			Parent = row,
			Position = UDim2.new(0, 36, 0, 0),
			Size = UDim2.new(1, -36, 0.55, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = def.rare and UIUtil.palette.accent or UIUtil.palette.text,
			Text = def.title,
		})
		UIUtil.make("TextLabel", {
			Parent = row,
			Position = UDim2.new(0, 36, 0.55, 0),
			Size = UDim2.new(1, -36, 0.45, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = UIUtil.palette.subtext,
			Text = def.description,
		})

		rows[def.id] = { frame = row, status = status }
	end
end

function ScrapbookController.toggle()
	panel.Visible = not panel.Visible
end

function ScrapbookController.start(parent: ScreenGui)
	build(parent)
	Remotes.event("DataUpdated").OnClientEvent:Connect(function(view)
		if view and view.scrapbook then
			unlocked = view.scrapbook
			refresh()
		end
	end)
end

return ScrapbookController
