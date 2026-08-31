--!strict
-- GameConfig — session pacing and party sizing (GDD §3, §13).
-- All durations in seconds. Tweak these to retune the round without touching systems.

local GameConfig = {
	-- Ordered phases of one sleepover session (GDD §3). GameRoundManager walks this list.
	phases = {
		{ name = "Arrive", duration = 20 }, -- choose spot / socialize
		{ name = "Activity", duration = 90 }, -- short minigame
		{ name = "FreeTime", duration = 30 }, -- explore / decorate / interact
		{ name = "RandomEvent", duration = 35 }, -- something unexpected
		{ name = "Activity", duration = 90 }, -- another minigame
		{ name = "LateNightChaos", duration = 45 }, -- increasingly weird
		{ name = "Morning", duration = 20 }, -- rewards + scrapbook
	},

	-- Party sizing (GDD §13). NPCManager fills up to `targetPartySize` with guests.
	minPlayers = 1,
	maxPlayers = 10,
	targetPartySize = 4, -- solo player still gets a lively-feeling sleepover

	-- Countdown shown before an activity/event actually begins (GDD §5 "countdown").
	activityCountdown = 5,
	eventCountdown = 3,

	-- End-of-session scrapbook memories granted to everyone who reached Morning.
	completionScrapbook = { "survived_first_sleepover", "stayed_awake_until_morning" },
}

return GameConfig
