--!strict
-- Lifecycle — THE reusable event framework (GDD §5). One runner drives every activity and
-- every chaos event through the same phases, so new content is a small module + a config
-- entry and never touches the managers (GDD §5 goal, §14 "Start → Run → Finish → Cleanup").
--
--   notify → countdown → begin(onStart) → run(onUpdate + checkWin, until win OR timer)
--          → results(onFinish) → rewards(via callback) → cleanup(onCleanup) → reset
--
-- A "runnable" is any table exposing the optional hooks below. ActivityBase and
-- ChaosEventBase are thin wrappers that make writing these ergonomic, but Lifecycle only
-- depends on the shape, not on those classes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Trove = require(Shared.util.Trove)
local Remotes = require(Shared.net.Remotes)

local Lifecycle = {}

export type Runnable = {
	id: string,
	displayName: string,
	duration: number,
	countdown: number?,
	config: { [string]: any }?,
	-- Hooks (all optional):
	onStart: ((ctx: any) -> ())?,
	onUpdate: ((dt: number, ctx: any) -> ())?,
	checkWin: ((ctx: any) -> boolean)?, -- return true to end early as a win
	onFinish: ((ctx: any) -> ())?, -- fill ctx.result here
	onCleanup: ((ctx: any) -> ())?,
}

export type RunOptions = {
	players: { Player },
	house: Instance,
	announceCountdown: boolean?,
	-- Called with (runnable, ctx.result) after onFinish, before cleanup, so a manager can
	-- hand results to RewardService. Kept as a callback to avoid a hard dependency here.
	onResults: ((runnable: Runnable, result: any) -> ())?,
}

local function broadcastAnnounce(message: string, style: string?)
	local ok, remote = pcall(Remotes.event, "Announce")
	if ok and remote then
		remote:FireAllClients(message, style or "info")
	end
end

-- Build the RunContext object an activity/event interacts with (Types.RunContext).
local function makeContext(runnable: Runnable, options: RunOptions, trove: any): any
	local result = {
		completed = false,
		winners = {},
		scores = {},
		starAwards = {},
		scrapbook = {},
		tags = {},
	}

	-- Roster-churn subscribers, registered by activities via ctx.onPlayerJoined / onPlayerLeft.
	local joinedCallbacks: { (Player) -> () } = {}
	local leftCallbacks: { (Player) -> () } = {}

	local ctx
	ctx = {
		id = runnable.id,
		displayName = runnable.displayName,
		players = options.players,
		house = options.house,
		trove = trove,
		result = result,
		config = runnable.config or {},
		_finishRequested = false,
		_aborted = false,
		addScore = function(player: Player, amount: number)
			local uid = player.UserId
			result.scores[uid] = (result.scores[uid] or 0) + amount
		end,
		announce = function(message: string, style: string?)
			broadcastAnnounce(message, style)
		end,
		finish = function()
			ctx._finishRequested = true
		end,
		abort = function()
			ctx._aborted = true
			ctx._finishRequested = true
		end,
		-- Push arbitrary per-activity state to every client's HUD (noise meter, found counter...).
		-- Activities own the shape of the table; HudController renders what it recognises.
		broadcastState = function(state: { [string]: any })
			local ok, remote = pcall(Remotes.event, "ActivityState")
			if ok and remote then
				remote:FireAllClients(runnable.id, state)
			end
		end,
		-- Called when someone joins mid-run. Activities use this to hand a late arrival their
		-- tool; without it a second Studio client that loads after onStart gets nothing.
		onPlayerJoined = function(callback: (Player) -> ())
			table.insert(joinedCallbacks, callback)
		end,
		onPlayerLeft = function(callback: (Player) -> ())
			table.insert(leftCallbacks, callback)
		end,
	}

	local function fire(callbacks: { (Player) -> () }, player: Player)
		for _, callback in callbacks do
			local ok, err = pcall(callback, player)
			if not ok then
				warn(`[Lifecycle] roster callback error: {err}`)
			end
		end
	end

	-- Keep ctx.players live for the whole run. Refreshed on the roster signals rather than every
	-- heartbeat, so the run loop isn't allocating a fresh player table 60 times a second.
	trove:Connect(Players.PlayerAdded, function(player: Player)
		ctx.players = Players:GetPlayers()
		fire(joinedCallbacks, player)
	end)
	trove:Connect(Players.PlayerRemoving, function(player: Player)
		-- PlayerRemoving fires while the player is still in the roster, so drop them by hand.
		local remaining = {}
		for _, other in Players:GetPlayers() do
			if other ~= player then
				table.insert(remaining, other)
			end
		end
		ctx.players = remaining
		fire(leftCallbacks, player)
	end)

	return ctx
end

local function safeCall(hook: ((...any) -> ())?, ...: any)
	if not hook then
		return
	end
	local ok, err = pcall(hook, ...)
	if not ok then
		warn(`[Lifecycle] hook error: {err}`)
	end
end

-- Run one activity/event to completion. BLOCKS the calling thread (managers call this from
-- their own coroutine), returning the RunResult. Guarantees onCleanup + trove:Clean() run
-- even if a hook errors or the timer expires.
function Lifecycle.run(runnable: Runnable, options: RunOptions): any
	local trove = Trove.new()
	local ctx = makeContext(runnable, options, trove)

	-- notify + countdown (GDD §5)
	if options.announceCountdown ~= false then
		local countdown = runnable.countdown or 3
		broadcastAnnounce(`{runnable.displayName} starting...`, "event")
		for _ = countdown, 1, -1 do
			task.wait(1)
		end
	end

	-- begin
	safeCall(runnable.onStart, ctx)

	-- run loop: tick onUpdate + checkWin until win, abort, or timer expiry.
	local elapsed = 0
	local duration = runnable.duration
	local heartbeat = RunService.Heartbeat
	local connectionDone = false

	local conn
	conn = heartbeat:Connect(function(dt: number)
		if connectionDone then
			return
		end
		elapsed += dt
		safeCall(runnable.onUpdate, dt, ctx)

		if runnable.checkWin then
			local ok, won = pcall(runnable.checkWin, ctx)
			if ok and won then
				ctx._finishRequested = true
			end
		end

		if ctx._finishRequested or elapsed >= duration then
			connectionDone = true
		end
	end)

	-- Wait for the run loop to signal completion.
	while not connectionDone do
		task.wait()
	end
	conn:Disconnect()

	-- results (GDD §5). onFinish fills ctx.result; completed = not aborted.
	ctx.result.completed = not ctx._aborted
	safeCall(runnable.onFinish, ctx)

	-- rewards — handed to the manager's callback (RewardService), never granted in-activity.
	if options.onResults then
		local ok, err = pcall(options.onResults, runnable, ctx.result)
		if not ok then
			warn(`[Lifecycle] onResults error: {err}`)
		end
	end

	-- cleanup / reset (GDD §5). Always runs.
	safeCall(runnable.onCleanup, ctx)
	trove:Clean()

	return ctx.result
end

return Lifecycle
