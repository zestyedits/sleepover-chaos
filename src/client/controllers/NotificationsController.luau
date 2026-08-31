--!strict
-- NotificationsController — toast messages for announcements, chaos events, and scrapbook
-- unlocks (GDD §5 "players notified", §7, §10). These are the moments that make the shared
-- story land ("MOM IS COMING", "WHY IS THERE A RACCOON IN THE KITCHEN?", GDD §18).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.net.Remotes)

local UIUtil = require(script.Parent.UIUtil)

local NotificationsController = {}

local container: Frame
local toastCounter = 0

local function toast(message: string, color: Color3, big: boolean?)
	-- Newer toasts get a lower LayoutOrder so they sort to the bottom of the list.
	toastCounter -= 1
	local frame = UIUtil.make("Frame", {
		Parent = container,
		Size = UDim2.new(1, 0, 0, big and 64 or 40),
		BackgroundColor3 = UIUtil.palette.panel,
		BackgroundTransparency = 0.05,
		LayoutOrder = toastCounter,
	}, { UIUtil.corner(10), UIUtil.padding(6) }) :: Frame

	local label = UIUtil.make("TextLabel", {
		Parent = frame,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Font = big and Enum.Font.GothamBold or Enum.Font.Gotham,
		TextScaled = true,
		TextColor3 = color,
		Text = message,
		TextWrapped = true,
	}) :: TextLabel

	-- Slide-in, hold, fade-out.
	frame.BackgroundTransparency = 1
	label.TextTransparency = 1
	TweenService:Create(frame, TweenInfo.new(0.2), { BackgroundTransparency = 0.05 }):Play()
	TweenService:Create(label, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()

	task.delay(big and 5 or 3.5, function()
		TweenService:Create(frame, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		local fade = TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		frame:Destroy()
	end)
end

function NotificationsController.start(parent: ScreenGui)
	container = UIUtil.make("Frame", {
		Name = "Toasts",
		Parent = parent,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(0, 460, 0, 220),
		BackgroundTransparency = 1,
	}, {
		UIUtil.make("UIListLayout", {
			Padding = UDim.new(0, 6),
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame

	Remotes.event("Announce").OnClientEvent:Connect(function(message: string, style: string)
		toast(message, UIUtil.styleColor(style or "info"), style == "chaos")
	end)

	Remotes.event("ChaosEvent").OnClientEvent:Connect(function(displayName: string, description: string)
		toast(`{displayName}: {description}`, UIUtil.palette.chaos, true)
	end)

	Remotes.event("ScrapbookUnlocked").OnClientEvent:Connect(function(id: string, info)
		local prefix = info and info.rare and "🌟 Rare Memory!" or "📖 New Memory"
		toast(`{prefix}  —  {info and info.title or id}`, UIUtil.palette.good, true)
	end)
end

return NotificationsController
