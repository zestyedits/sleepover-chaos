--!strict
-- RankConfig — level curve, rank names, and star/xp reward amounts (GDD §9).
-- RewardService is the only consumer; nothing else computes progression.

local RankConfig = {
	-- XP required to reach each level. level 1 needs 0; level N needs xpForLevel(N).
	-- A gentle quadratic curve: base * (level-1) + step * (level-1)^2.
	base = 100,
	step = 25,

	-- Rank thresholds by level (GDD §9). rank applies at the highest level <= player level.
	ranks = {
		{ level = 1, name = "Guest" },
		{ level = 5, name = "Regular" },
		{ level = 12, name = "Bestie" },
		{ level = 25, name = "Sleepover Pro" },
		{ level = 40, name = "Party Legend" },
	},

	-- Reward amounts. Activities/events return results; RewardService turns them into these.
	rewards = {
		starsPerScorePoint = 1, -- each score point in a run = this many stars
		participationStars = 5, -- flat stars for taking part in an activity
		winBonusStars = 15, -- extra stars for winning an activity
		completionStars = 25, -- finishing a whole sleepover (GDD §3 Morning)
		xpPerStar = 1, -- xp gained equals stars gained (simple 1:1 for the prototype)
	},

	maxLevel = 60,
}

-- XP needed to advance FROM `level` to `level + 1`.
function RankConfig.xpForLevel(level: number): number
	local n = level - 1
	return RankConfig.base * n + RankConfig.step * n * n
end

-- Rank name for a given level.
function RankConfig.rankForLevel(level: number): string
	local name = RankConfig.ranks[1].name
	for _, rank in RankConfig.ranks do
		if level >= rank.level then
			name = rank.name
		else
			break
		end
	end
	return name
end

return RankConfig
