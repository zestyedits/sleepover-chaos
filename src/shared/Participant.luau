--!strict
-- Participant — the thing that plays an activity. A human, or a bot.
--
-- Until now "who is in this run" meant `{ Player }`, and scoring went through
-- `result.scores[player.UserId]`. That made NPC guests structurally incapable of playing: they
-- have no UserId, so they could be a *target* (Pillow Fight hits them) but never a *subject*
-- (nobody could score for what a guest did). A solo player had scenery, not opponents.
--
-- ── Why bots get ids below a floor ──────────────────────────────────────────────────────────
-- A bot's id is a large negative number, below BOT_ID_FLOOR. Live Roblox UserIds are positive,
-- so the spaces cannot collide, and more importantly:
--
--     Players:GetPlayerByUserId(-1000003)   -->   nil
--
-- RewardService turns score keys back into players with exactly that call. So a bot is
-- structurally incapable of earning stars, XP or scrapbook entries — the exclusion is a property
-- of the id space, not a guard someone can forget to write. Verified in Studio: out-of-range and
-- zero ids return nil rather than erroring.
--
-- The FLOOR is what makes this safe rather than merely clever. Studio hands local-server test
-- players negative UserIds (-1, -2, ...), so "any negative id is a bot" would be wrong in the
-- exact scenario we most need to work: a two-client playtest.
--
-- ── Identity ────────────────────────────────────────────────────────────────────────────────
-- Compare participants with `Participant.same(a, b)`, never with `==`. Ids are the identity;
-- table identity is not guaranteed across calls, and comparing by id also lets a Player and a
-- Participant wrapping that Player compare equal.

export type Participant = {
	id: number, -- Player.UserId for humans; a negative synthetic id for bots
	name: string,
	isBot: boolean,
	player: Player?, -- set iff not isBot
	model: Model?, -- set iff isBot
}

local Participant = {}

-- Bot ids live BELOW this floor, and the distance matters.
--
-- Roblox hands out negative UserIds to local-server test players in Studio: Player1 is -1,
-- Player2 is -2, and so on. So the obvious "count down from -1" scheme collides with exactly the
-- two-client playtest this whole feature exists to make work — a bot and a test player would
-- share a score entry. The floor puts a million ids between the two spaces.
--
-- Do not relax this constant.
local BOT_ID_FLOOR = -1000000

-- Monotonic for the server's lifetime, so a despawned guest's id is never reused by a new one,
-- which would let a stale score entry bleed into the next run.
local nextBotId = BOT_ID_FLOOR

-- Explicit rather than relying on "negative means bot" — Studio test players are negative too.
function Participant.isBotId(id: number): boolean
	return id <= BOT_ID_FLOOR
end

-- Humans are cached so repeated wrapping does not churn tables every heartbeat. Bots are owned by
-- BotService, which holds its own mapping, so they are deliberately not cached here.
local humanCache: { [Player]: Participant } = {}

function Participant.fromPlayer(player: Player): Participant
	local existing = humanCache[player]
	if existing then
		-- Display names can change mid-session; keep the cached entry honest.
		existing.name = player.DisplayName
		return existing
	end
	local participant: Participant = {
		id = player.UserId,
		name = player.DisplayName,
		isBot = false,
		player = player,
		model = nil,
	}
	humanCache[player] = participant
	return participant
end

-- Drop a human's cache entry. Called from BotService on PlayerRemoving; without it the cache
-- pins every player who has ever joined for the life of the server.
function Participant.forget(player: Player)
	humanCache[player] = nil
end

function Participant.forBot(model: Model, name: string): Participant
	nextBotId -= 1
	return {
		id = nextBotId,
		name = name,
		isBot = true,
		player = nil,
		model = model,
	}
end

-- True for a table shaped like a Participant. Used to tell a Participant from a Player at the
-- boundaries where both are accepted.
function Participant.is(subject: any): boolean
	return type(subject) == "table" and type(subject.id) == "number" and subject.isBot ~= nil
end

-- Normalise either form to a Participant. Returns nil for anything else rather than erroring,
-- so a bad caller degrades to "did not score" instead of taking the whole run down.
function Participant.resolve(subject: any): Participant?
	if Participant.is(subject) then
		return subject
	end
	if typeof(subject) == "Instance" and subject:IsA("Player") then
		return Participant.fromPlayer(subject :: Player)
	end
	return nil
end

-- Identity compare. Accepts Players and Participants on either side.
function Participant.same(a: any, b: any): boolean
	local left, right = Participant.resolve(a), Participant.resolve(b)
	return left ~= nil and right ~= nil and left.id == right.id
end

-- Where this participant physically is, for range/proximity checks that need to treat humans and
-- bots identically. Nil if they have no body right now (respawning, despawned).
function Participant.rootPart(participant: Participant): BasePart?
	if participant.isBot then
		local model = participant.model
		if model and model.Parent then
			return model.PrimaryPart
		end
		return nil
	end
	local player = participant.player
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

function Participant.humanoid(participant: Participant): Humanoid?
	local root = Participant.rootPart(participant)
	local model = root and root.Parent
	return if model then model:FindFirstChildOfClass("Humanoid") else nil
end

-- Only the humans, for the places that genuinely mean "real players" — reward payouts, remote
-- fires, profile lookups.
function Participant.humansOf(participants: { Participant }): { Player }
	local players: { Player } = {}
	for _, participant in participants do
		local player = participant.player
		if not participant.isBot and player and player.Parent then
			table.insert(players, player)
		end
	end
	return players
end

return Participant
