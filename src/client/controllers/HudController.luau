--!strict
-- HudController — the always-on HUD: current phase + countdown, active objective, and the
-- player's stars / level / rank (GDD §3, §9). Presentation only; all values come from the
-- server over Remotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.net.Remotes)

local UIUtil = require(script.Parent.UIUtil)

local HudController = {}

local phaseLabel: TextLabel
local objectiveLabel: TextLabel
local starsLabel: TextLabel
local rankLabel: TextLabel

local countdownValue = 0

local function build(parent: ScreenGui)
	local palette = UIUtil.palette

	-- Top-center phase pill.
	local phaseFrame = UIUtil.make("Frame", {
		Name = "PhasePill",
		Parent = parent,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.new(0, 320, 0, 56),
		BackgroundColor3 = palette.panel,
		BackgroundTransparency = 0.1,
	}, { UIUtil.corner(12) }) :: Frame

	phaseLabel = UIUtil.make("TextLabel", {
		Name = "Phase",
		Parent = phaseFrame,
		Size = UDim2.new(1, 0, 0.6, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = palette.text,
		Text = "Getting cozy...",
	}) :: TextLabel

	objectiveLabel = UIUtil.make("TextLabel", {
		Name = "Objective",
		Parent = phaseFrame,
		Position = UDim2.new(0, 0, 0.6, 0),
		Size = UDim2.new(1, 0, 0.4, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextScaled = true,
		TextColor3 = palette.subtext,
		Text = "",
	}) :: TextLabel

	-- Top-right progression card.
	local card = UIUtil.make("Frame", {
		Name = "ProgressCard",
		Parent = parent,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.new(0, 200, 0, 56),
		BackgroundColor3 = palette.panel,
		BackgroundTransparency = 0.1,
	}, { UIUtil.corner(12), UIUtil.padding(8) }) :: Frame

	starsLabel = UIUtil.make("TextLabel", {
		Name = "Stars",
		Parent = card,
		Size = UDim2.new(1, 0, 0.55, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = palette.warn,
		Text = "⭐ 0",
	}) :: TextLabel

	rankLabel = UIUtil.make("TextLabel", {
		Name = "Rank",
		Parent = card,
		Position = UDim2.new(0, 0, 0.55, 0),
		Size = UDim2.new(1, 0, 0.45, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = palette.subtext,
		Text = "Lv 1 · Guest",
	}) :: TextLabel
end

local function setPhaseText()
	if countdownValue > 0 then
		phaseLabel.Text = `{phaseLabel:GetAttribute("Base") or "Sleepover"}  ({countdownValue}s)`
	end
end

function HudController.start(parent: ScreenGui)
	build(parent)

	Remotes.event("PhaseChanged").OnClientEvent:Connect(function(name: string, duration: number)
		local pretty = ({
			Arrive = "🛎️ Arriving",
			Activity = "🎉 Activity",
			FreeTime = "🛋️ Free Time",
			RandomEvent = "❓ Random Event",
			LateNightChaos = "🌙 Late-Night Chaos",
			Morning = "☀️ Morning",
		})[name] or name
		phaseLabel:SetAttribute("Base", pretty)
		phaseLabel.Text = pretty
		objectiveLabel.Text = ""
		countdownValue = math.floor(duration)
		setPhaseText()
	end)

	Remotes.event("ActivityStarted").OnClientEvent
		:Connect(function(displayName: string, objective: string)
			objectiveLabel.Text = objective or ""
		end)

	Remotes.event("ActivityEnded").OnClientEvent:Connect(function(displayName: string, summary)
		if summary and summary.topName then
			objectiveLabel.Text = `Winner: {summary.topName} ({summary.topScore})`
		end
	end)

	Remotes.event("DataUpdated").OnClientEvent:Connect(function(view)
		if not view then
			return
		end
		starsLabel.Text = `⭐ {view.stars}`
		rankLabel.Text = `Lv {view.level} · {view.rank}`
	end)

	-- Local countdown ticker (server also re-broadcasts each phase).
	task.spawn(function()
		while true do
			task.wait(1)
			if countdownValue > 0 then
				countdownValue -= 1
				setPhaseText()
			end
		end
	end)

	-- Ask the server for our current profile once on join.
	task.spawn(function()
		local ok, view = pcall(function()
			return Remotes.func("RequestProfile"):InvokeServer()
		end)
		if ok and view then
			starsLabel.Text = `⭐ {view.stars}`
			rankLabel.Text = `Lv {view.level} · {view.rank}`
		end
	end)
end

return HudController
