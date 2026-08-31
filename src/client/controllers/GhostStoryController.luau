--!strict
-- GhostStoryController — renders the interactive Ghost Story prompt and sends the player's vote
-- (GDD §6). The server tallies votes and branches; this is purely the choice UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.net.Remotes)

local UIUtil = require(script.Parent.UIUtil)

local GhostStoryController = {}

local panel: Frame
local storyText: TextLabel
local choiceHolder: Frame

local function clearChoices()
	for _, child in choiceHolder:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function build(parent: ScreenGui)
	panel = UIUtil.make("Frame", {
		Name = "GhostStoryPanel",
		Parent = parent,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -240),
		Size = UDim2.new(0, 520, 0, 200),
		BackgroundColor3 = UIUtil.palette.bg,
		BackgroundTransparency = 0.05,
		Visible = false,
	}, { UIUtil.corner(14), UIUtil.padding(12) }) :: Frame

	storyText = UIUtil.make("TextLabel", {
		Parent = panel,
		Size = UDim2.new(1, 0, 0, 80),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextScaled = true,
		TextWrapped = true,
		TextColor3 = UIUtil.palette.text,
		Text = "",
	}) :: TextLabel

	choiceHolder = UIUtil.make("Frame", {
		Parent = panel,
		Position = UDim2.new(0, 0, 0, 88),
		Size = UDim2.new(1, 0, 1, -88),
		BackgroundTransparency = 1,
	}, {
		UIUtil.make("UIListLayout", {
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	}) :: Frame
end

function GhostStoryController.start(parent: ScreenGui)
	build(parent)

	Remotes.event("GhostStoryPrompt").OnClientEvent:Connect(function(nodeId: string, text: string, choices: { string })
		storyText.Text = text
		clearChoices()

		if not choices or #choices == 0 then
			panel.Visible = true
			task.delay(4, function()
				panel.Visible = false
			end)
			return
		end

		panel.Visible = true
		for index, label in choices do
			local button = UIUtil.make("TextButton", {
				Parent = choiceHolder,
				Size = UDim2.new(1, 0, 0, 34),
				BackgroundColor3 = UIUtil.palette.accent,
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextColor3 = UIUtil.palette.bg,
				Text = label,
			}, { UIUtil.corner(8), UIUtil.padding(4) }) :: TextButton

			button.MouseButton1Click:Connect(function()
				Remotes.event("GhostStoryChoice"):FireServer(index)
				-- Highlight the picked option.
				for _, other in choiceHolder:GetChildren() do
					if other:IsA("TextButton") then
						other.BackgroundColor3 = UIUtil.palette.panel
						other.AutoButtonColor = false
					end
				end
				button.BackgroundColor3 = UIUtil.palette.good
			end)
		end
	end)
end

return GhostStoryController
