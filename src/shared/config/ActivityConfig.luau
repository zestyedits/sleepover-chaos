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
				pointsPerHit = 2,
				pointsPerNpcHit = 1, -- NPC guests are hittable, just worth less than a real player
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
			-- Noise budget: 4 grabs alone reach 88 of 100, so grabbing cannot bust you on its
			-- own — sprinting is what tips it over. A player at full speed (16) adds
			-- (16 - 7) * 0.35 = ~3.1/s, so two people running outpace the 5/s decay while
			-- standing still always recovers. The old numbers capped out at 72 against a
			-- threshold of 100, which made the fail state literally unreachable.
			settings = {
				pointsPerSnack = 2,
				noiseFailThreshold = 100,
				noisePerGrab = 22,
				noiseDecayPerSecond = 5,
				quietSpeed = 7, -- studs/s you can move without making a sound
				noisePerSpeedUnit = 0.35, -- noise per stud/s over quietSpeed, per second
			},
		},
		{
			id = "HideAndSeek",
			displayName = "Hide & Seek",
			module = "HideAndSeek",
			weight = 2,
			duration = 75,
			objective = "Claim a hiding spot and stay put — the seeker is coming.",
			settings = {
				seekerHeadStart = 12,
				hideRadius = 10, -- drift further than this from your spot and you are exposed
				searchRange = 9, -- seeker's "Search!" reach against a hiding spot
				tagRange = 7, -- ...and against someone caught in the open
				pointsForSurviving = 3,
				pointsPerCatch = 2,
				pointsForFindingSpot = 1, -- solo scavenger-hunt mode
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
