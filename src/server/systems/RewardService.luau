--!strict
-- RewardService — the ONLY place stars/xp/levels/scrapbook are granted (GDD §9, §10).
-- Activities and events return RunResults; this service interprets them, applies the level
-- curve and rank thresholds from RankConfig, unlocks scrapbook memories from ScrapbookConfig,
-- and pushes updates to the client. Nothing else pays out — that keeps balance in one place
-- and makes "no pay-to-win" (GDD §12) enforceable.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Participant = require(Shared.Participant)
local RankConfig = require(Shared.config.RankConfig)
local Remotes = require(Shared.net.Remotes)
local ScrapbookConfig = require(Shared.config.ScrapbookConfig)

local PlayerDataService = require(script.Parent.PlayerDataService)

local RewardService = {}

local function pushView(player: Player)
	local view = PlayerDataService.view(player)
	if view then
		Remotes.event("DataUpdated"):FireClient(player, view)
	end
end

-- Apply xp and roll levels/rank forward. Mutates the profile in place.
local function applyXp(profile: any, xp: number)
	profile.xp += xp
	while profile.level < RankConfig.maxLevel do
		local needed = RankConfig.xpForLevel(profile.level)
		if profile.xp >= needed then
			profile.xp -= needed
			profile.level += 1
		else
			break
		end
	end
	profile.rank = RankConfig.rankForLevel(profile.level)
end

-- Grant stars (and matching xp) to a player. Central entry point.
function RewardService.grantStars(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	PlayerDataService.update(player, function(profile)
		profile.stars += amount
		applyXp(profile, amount * RankConfig.rewards.xpPerStar)
	end)
	pushView(player)
end

-- Unlock a scrapbook achievement (once). Returns true if newly unlocked. Grants the
-- achievement's star reward and any sticker cosmetic.
function RewardService.unlockScrapbook(player: Player, achievementId: string): boolean
	local def = ScrapbookConfig.get(achievementId)
	if not def then
		return false
	end
	local profile = PlayerDataService.get(player)
	if not profile then
		return false
	end
	if profile.scrapbook[achievementId] then
		return false -- already unlocked
	end

	PlayerDataService.update(player, function(p)
		p.scrapbook[achievementId] = os.time()
		if def.rare then
			p.stats.rareEventsWitnessed = (p.stats.rareEventsWitnessed or 0) + 1
		end
		if def.sticker then
			p.cosmetics.owned[def.sticker] = true
		end
	end)

	if def.starReward and def.starReward > 0 then
		RewardService.grantStars(player, def.starReward)
	end

	Remotes.event("ScrapbookUnlocked"):FireClient(player, achievementId, {
		title = def.title,
		description = def.description,
		rare = def.rare == true,
		sticker = def.sticker,
	})
	pushView(player)
	return true
end

-- Bump an arbitrary stat counter.
function RewardService.incrementStat(player: Player, stat: string, amount: number?)
	PlayerDataService.update(player, function(profile)
		profile.stats[stat] = (profile.stats[stat] or 0) + (amount or 1)
	end)
end

-- Winners may be Players or Participants -- activities insert whichever they were holding, and
-- a bot has no Player to insert. Identity comparison would silently stop matching the moment an
-- activity started recording participants, so compare by id instead.
local function isWinner(result: any, player: Player): boolean
	for _, winner in result.winners do
		if Participant.same(winner, player) then
			return true
		end
	end
	return false
end

-- Interpret a RunResult from a finished activity/event and pay everyone out (GDD §5 rewards).
-- `kind` is "Activity" or "ChaosEvent"; used for stat bookkeeping.
function RewardService.applyRunResult(kind: string, runnable: any, result: any)
	local rewards = RankConfig.rewards

	-- Everyone with a score entry participated. Bots are filtered twice over: their ids sit
	-- below the bot floor, AND Players:GetPlayerByUserId cannot resolve them. Note the deeper
	-- guarantee behind both -- every grant function here takes a Player, and a bot has no Player
	-- object, so paying one is not expressible rather than merely prevented.
	local participants: { Player } = {}
	local seen: { [Player]: boolean } = {}
	for id in result.scores do
		if not Participant.isBotId(id) then
			local player = Players:GetPlayerByUserId(id)
			if player and not seen[player] then
				seen[player] = true
				table.insert(participants, player)
			end
		end
	end

	-- Nobody human scored. Fall back to everyone present, so a round where the bots did all the
	-- work still pays the humans who sat through it. Guarded on there being no HUMAN score
	-- rather than no score at all -- otherwise a bot-only scoreboard would look like a completed
	-- run with participants and skip the payout entirely.
	if #participants == 0 then
		for _, player in Players:GetPlayers() do
			table.insert(participants, player)
		end
	end

	for _, player in participants do
		local score = result.scores[player.UserId] or 0
		local stars = score * rewards.starsPerScorePoint

		if kind == "Activity" then
			stars += rewards.participationStars
			RewardService.incrementStat(player, "activitiesPlayed", 1)
		end
		local won = isWinner(result, player)
		if won then
			stars += rewards.winBonusStars
		end

		-- Per-run flat bonuses declared by the activity (e.g. objective completed).
		local flat = result.starAwards and result.starAwards[player.UserId]
		if flat then
			stars += flat
		end

		if stars > 0 then
			RewardService.grantStars(player, stars)
		end

		-- Scrapbook memories the run flagged for all participants.
		for _, achievementId in result.scrapbook do
			RewardService.unlockScrapbook(player, achievementId)
		end

		-- Winner-only memories/stats (e.g. "Won Pillow Fight", pillowFightWins).
		if won then
			for _, achievementId in result.winnerScrapbook or {} do
				RewardService.unlockScrapbook(player, achievementId)
			end
			for stat, amount in result.winnerStats or {} do
				RewardService.incrementStat(player, stat, amount)
			end
		end
	end
end

-- Grant end-of-session rewards (GDD §3 Morning): completion stars + completion scrapbook.
function RewardService.grantSessionCompletion(player: Player, scrapbookIds: { string })
	RewardService.grantStars(player, RankConfig.rewards.completionStars)
	RewardService.incrementStat(player, "sleepoversCompleted", 1)
	for _, id in scrapbookIds do
		RewardService.unlockScrapbook(player, id)
	end
end

function RewardService.start()
	-- Push a fresh view whenever a profile loads so the HUD populates on join.
	PlayerDataService.ProfileLoaded:Connect(function(player)
		pushView(player)
	end)

	-- Client requests its profile view on join (RemoteFunction).
	Remotes.func("RequestProfile").OnServerInvoke = function(player)
		return PlayerDataService.waitFor(player, 8) and PlayerDataService.view(player) or nil
	end
end

return RewardService
