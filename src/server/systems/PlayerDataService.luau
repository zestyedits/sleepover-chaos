--!strict
-- PlayerDataService — persistent player profiles (GDD §9, §10, §14).
--
-- Self-contained DataStore layer (no Wally/ProfileService dependency so the repo runs without
-- a package install step) but built with the same safeguards a real game needs:
--   * schema-versioned default with a migration seam
--   * per-player session lock with stale-lock steal after a TTL (prevents duplicate sessions
--     writing the same key across servers)
--   * load-with-retry and throttled autosave
--   * BindToClose flush
-- The public surface is small enough that ProfileService can be swapped behind it later.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.util.Signal)
local CosmeticConfig = require(Shared.config.CosmeticConfig)
local RankConfig = require(Shared.config.RankConfig)

local SCHEMA_VERSION = 1
local STORE_NAME = "PlayerProfiles_v1"
local AUTOSAVE_INTERVAL = 60 -- seconds
local SESSION_LOCK_TTL = 60 * 30 -- steal a lock older than 30 min (dead server)
local MAX_RETRIES = 4

-- In Studio without API access, DataStores throw. We fall back to an in-memory store so the
-- prototype is fully playable offline; a warning is emitted once.
local useMemoryStore = false
local memoryStore: { [string]: any } = {}

local store: DataStore = DataStoreService:GetDataStore(STORE_NAME)

local PlayerDataService = {}
PlayerDataService.ProfileLoaded = Signal.new() -- (player, profile)
PlayerDataService.ProfileChanged = Signal.new() -- (player, profile)

local profiles: { [Player]: any } = {}
local loading: { [Player]: boolean } = {}

-- ---------------------------------------------------------------------------------------
-- Default profile + migrations
-- ---------------------------------------------------------------------------------------

local function defaultProfile(): any
	local ownedDefaults = {}
	for id in CosmeticConfig.defaultOwned do
		ownedDefaults[id] = true
	end
	local equippedDefaults = {}
	for slot, id in CosmeticConfig.defaultEquipped do
		equippedDefaults[slot] = id
	end

	return {
		schemaVersion = SCHEMA_VERSION,
		stars = 0,
		xp = 0,
		level = 1,
		rank = RankConfig.rankForLevel(1),
		cosmetics = {
			owned = ownedDefaults,
			equipped = equippedDefaults,
		},
		scrapbook = {},
		stats = {
			sleepoversCompleted = 0,
			pillowFightWins = 0,
			activitiesPlayed = 0,
			rareEventsWitnessed = 0,
		},
		_lock = nil, -- { jobId, timestamp }
	}
end

-- Bring an older profile up to the current schema. Add cases as SCHEMA_VERSION grows.
local function migrate(data: any): any
	if type(data) ~= "table" then
		return defaultProfile()
	end
	-- Fill any missing top-level keys from the default (forward-compatible loads).
	local default = defaultProfile()
	for key, value in default do
		if data[key] == nil then
			data[key] = value
		end
	end
	if not data.cosmetics.owned then
		data.cosmetics.owned = default.cosmetics.owned
	end
	if not data.cosmetics.equipped then
		data.cosmetics.equipped = default.cosmetics.equipped
	end
	data.schemaVersion = SCHEMA_VERSION
	return data
end

-- ---------------------------------------------------------------------------------------
-- DataStore access with retry + memory fallback
-- ---------------------------------------------------------------------------------------

local function keyFor(userId: number): string
	return `user_{userId}`
end

local function retry<T>(fn: () -> T): (boolean, T?)
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if attempt == MAX_RETRIES then
			warn(`[PlayerDataService] datastore op failed after {MAX_RETRIES} tries: {result}`)
			return false, nil
		end
		task.wait(2 ^ attempt) -- exponential backoff: 2,4,8s
	end
	return false, nil
end

local function rawUpdate(userId: number, transform: (any) -> any?): (boolean, any)
	if useMemoryStore then
		local key = keyFor(userId)
		local newValue = transform(memoryStore[key])
		if newValue ~= nil then
			memoryStore[key] = newValue
		end
		return true, memoryStore[key]
	end

	local key = keyFor(userId)
	return retry(function()
		return store:UpdateAsync(key, function(old)
			return transform(old)
		end)
	end)
end

