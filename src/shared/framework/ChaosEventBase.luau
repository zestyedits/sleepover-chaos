--!strict
-- ChaosEventBase — base "class" for chaos events (GDD §7). Same lifecycle as activities but
-- events are typically "small system changes": most only implement onStart (apply a world
-- change, play a sound, spawn a prop) and onCleanup (revert). Runs through the same Lifecycle.

local ChaosEventBase = {}

export type EventHooks = {
	onStart: ((ctx: any) -> ())?,
	onUpdate: ((dt: number, ctx: any) -> ())?,
	checkWin: ((ctx: any) -> boolean)?,
	onFinish: ((ctx: any) -> ())?,
	onCleanup: ((ctx: any) -> ())?,
}

export type EventFactory = {
	kind: string,
	id: string,
	hooks: EventHooks,
	create: (def: any) -> any,
}

function ChaosEventBase.extend(id: string, hooks: EventHooks): EventFactory
	local factory = {
		kind = "ChaosEvent",
		id = id,
		hooks = hooks,
	}

	function factory.create(def: any): any
		return {
			id = def.id or id,
			displayName = def.displayName or id,
			duration = def.duration or 20,
			countdown = def.countdown,
			config = def.settings or {},
			onStart = hooks.onStart,
			onUpdate = hooks.onUpdate,
			checkWin = hooks.checkWin,
			onFinish = hooks.onFinish,
			onCleanup = hooks.onCleanup,
		}
	end

	return factory
end

return ChaosEventBase
