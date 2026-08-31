--!strict
-- Types — shared Luau type definitions used across server and client.
-- Keeping these in one place means the profile schema and run contracts have a single
-- authoritative shape.

export type CosmeticSlot =
	"Pajamas"
	| "Slippers"
	| "Plushie"
	| "PhoneSkin"
	| "Emote"
	| "Nameplate"
	| "Theme"

-- Persistent per-player profile. Saved by PlayerDataService. Bump `schemaVersion` and add a
-- migration in PlayerDataService when this shape changes.
export type Profile = {
	schemaVersion: number,
	stars: number, -- Sleepover Stars, the soft currency (GDD §9)
	xp: number,
	level: number,
	rank: string, -- Guest → Regular → Bestie → Sleepover Pro → Party Legend (GDD §9)
	cosmetics: {
		owned: { [string]: boolean },
		equipped: { [string]: string? }, -- slot -> cosmetic id
	},
	scrapbook: { [string]: number }, -- achievementId -> unlock timestamp (os.time) (GDD §10)
	stats: {
		sleepoversCompleted: number,
		pillowFightWins: number,
		activitiesPlayed: number,
		rareEventsWitnessed: number,
		[string]: number,
	},
}

-- Results returned by an activity/event when it finishes. Interpreted by RewardService;
-- activities never grant rewards directly.
export type RunResult = {
	completed: boolean, -- true = ran to a natural conclusion, false = aborted
	winners: { Player }, -- players to spotlight / award win-based scrapbook memories
	scores: { [number]: number }, -- Player.UserId -> score this run
	starAwards: { [number]: number }, -- Player.UserId -> flat star bonus (optional per-run)
	scrapbook: { string }, -- achievement ids every participant should be checked against
	winnerScrapbook: { string }?, -- achievement ids granted only to winners
	winnerStats: { [string]: number }?, -- stat increments applied only to winners
	tags: { [string]: any }, -- freeform extra info (e.g. { mega = true })
}

-- Passed to every activity/event lifecycle hook. The single object an activity touches.
export type RunContext = {
	id: string,
	displayName: string,
	players: { Player },
	house: Instance,
	trove: any, -- Trove for this run; cleaned automatically on finish
	result: RunResult,
	config: { [string]: any },
	-- Helpers injected by the framework:
	addScore: (player: Player, amount: number) -> (),
	announce: (message: string, style: string?) -> (),
	finish: () -> (), -- request an early, successful end (win condition met)
	abort: () -> (), -- request an early, unsuccessful end
}

export type PhaseName =
	"Arrive"
	| "Activity"
	| "FreeTime"
	| "RandomEvent"
	| "LateNightChaos"
	| "Morning"

return {}
