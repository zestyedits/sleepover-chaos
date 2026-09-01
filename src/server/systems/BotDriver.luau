--!strict
-- BotDriver — the shared machinery that makes bots act during a run.
--
-- A bot cannot press a button. It cannot fire a RemoteEvent and it cannot trigger a
-- ProximityPrompt, so everything a human does through the UI has to be driven server-side. The
-- shape that keeps this from turning into five bespoke AIs is: an activity supplies a `plan`
-- function that answers one question — "what should THIS bot do next?" — and the driver handles
-- the tedious parts: ticking, walking, arrival detection, staggering, and cleanup.
--
-- ── Difficulty is RATE, never VALUE ─────────────────────────────────────────────────────────
-- `skill` controls how often a bot acts. It never changes what an action is worth. A bot's hit
-- scores exactly what a human's hit scores, which keeps the scoreboard directly comparable and
-- means there is only one balance surface instead of two. Turning bots down makes them slower,
-- not cheaper to beat.
--
-- ── Why one loop, not one per bot ───────────────────────────────────────────────────────────
-- Planning is O(bots) at ~1.5s intervals, which is nothing. A thread per bot would multiply the
-- cleanup surface by the party size for no benefit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.config.GameConfig)
local Participant = require(Shared.Participant)

local NPCManager = require(script.Parent.NPCManager)

type Participant = Participant.Participant

local BotDriver = {}

-- A single instruction for one bot.
export type Job = {
	behavior: NPCManager.Behavior, -- how to move: "Seek" walks straight at the goal
	goal: BasePart?, -- where; nil means act where you stand
	arriveRadius: number?, -- how close counts as arrived (default 8)
	onArrive: ((bot: Participant, guest: Model) -> ())?, -- what to do once there
}

export type DriverSpec = {
	interval: number?, -- seconds between planning ticks
	skill: number?, -- 0..1 chance a given bot plans on a given tick
	plan: (ctx: any, bot: Participant, guest: Model) -> Job?,
}

local MIN_INTERVAL = 0.75
local DEFAULT_ARRIVE_RADIUS = 8

-- Start driving every bot in this run. Returns a stop function; add it to ctx.trove.
--
-- The `active` flag is belt-and-braces alongside the trove. The trove cancels the thread, but a
-- thread parked in task.wait can still be resumed in the window between the run loop stopping
-- and cleanup running — which is exactly the bug that let a Hide & Seek seeker tool follow a
-- player into the next activity.
function BotDriver.run(ctx: any, spec: DriverSpec): () -> ()
	local active = true
	local interval = math.max(spec.interval or GameConfig.botActionInterval or 1.5, MIN_INTERVAL)
	local skill = spec.skill or GameConfig.botSkill or 0.6

	-- Jobs in flight, keyed by participant id. A bot keeps walking toward its goal across ticks
	-- rather than re-planning from scratch every time, so it does not dither on the spot.
	local jobs: { [number]: Job } = {}

	local function step(bot: Participant)
		local guest = bot.model
		if not guest or not guest.Parent then
			jobs[bot.id] = nil
			return
		end

		local job = jobs[bot.id]
		if job then
			local goal = job.goal
			-- Goal destroyed mid-walk (snack taken, prop cleaned up): drop it and re-plan.
			if goal and not goal.Parent then
				jobs[bot.id] = nil
				NPCManager.clearGuestBehavior(guest)
				return
			end
			if goal then
				local root = Participant.rootPart(bot)
				local radius = job.arriveRadius or DEFAULT_ARRIVE_RADIUS
				if root and (root.Position - goal.Position).Magnitude <= radius then
					jobs[bot.id] = nil
					NPCManager.clearGuestBehavior(guest)
					if job.onArrive then
						local ok, err = pcall(job.onArrive, bot, guest)
						if not ok then
							warn(`[BotDriver] {ctx.id}: onArrive error: {err}`)
						end
					end
				end
				return -- still walking; do not plan over the top of it
			end
			-- Goal-less job: act immediately and clear.
			jobs[bot.id] = nil
			if job.onArrive then
				pcall(job.onArrive, bot, guest)
			end
			return
		end

		-- Idle bot. Roll against skill so the party does not move as one organism.
		if math.random() > skill then
			return
		end
		local ok, planned = pcall(spec.plan, ctx, bot, guest)
		if not ok then
			warn(`[BotDriver] {ctx.id}: plan error: {planned}`)
			return
		end
		if not planned then
			return
		end
		jobs[bot.id] = planned
		local goal = planned.goal
		NPCManager.setGuestBehavior(guest, planned.behavior, goal and goal.Position or nil)
	end

	ctx.trove:Add(task.spawn(function()
		-- Stagger the first tick so bots do not all act on the same frame as the countdown ends.
		task.wait(math.random() * interval)
		while active do
			for _, bot in ctx.bots() do
				if not active then
					break
				end
				step(bot)
			end
			task.wait(interval)
		end
	end))

	local stop = function()
		active = false
		for _, bot in ctx.bots() do
			local guest = bot.model
			if guest and guest.Parent then
				NPCManager.clearGuestBehavior(guest)
			end
		end
		table.clear(jobs)
	end
	ctx.trove:AddCleanup(stop)
	return stop
end

-- For actions that are not a place you walk to — voting, reacting, choosing. Fires `action` once
-- per bot, spread across `window` seconds so they do not all answer on the same frame.
function BotDriver.stagger(ctx: any, window: number, action: (bot: Participant, guest: Model) -> ())
	local active = true
	ctx.trove:AddCleanup(function()
		active = false
	end)

	for _, bot in ctx.bots() do
		local delay = math.random() * math.max(window, 0.1)
		ctx.trove:Add(task.delay(delay, function()
			if not active then
				return
			end
			local guest = bot.model
			if not guest or not guest.Parent then
				return
			end
			local ok, err = pcall(action, bot, guest)
			if not ok then
				warn(`[BotDriver] {ctx.id}: staggered action error: {err}`)
			end
		end))
	end
end

-- Nearest tagged part to a participant, skipping any the caller has ruled out. The workhorse for
-- "find me a snack / a spot / a bed I can actually reach".
function BotDriver.nearestPart(
	bot: Participant,
	candidates: { BasePart },
	accept: ((part: BasePart) -> boolean)?
): BasePart?
	local root = Participant.rootPart(bot)
	if not root then
		return nil
	end
	local best: BasePart?, bestDistance = nil, math.huge
	for _, part in candidates do
		if part.Parent and (not accept or accept(part)) then
			local distance = (root.Position - part.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = part, distance
			end
		end
	end
	return best
end

-- Nearest other participant, for activities where the target is a person rather than a prop.
function BotDriver.nearestParticipant(
	ctx: any,
	bot: Participant,
	maxDistance: number?
): (Participant?, BasePart?)
	local root = Participant.rootPart(bot)
	if not root then
		return nil, nil
	end
	local limit = maxDistance or math.huge
	local best: Participant?, bestRoot: BasePart?, bestDistance = nil, nil, limit
	for _, other in ctx.participants do
		if other.id ~= bot.id then
			local otherRoot = Participant.rootPart(other)
			if otherRoot then
				local distance = (root.Position - otherRoot.Position).Magnitude
				if distance < bestDistance then
					best, bestRoot, bestDistance = other, otherRoot, distance
				end
			end
		end
	end
	return best, bestRoot
end

return BotDriver
