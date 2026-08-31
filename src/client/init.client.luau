--!strict
-- Client bootstrap — builds the ScreenGui, starts the HUD/notification/menu controllers, and
-- adds a small toolbar to open the Scrapbook and Closet. Presentation only (GDD §14).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.net.Remotes)

local controllers = script:WaitForChild("controllers")
local UIUtil = require(controllers.UIUtil)
local HudController = require(controllers.HudController)
local NotificationsController = require(controllers.NotificationsController)
local ScrapbookController = require(controllers.ScrapbookController)
local CosmeticMenuController = require(controllers.CosmeticMenuController)
local GhostStoryController = require(controllers.GhostStoryController)

Remotes.init()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screen = Instance.new("ScreenGui")
screen.Name = "SleepoverChaosUI"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

-- Start controllers.
HudController.start(screen)
NotificationsController.start(screen)
ScrapbookController.start(screen)
CosmeticMenuController.start(screen)
GhostStoryController.start(screen)

-- Bottom-left toolbar with panel toggles.
local toolbar = UIUtil.make("Frame", {
	Name = "Toolbar",
	Parent = screen,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 12, 1, -12),
	Size = UDim2.new(0, 260, 0, 44),
	BackgroundTransparency = 1,
}, {
	UIUtil.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}),
}) :: Frame

local function toolbarButton(text: string, onClick: () -> ())
	local button = UIUtil.make("TextButton", {
		Parent = toolbar,
		Size = UDim2.new(0, 120, 1, 0),
		BackgroundColor3 = UIUtil.palette.panel,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = UIUtil.palette.text,
		Text = text,
	}, { UIUtil.corner(10), UIUtil.padding(8) }) :: TextButton
	button.MouseButton1Click:Connect(onClick)
end

toolbarButton("📖 Scrapbook", ScrapbookController.toggle)
toolbarButton("👗 Closet", CosmeticMenuController.toggle)

print("[SleepoverChaos] client ready.")
