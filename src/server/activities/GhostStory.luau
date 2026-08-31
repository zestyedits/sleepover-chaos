--!strict
-- GhostStory (GDD §6) — everyone gathers; a short interactive story plays and players vote on
-- what happens next. Sometimes nothing happens... and sometimes a choice triggers a real chaos
-- event elsewhere in the house. The story is driven in a spawned task so the Lifecycle run loop
-- still bounds it with the activity timer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ActivityBase = require(Shared.framework.ActivityBase)
local RandomUtil = require(Shared.util.RandomUtil)
local Remotes = require(Shared.net.Remotes)

local EventManager = require(script.Parent.Parent.systems.EventManager)
local NPCManager = require(script.Parent.Parent.systems.NPCManager)
local HouseBuilder = require(script.Parent.Parent.world.HouseBuilder)

local VOTE_WINDOW = 8 -- seconds per story node

-- A tiny branching story. `triggers` names a chaos event id to fire if that branch is chosen.
local STORY = {
	start = {
		id = "start",
		text = "The house creaks. Someone swears they heard footsteps in the attic. What do you do?",
		choices = {
			{ label = "Investigate the noise", next = "attic" },
			{ label = "Hide under the blankets", next = "blankets" },
		},
	},
	attic = {
		id = "attic",
		text = "You creep toward the attic door. It's slightly open, and it's cold. Do you open it?",
		choices = {
			{ label = "Fling it open!", next = "ending_brave", triggers = "StrangeNoise" },
			{ label = "Nope. Back to bed.", next = "blankets" },
		},
	},
	blankets = {
		id = "blankets",
		text = "Safe under the covers... until every light in the house flickers. Peek out?",
		choices = {
			{ label = "Peek", next = "ending_dark", triggers = "PowerOutage" },
			{ label = "Stay hidden till morning", next = "ending_safe" },
		},
	},
	ending_brave = {
		id = "ending_brave",
		text = "It was just a raccoon. A VERY startled raccoon. The end.",
		choices = {},
	},
	ending_dark = {
		id = "ending_dark",
		text = "The dark swallows the room. Good story. Great timing. The end.",
		choices = {},
	},
	ending_safe = {
		id = "ending_safe",
		text = "Nothing happened. You lived. Boring, but you lived. The end.",
		choices = {},
	},
}

return ActivityBase.extend("GhostStory", {
	onStart = function(ctx)
		ctx.announce("Gather round for a ghost story...", "event")
		local anchor = HouseBuilder.getAnchor(ctx.house, "GhostStory", "gather")
		if anchor then
			NPCManager.setGatherPoint(anchor.Position)
		end

		local settings = ctx.config
		local votes: { [Player]: number } = {}
		local voteConn = Remotes.event("GhostStoryChoice").OnServerEvent
			:Connect(function(player, choiceIndex)
				if typeof(choiceIndex) == "number" then
					votes[player] = choiceIndex
				end
			end)
		ctx.trove:Add(voteConn)

		-- The story thread outlives nothing. It is owned by the run trove (which cancels
		-- threads) AND gated on `active`, because a thread parked in task.wait can still be
		-- resumed in the window between the run loop stopping and cleanup running. Without
		-- both, an expired ghost story could fire a real chaos event minutes later, in the
		-- middle of a completely different activity.
		local active = true
		ctx.trove:AddCleanup(function()
			active = false
		end)

		ctx.trove:Add(task.spawn(function()
			local node = STORY.start
			local safety = 0
			while node and #node.choices > 0 and safety < 6 do
				safety += 1
				table.clear(votes)

				local choiceLabels = {}
				for _, choice in node.choices do
					table.insert(choiceLabels, choice.label)
				end
				Remotes.event("GhostStoryPrompt"):FireAllClients(node.id, node.text, choiceLabels)

				task.wait(VOTE_WINDOW)
				if not active then
					return
				end

				-- Tally votes; reward participation (GDD §6).
				local tally = {}
				for _ in node.choices do
					table.insert(tally, 0)
				end
				for player, index in votes do
					if tally[index] then
						tally[index] += 1
						ctx.addScore(player, settings.pointsForParticipating or 1)
						if not table.find(ctx.result.winners, player) then
							table.insert(ctx.result.winners, player)
						end
					end
				end

				-- Pick the winning choice (ties / no votes -> random choice).
				local bestIndex, bestVotes = 1, -1
				for i, count in tally do
					if count > bestVotes then
						bestVotes = count
						bestIndex = i
					end
				end
				if bestVotes <= 0 then
					bestIndex = math.random(1, #node.choices)
				end
				local chosen = node.choices[bestIndex]

				-- A branch may trigger a real event elsewhere in the house (GDD §6).
				if
					active
					and chosen.triggers
					and RandomUtil.chance(settings.chanceToTriggerEvent or 0.4)
				then
					ctx.announce("...wait. Did that actually just happen?!", "chaos")
					EventManager.triggerById(chosen.triggers)
				end

				node = STORY[chosen.next]
			end

			-- Final node text, then end the activity.
			if active and node and node.text then
				Remotes.event("GhostStoryPrompt"):FireAllClients(node.id, node.text, {})
				ctx.announce(node.text, "result")
			end
			task.wait(2)
			if active then
				ctx.finish()
			end
		end))
	end,

	onCleanup = function(_ctx)
		NPCManager.setGatherPoint(nil)
	end,
})
