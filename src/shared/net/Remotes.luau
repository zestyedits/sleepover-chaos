--!strict
-- Remotes — the single source of truth for every RemoteEvent / RemoteFunction.
--
-- On the server this module creates the instances under a "SleepoverRemotes" folder in
-- ReplicatedStorage. On the client it waits for them. Both sides `require` this module and
-- read remotes by name, so there is exactly one authoritative list and no stringly-typed
-- FindFirstChild scattered around the codebase.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "SleepoverRemotes"

-- name -> "Event" | "Function"
local DEFINITIONS: { [string]: string } = {
	-- Server -> Client (broadcast/state)
	PhaseChanged = "Event", -- (phase: string, timeLeft: number, info: table)
	ActivityStarted = "Event", -- (displayName: string, objective: string, duration: number)
	ActivityEnded = "Event", -- (displayName: string, resultSummary: table)
	ChaosEvent = "Event", -- (displayName: string, description: string)
	Announce = "Event", -- (message: string, style: string)
	DataUpdated = "Event", -- (profileView: table) whole client-safe profile snapshot
	ScrapbookUnlocked = "Event", -- (achievementId: string, achievementInfo: table)
	GhostStoryPrompt = "Event", -- (storyNodeId: string, text: string, choices: {string})

	-- Client -> Server (input; always validated server-side)
	RequestEquip = "Event", -- (slot: string, cosmeticId: string)
	GhostStoryChoice = "Event", -- (choiceIndex: number)
	RequestProfile = "Function", -- () -> profileView

	-- Client -> Server debug/dev only (guarded in CosmeticService)
	DevGrantStars = "Event", -- (amount: number) -- Studio only
}

local Remotes = {}
local cache: { [string]: Instance } = {}

local function ensureFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if folder then
		return folder :: Folder
	end
	assert(RunService:IsServer(), "Remotes folder must be created by the server first")
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

local function build()
	local folder = ensureFolder()
	for name, kind in DEFINITIONS do
		local existing = folder:FindFirstChild(name)
		if existing then
			cache[name] = existing
			continue
		end
		if RunService:IsServer() then
			local instance =
				Instance.new(if kind == "Function" then "RemoteFunction" else "RemoteEvent")
			instance.Name = name
			instance.Parent = folder
			cache[name] = instance
		else
			local instance = folder:WaitForChild(name, 30)
			if instance then
				cache[name] = instance
			end
		end
	end
end

-- Call once on each side during bootstrap.
function Remotes.init()
	build()
end

function Remotes.event(name: string): RemoteEvent
	local remote = cache[name]
	if not remote then
		build()
		remote = cache[name]
	end
	assert(remote and remote:IsA("RemoteEvent"), "Unknown RemoteEvent: " .. tostring(name))
	return remote :: RemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	local remote = cache[name]
	if not remote then
		build()
		remote = cache[name]
	end
	assert(remote and remote:IsA("RemoteFunction"), "Unknown RemoteFunction: " .. tostring(name))
	return remote :: RemoteFunction
end

return Remotes
