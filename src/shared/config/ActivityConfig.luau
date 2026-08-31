--!strict
-- ActivityConfig — the pool ActivityManager draws from, plus per-activity tunables (GDD §6).
-- `module` is the child name under src/server/activities. `weight` biases random selection.

export type ActivityDef = {
	id: string,
	displayName: string,
	module: string,
	weight: number,
	duration: number, -- max run length before the timer ends it (seconds)
	objective: string, -- shown in the HUD when the activity starts
	settings: { [string]: any },
}

local ActivityConfig = {
	activities = {
		{
			id = "PillowFight",
			displayName = "Pillow Fight",
			module = "PillowFight",
			weight = 3,
			duration = 60,
			objective = "Whack everyone with pillows! Most hits wins.",
			settings = {
				pointsPerHit = 1,
				megaChance = 0.15, -- rare MEGA PILLOW FIGHT variant (GDD §6)
				megaPointMultiplier = 2,
			},
		},
		{
			id = "ParentCheck",
			displayName = "Parent Check",
			module = "ParentCheck",
			weight = 3,
			duration = 30,
			objective = "MOM IS COMING — hide the contraband and get in bed!",
			settings = {
				hideWindow = 30,
				pointsPerHiddenItem = 2,
				pointsForInBed = 3,
			},
		},
		{
			id = "MidnightSnack",
			displayName = "Midnight Snack Raid",
			module = "MidnightSnack",
			weight = 2,
			duration = 60,
			objective = "Sneak the requested snacks back without waking the house.",
			settings = {
				pointsPerSnack = 2,
				noiseFailThreshold = 100,
				noisePerGrab = 18,
				noiseDecayPerSecond = 6,
			},
		},
		{
			id = "HideAndSeek",
			displayName = "Hide & Seek",
			module = "HideAndSeek",
			weight = 2,
			duration = 75,
			objective = "Hide from the seeker. Last one hidden wins!",
			settings = {
				seekerHeadStart = 8,
				pointsForSurviving = 3,
				pointsPerCatch = 2,
			},
		},
		{
			id = "GhostStory",
			displayName = "Ghost Story",
			module = "GhostStory",
			weight = 2,
			duration = 70,
			objective = "Gather round and decide what happens next...",
			settings = {
				chanceToTriggerEvent = 0.4, -- some branches trigger a real event (GDD §6)
				pointsForParticipating = 1,
			},
		},
	} :: { ActivityDef },
}

return ActivityConfig
