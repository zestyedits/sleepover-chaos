--!strict
-- GameRoundManager — the session state machine (GDD §3).
-- Walks the phase list from GameConfig, delegating to ActivityManager / EventManager, and
-- broadcasts phase changes so the client HUD tracks the sleepover. It orchestrates; it never
-- implements activity mechanics itself (GDD §14 separation of concerns).
--
--   Arrive → Activity → FreeTime → RandomEvent → Activity → LateNightChaos → Morning → loop

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.config.GameConfig)
local Remotes = require(Shared.net.Remotes)

local ActivityManager = require(script.Parent.ActivityManager)
local EventManager = require(script.Parent.EventManager)
local RewardService = require(script.Parent.RewardService)

local GameRoundManager = {}

local currentPhase = "Idle"
local phaseTimeLeft = 0

local function broadcastPhase(name: string, duration: number, info: { [string]: any }?)
	currentPhase = name
	phaseTimeLeft = duration
	Remotes.event("PhaseChanged"):FireAllClients(name, duration, info or {})
end

-- A simple counting-down "wait" that keeps clients' timers in sync each second.
local function timedPhase(name: string, duration: number, info: { [string]: any }?)
	broadcastPhase(name, duration, info)
	local remaining = duration
	while remaining > 0 do
		task.wait(1)
		remaining -= 1
		phaseTimeLeft = remaining
	end
end

-- Grant end-of-session rewards to everyone who reached Morning (GDD §3, §10).
local function awardCompletion()
	for _, player in Players:GetPlayers() do
		RewardService.grantSessionCompletion(player, GameConfig.completionScrapbook)
	end
end

-- Run one phase according to its config entry. Activity/RandomEvent/LateNightChaos phases
-- hand control to their managers (which block until the run finishes); the rest just wait.
local function runPhase(phase: any)
	if phase.name == "Activity" then
		broadcastPhase("Activity", phase.duration, {})
		ActivityManager.runOne() -- blocks; its own timer bounds the run
	elseif phase.name == "RandomEvent" then
		broadcastPhase("RandomEvent", phase.duration, {})
		EventManager.runOne()
	elseif phase.name == "LateNightChaos" then
		-- Late-night: chain a chaos event, and sometimes a second for escalating weirdness.
		broadcastPhase("LateNightChaos", phase.duration, {})
		EventManager.runOne()
	elseif phase.name == "Morning" then
		timedPhase("Morning", phase.duration, {})
		awardCompletion()
	else
		-- Arrive / FreeTime: social/explore beats (GDD §3).
		timedPhase(phase.name, phase.duration, {})
	end
end

-- The main loop. One iteration = one full sleepover, then it repeats (GDD §3 "play another").
local function sessionLoop()
	while true do
		for _, phase in GameConfig.phases do
			runPhase(phase)
		end
		-- Brief intermission before the next sleepover.
		timedPhase("Arrive", 4, { intermission = true })
	end
end

function GameRoundManager.getPhase(): (string, number)
	return currentPhase, phaseTimeLeft
end

function GameRoundManager.start()
	task.spawn(function()
		-- Small delay so systems and the first players settle before the loop begins.
		task.wait(2)
		sessionLoop()
	end)
end

return GameRoundManager
