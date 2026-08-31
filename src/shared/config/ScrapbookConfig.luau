--!strict
-- ScrapbookConfig — the collectable memories (GDD §10).
-- Achievements are unlock-once. Rare-event memories carry a `sticker` reward and bonus stars.
-- RewardService checks these; the client Scrapbook UI renders them from this same table.

export type AchievementDef = {
	id: string,
	title: string,
	description: string,
	rare: boolean?,
	starReward: number?,
	sticker: string?, -- cosmetic sticker id granted on unlock (rare events, GDD §10)
}

local ScrapbookConfig = {
	achievements = {
		{
			id = "survived_first_sleepover",
			title = "Survived First Sleepover",
			description = "You made it through a whole night.",
			starReward = 20,
		},
		{
			id = "stayed_awake_until_morning",
			title = "Stayed Awake Until Morning",
			description = "Reached the Morning phase without rage-quitting.",
			starReward = 10,
		},
		{
			id = "won_pillow_fight",
			title = "Won Pillow Fight",
			description = "Most pillow hits. Undisputed champion.",
			starReward = 15,
		},
		{
			id = "survived_blackout",
			title = "Survived Blackout",
			description = "Kept your cool when the lights died.",
			rare = true,
			starReward = 15,
			sticker = "sticker_flashlight",
		},
		{
			id = "found_secret_attic",
			title = "Found the Secret Attic",
			description = "Followed the strange noise upstairs.",
			rare = true,
			starReward = 20,
			sticker = "sticker_ghost",
		},
		{
			id = "perfect_parent_check",
			title = "Perfect Parent Check",
			description = "Everything hidden, everyone in bed, not a sound.",
			rare = true,
			starReward = 20,
			sticker = "sticker_shh",
		},
		{
			id = "wrong_pizza",
			title = "Rare Event Witnessed: Wrong Pizza",
			description = "Anchovy and pineapple. Someone is responsible.",
			rare = true,
			starReward = 10,
			sticker = "sticker_pizza",
		},
		{
			id = "midnight_feast",
			title = "Midnight Feast",
			description = "Raided the kitchen and got away clean.",
			starReward = 10,
		},
	} :: { AchievementDef },
}

-- id -> def lookup, built once.
local byId: { [string]: AchievementDef } = {}
for _, achievement in ScrapbookConfig.achievements do
	byId[achievement.id] = achievement
end
ScrapbookConfig.byId = byId

function ScrapbookConfig.get(id: string): AchievementDef?
	return byId[id]
end

return ScrapbookConfig
