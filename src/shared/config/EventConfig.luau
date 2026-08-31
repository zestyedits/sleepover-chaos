--!strict
-- EventConfig — the chaos-event pool for EventManager (GDD §7).
-- Chaos events are "small system changes, not entire new games": short, config-light.

export type EventDef = {
	id: string,
	displayName: string,
	module: string,
	weight: number,
	duration: number,
	description: string, -- toast shown when it fires
	rare: boolean?, -- rare events award unique scrapbook memories (GDD §10)
	settings: { [string]: any },
}

local EventConfig = {
	events = {
		{
			id = "PowerOutage",
			displayName = "Power Outage",
			module = "PowerOutage",
			weight = 3,
			duration = 25,
			description = "The lights just went out. Who touched the breaker?!",
			settings = { scrapbook = "survived_blackout" },
		},
		{
			id = "StrangeNoise",
			displayName = "Strange Noise Upstairs",
			module = "StrangeNoise",
			weight = 3,
			duration = 25,
			description = "...did you hear that? Something's in the attic.",
			settings = { scrapbook = "found_secret_attic", opensAttic = true },
		},
		{
			id = "PizzaDisaster",
			displayName = "Pizza Delivery Disaster",
			module = "PizzaDisaster",
			weight = 2,
			duration = 25,
			description = "Pizza's here! ...this is the completely wrong order.",
			settings = { scrapbook = "wrong_pizza" },
		},
	} :: { EventDef },
}

return EventConfig
