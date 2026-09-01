--!strict
-- Types — shared Luau type definitions used across server and client.
-- Keeping these in one place means the profile schema and run contracts have a single
-- authoritative shape.

export type CosmeticSlot =
	"Pajamas"
	| "SleepingBag"
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
	winners: { any }, -- Participants to spotlight / award win-based scrapbook memories
	-- Participant id -> score. Humans key by Player.UserId (always positive); bots key by a
	-- negative synthetic id, which is why RewardService's GetPlayerByUserId lookup skips them.
	scores: { [number]: number },
	names: { [number]: string }, -- participant id -> display name, for results without lookups
	starAwards: { [number]: number }, -- participant id -> flat star bonus (optional per-run)
	scrapbook: { string }, -- achievement ids every participant should be checked against
	winnerScrapbook: { string }?, -- achievement ids granted only to winners
	winnerStats: { [string]: number }?, -- stat increments applied only to winners
	tags: { [string]: any }, -- freeform extra info (e.g. { mega = true })
}

-- Passed to every activity/event lifecycle hook. The single object an activity touches.
export type RunContext = {
	id: string,
	displayName: string,
	players: { Player }, -- HUMANS ONLY -- see the note in Lifecycle.makeContext
	participants: { any }, -- humans + bots; what "everyone competing" means
	house: Instance,
	trove: any, -- Trove for this run; cleaned automatically on finish
	result: RunResult,
	config: { [string]: any },
	-- Helpers injected by the framework:
	addScore: (subject: any, amount: number) -> (), -- accepts a Player or a Participant
	bots: () -> { any }, -- the bot participants currently in this run
	announce: (message: string, style: string?) -> (),
	finish: () -> (), -- request an early, successful end (win condition met)
	abort: () -> (), -- request an early, unsuccessful end
	broadcastState: (state: { [string]: any }) -> (), -- push live HUD state (meters, counters)
	-- Roster churn. `players` above is kept live by the framework, but an activity that handed
	-- out per-player state on start (a tool, a score entry) needs to know about late arrivals.
	onPlayerJoined: (callback: (Player) -> ()) -> (),
	onPlayerLeft: (callback: (Player) -> ()) -> (),
}

export type PhaseName =
	"Arrive"
	| "Activity"
	| "FreeTime"
	| "RandomEvent"
	| "LateNightChaos"
	| "Morning"

return {}
