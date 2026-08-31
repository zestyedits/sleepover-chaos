--!strict
-- ActivityManager — owns the activity pool and runs one at a time through Lifecycle (GDD §5, §14).
-- It is the ONLY code that drives an activity's run loop; individual activities never control
-- the game (GDD §14). Selection is weighted-random with no immediate repeat (GDD §5).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ActivityConfig = require(Shared.config.ActivityConfig)
local GameConfig = require(Shared.config.GameConfig)
local Lifecycle = require(Shared.framework.Lifecycle)
local RandomUtil = require(Shared.util.RandomUtil)
local Remotes = require(Shared.net.Remotes)

local RewardService = require(script.Parent.RewardService)
local NPCManager = require(script.Parent.NPCManager)
local HouseBuilder = require(script.Parent.Parent.world.HouseBuilder)

local ActivityManager = {}

-- id -> activity factory (loaded from src/server/activities).
local factories: { [string]: any } = {}
local defsById: { [string]: any } = {}
local lastRunId: string? = nil
local running = false
-- Set by the Studio-only dev panel; consumed by the next pickNext() so a forced activity still
-- goes through the normal run path rather than a parallel one.
local pendingDevDef: any? = nil

for _, def in ActivityConfig.activities do
	defsById[def.id] = def
end

local function loadFactories()
	local activitiesFolder = script.Parent.Parent:FindFirstChild("activities")
	if not activitiesFolder then
		warn("[ActivityManager] no activities folder found")
		return
	end
	for _, module in activitiesFolder:GetChildren() do
		if module:IsA("ModuleScript") then
			local ok, factory = pcall(require, module)
			if ok and factory and factory.id then
				factories[factory.id] = factory
			else
				warn(`[ActivityManager] failed to load activity {module.Name}: {factory}`)
			end
		end
	end
end

-- Build the weighted list of activities that actually have a loaded module.
local function selectionPool(): { { value: any, weight: number } }
	local pool = {}
	for _, def in ActivityConfig.activities do
		if factories[def.module] then
			table.insert(pool, { value = def, weight = def.weight })
		end
	end
	return pool
end

-- Pick the next activity def (no immediate repeat).
function ActivityManager.pickNext(): any?
	if pendingDevDef then
		local def = pendingDevDef
		pendingDevDef = nil
		return def
	end
	local pool = selectionPool()
	return RandomUtil.weightedAvoiding(
		pool,
		(function()
			for _, def in ActivityConfig.activities do
				if def.id == lastRunId then
					return def
				end
			end
			return nil
		end)()
	)
end

-- Run one activity to completion. BLOCKS until finished (called from GameRoundManager's thread).
function ActivityManager.runOne(def: any?): any?
	if running then
		warn("[ActivityManager] runOne called while already running")
		return nil
	end
	def = def or ActivityManager.pickNext()
	if not def then
		warn("[ActivityManager] no activity available to run")
		return nil
	end

	local factory = factories[def.module]
	if not factory then
		return nil
	end

	running = true
	lastRunId = def.id

	local house = Workspace:FindFirstChild("House") or HouseBuilder.build()
	local runnable = factory.create(def)
	runnable.countdown = GameConfig.activityCountdown

	-- Point NPCs at this activity's anchor so the party congregates (GDD §13). This only sets
	-- the WHERE; the activity's own onStart picks the behaviour (hide, get in bed, gather), and
	-- a "Gather" behaviour with no position keeps whatever anchor we set here.
	local anchor = HouseBuilder.getAnchor(house, def.module)
	if anchor then
		NPCManager.setGatherPoint(anchor.Position)
	end

	-- Tell clients an activity is starting (HUD objective).
	Remotes.event("ActivityStarted"):FireAllClients(def.displayName, def.objective, def.duration)

	local result = Lifecycle.run(runnable, {
		players = Players:GetPlayers(),
		house = house,
		announceCountdown = true,
		onResults = function(runnableRef, runResult)
			RewardService.applyRunResult("Activity", runnableRef, runResult)
		end,
	})

	-- Summarize for the client (winners + top score).
	local topScore, topName = 0, nil
	for uid, score in result.scores do
		if score > topScore then
			topScore = score
			local player = Players:GetPlayerByUserId(uid)
			topName = player and player.Name or nil
		end
	end
	Remotes.event("ActivityEnded"):FireAllClients(def.displayName, {
		topScore = topScore,
		topName = topName,
	})

	NPCManager.setGatherPoint(nil)
	running = false
	return result
end

-- Studio-only: force-run an activity from the dev panel. Without this, testing one activity
-- repeatedly means sitting through Arrive/FreeTime and hoping weighted-random cooperates.
-- The IsStudio check lives HERE, on the server — the client claiming to be in Studio is not
-- evidence of anything.
local function handleDevRun(player: Player, activityId: unknown)
	if not RunService:IsStudio() then
		warn(`[ActivityManager] ignoring DevRunActivity from {player.Name}: not a Studio session`)
		return
	end
	if typeof(activityId) ~= "string" then
		return
	end
	local def = defsById[activityId]
	if not def or not factories[def.module] then
		return
	end

	if running then
		-- Something is mid-run; queue it rather than stomping a live activity.
		pendingDevDef = def
		Remotes.event("Announce")
			:FireAllClients(`[dev] {def.displayName} queued for the next activity.`, "info")
		return
	end
	task.spawn(ActivityManager.runOne, def)
end

function ActivityManager.start()
	loadFactories()
	Remotes.event("DevRunActivity").OnServerEvent:Connect(handleDevRun)
end

return ActivityManager
