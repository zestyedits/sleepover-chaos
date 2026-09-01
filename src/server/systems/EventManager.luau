--!strict
-- EventManager — owns the chaos-event pool and runs one through Lifecycle (GDD §7).
-- Mirrors ActivityManager but for the "small world change" events. Also exposes runById so a
-- GhostStory branch can trigger a specific event elsewhere in the house (GDD §6).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventConfig = require(Shared.config.EventConfig)
local GameConfig = require(Shared.config.GameConfig)
local Lifecycle = require(Shared.framework.Lifecycle)
local RandomUtil = require(Shared.util.RandomUtil)
local Remotes = require(Shared.net.Remotes)

local NPCManager = require(script.Parent.NPCManager)
local RewardService = require(script.Parent.RewardService)
local HouseLoader = require(script.Parent.Parent.world.HouseLoader)

local EventManager = {}

local factories: { [string]: any } = {}
local defsById: { [string]: any } = {}
local lastRunId: string? = nil
local running = false

for _, def in EventConfig.events do
	defsById[def.id] = def
end

local function loadFactories()
	local folder = script.Parent.Parent:FindFirstChild("chaosevents")
	if not folder then
		warn("[EventManager] no chaosevents folder found")
		return
	end
	for _, module in folder:GetChildren() do
		if module:IsA("ModuleScript") then
			local ok, factory = pcall(require, module)
			if ok and factory and factory.id then
				factories[factory.id] = factory
			else
				warn(`[EventManager] failed to load event {module.Name}: {factory}`)
			end
		end
	end
end

local function selectionPool(): { { value: any, weight: number } }
	local pool = {}
	for _, def in EventConfig.events do
		if factories[def.module] then
			table.insert(pool, { value = def, weight = def.weight })
		end
	end
	return pool
end

function EventManager.pickNext(): any?
	local avoid = lastRunId and defsById[lastRunId] or nil
	return RandomUtil.weightedAvoiding(selectionPool(), avoid)
end

local function runDef(def: any): any?
	local factory = factories[def.module]
	if not factory then
		return nil
	end

	running = true
	lastRunId = def.id

	local house = Workspace:FindFirstChild("House") or HouseLoader.load()
	local runnable = factory.create(def)
	runnable.countdown = GameConfig.eventCountdown

	Remotes.event("ChaosEvent"):FireAllClients(def.displayName, def.description)

	local result = Lifecycle.run(runnable, {
		players = Players:GetPlayers(),
		bots = NPCManager.getParticipants(),
		house = house,
		announceCountdown = true,
		onResults = function(runnableRef, runResult)
			RewardService.applyRunResult("ChaosEvent", runnableRef, runResult)
		end,
	})

	running = false
	return result
end

-- Run a random chaos event (no immediate repeat). BLOCKS until finished.
function EventManager.runOne(def: any?): any?
	if running then
		warn("[EventManager] runOne called while already running")
		return nil
	end
	def = def or EventManager.pickNext()
	if not def then
		warn("[EventManager] no chaos event available")
		return nil
	end
	return runDef(def)
end

-- Trigger a specific event by id (used by GhostStory branches, GDD §6). Non-blocking spawn so
-- it can fire "elsewhere in the house" during another activity.
function EventManager.triggerById(id: string)
	local def = defsById[id]
	if not def or running then
		return
	end
	task.spawn(runDef, def)
end

function EventManager.start()
	loadFactories()

	-- Studio-only force-trigger for the dev panel. triggerById already refuses to stack runs.
	Remotes.event("DevRunEvent").OnServerEvent:Connect(function(player: Player, eventId: unknown)
		if not RunService:IsStudio() then
			warn(`[EventManager] ignoring DevRunEvent from {player.Name}: not a Studio session`)
			return
		end
		if typeof(eventId) == "string" then
			EventManager.triggerById(eventId)
		end
	end)
end

return EventManager
