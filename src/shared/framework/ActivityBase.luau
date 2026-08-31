--!strict
-- ActivityBase — ergonomic base "class" for the 5 minigames (GDD §6, §14).
-- An activity module returns `ActivityBase.extend("PillowFight", { onStart = ..., ... })`.
-- The result is a factory: ActivityManager calls `factory.create(def)` to make a Runnable
-- that Lifecycle drives. This keeps each activity to roughly one screen of code because the
-- lifecycle, context, scoring, and cleanup all live in the framework (GDD §5).

local ActivityBase = {}

export type ActivityHooks = {
	onStart: ((ctx: any) -> ())?,
	onUpdate: ((dt: number, ctx: any) -> ())?,
	checkWin: ((ctx: any) -> boolean)?,
	onFinish: ((ctx: any) -> ())?,
	onCleanup: ((ctx: any) -> ())?,
}

export type ActivityFactory = {
	kind: string,
	id: string,
	hooks: ActivityHooks,
	-- Build a Lifecycle.Runnable from a config def (ActivityConfig.ActivityDef).
	create: (def: any) -> any,
}

-- `id` is a stable identifier; `hooks` provides the lifecycle overrides.
function ActivityBase.extend(id: string, hooks: ActivityHooks): ActivityFactory
	local factory = {
		kind = "Activity",
		id = id,
		hooks = hooks,
	}

	function factory.create(def: any): any
		return {
			id = def.id or id,
			displayName = def.displayName or id,
			duration = def.duration or 60,
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

return ActivityBase