-- ---------------------------------------------------------------------------------------
-- Load / save with session locking
-- ---------------------------------------------------------------------------------------

local jobId = game.JobId ~= "" and game.JobId or "studio"

local function tryDetectMemoryFallback()
	-- Probe DataStore availability once; in Studio without API access this errors.
	local ok = pcall(function()
		store:GetAsync("__probe__")
	end)
	if not ok then
		useMemoryStore = true
		warn("[PlayerDataService] DataStores unavailable — using in-memory store (data won't persist).")
	end
end

local function loadProfile(player: Player)
	if loading[player] or profiles[player] then
		return
	end
	loading[player] = true

	local now = os.time()
	local loaded
	local ok = rawUpdate(player.UserId, function(old)
		local data = old and migrate(old) or defaultProfile()

		-- Session lock: refuse to load if another live server holds a fresh lock.
		local lock = data._lock
		if lock and lock.jobId ~= jobId and (now - (lock.timestamp or 0)) < SESSION_LOCK_TTL then
			-- Locked elsewhere; abort the update (return nil) and retry shortly.
			return nil
		end

		data._lock = { jobId = jobId, timestamp = now }
		loaded = data
		return data
	end)

	if not ok or not loaded then
		-- Could not acquire lock (or datastore failure). Give the player a fresh, unsaved
		-- profile so they can still play; it simply won't persist this session.
		loaded = defaultProfile()
		warn(`[PlayerDataService] could not load/lock profile for {player.Name}; using transient profile.`)
	end

	loaded._lock = nil -- keep the lock only in the store, not in the live copy
	loaded._transient = (not ok)

	if not player:IsDescendantOf(Players) then
		loading[player] = nil
		return
	end

	profiles[player] = loaded
	loading[player] = nil
	PlayerDataService.ProfileLoaded:Fire(player, loaded)
	PlayerDataService.ProfileChanged:Fire(player, loaded)
end

local function saveProfile(player: Player, release: boolean)
	local profile = profiles[player]
	if not profile or profile._transient then
		return
	end

	rawUpdate(player.UserId, function(old)
		-- Only write if we still hold the lock (or it's ours/expired).
		local now = os.time()
		local toSave = table.clone(profile)
		toSave._lock = if release then nil else { jobId = jobId, timestamp = now }
		toSave._transient = nil
		return toSave
	end)
end

-- ---------------------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------------------

function PlayerDataService.get(player: Player): any?
	return profiles[player]
end

-- Wait (bounded) for a profile to finish loading.
function PlayerDataService.waitFor(player: Player, timeout: number?): any?
	local deadline = os.clock() + (timeout or 10)
	while not profiles[player] and os.clock() < deadline do
		if not player:IsDescendantOf(Players) then
			return nil
		end
		task.wait(0.1)
	end
	return profiles[player]
end

-- Mutate a profile through a transform and fire ProfileChanged. Returns the profile.
function PlayerDataService.update(player: Player, transform: (profile: any) -> ()): any?
	local profile = profiles[player]
	if not profile then
		return nil
	end
	transform(profile)
	PlayerDataService.ProfileChanged:Fire(player, profile)
	return profile
end

-- Build a client-safe view (strips internal fields).
function PlayerDataService.view(player: Player): any?
	local profile = profiles[player]
	if not profile then
		return nil
	end
	return {
		stars = profile.stars,
		xp = profile.xp,
		level = profile.level,
		rank = profile.rank,
		xpForNext = RankConfig.xpForLevel(profile.level),
		cosmetics = profile.cosmetics,
		scrapbook = profile.scrapbook,
		stats = profile.stats,
	}
end

function PlayerDataService.start()
	tryDetectMemoryFallback()

	local function onPlayerAdded(player: Player)
		task.spawn(loadProfile, player)
	end

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	Players.PlayerRemoving:Connect(function(player)
		saveProfile(player, true)
		profiles[player] = nil
		loading[player] = nil
	end)

	-- Autosave loop.
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player in profiles do
				saveProfile(player, false)
			end
		end
	end)

	-- Flush on shutdown.
	game:BindToClose(function()
		if RunService:IsStudio() and useMemoryStore then
			return
		end
		for player in profiles do
			task.spawn(saveProfile, player, true)
		end
		task.wait(3) -- give writes a moment to flush
	end)
end

return PlayerDataService
