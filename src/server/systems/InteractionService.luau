--!strict
-- InteractionService — central ProximityPrompt registry (GDD §14).
-- Tagged greybox parts (snacks, hiding spots, doors, contraband) get a ProximityPrompt.
-- When triggered, the request is routed to whichever run (activity/event) has registered a
-- handler for that role. Because the physical props are shared, the same kitchen/bedroom
-- serves whichever activity is currently live — this is what keeps everything inside the one
-- house (GDD §17) instead of spawning bespoke minigame maps.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Participant = require(Shared.Participant)
local Tags = require(Shared.Tags)

type Participant = Participant.Participant

local InteractionService = {}

-- role -> handler(actor, promptPart). Only one active handler per role; an activity registers on
-- start and unregisters on cleanup.
--
-- The actor is a PARTICIPANT, not a Player. That single widening is what makes bots able to play:
-- a bot cannot fire a RemoteEvent and cannot trigger a ProximityPrompt, but it can be routed
-- through the very same handler a real prompt would call. Grabbing a snack, hiding, and stashing
-- contraband all become bot-capable without the activities knowing anything about bots.
local handlers: { [string]: (actor: Participant, part: BasePart) -> () } = {}
local prompts: { [BasePart]: ProximityPrompt } = {}

-- Mirrors ProximityPrompt.MaxActivationDistance below, so a simulated interaction is held to the
-- same reach a human gets. Without it a bot could raid the kitchen from upstairs.
local SIMULATED_REACH = 10

local function ensurePrompt(part: BasePart)
	if prompts[part] then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = part:GetAttribute("ActionText") or "Interact"
	prompt.ObjectText = part:GetAttribute("Label") or part.Name
	prompt.HoldDuration = part:GetAttribute("HoldDuration") or 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.Parent = part
	prompts[part] = prompt

	-- Enable immediately if a handler for this role is already registered. This matters
	-- because the tag-added signal that creates prompts can fire AFTER an activity has
	-- already called register() (e.g. ParentCheck spawns contraband then registers).
	local role = part:GetAttribute("Role")
	prompt.Enabled = role ~= nil and handlers[role] ~= nil

	prompt.Triggered:Connect(function(player: Player)
		local role = part:GetAttribute("Role")
		local handler = role and handlers[role]
		if handler then
			handler(Participant.fromPlayer(player), part)
		end
	end)

	-- The map is keyed by the part, so without this every house rebuild pins the entire previous
	-- set of props in memory and refreshPromptStates walks them forever.
	part.Destroying:Connect(function()
		prompts[part] = nil
	end)
end

-- Update prompt enabled-state to match currently-registered roles.
local function refreshPromptStates()
	for part, prompt in prompts do
		local role = part:GetAttribute("Role")
		prompt.Enabled = role ~= nil and handlers[role] ~= nil
	end
end

-- Register a handler for a role (called by an activity in onStart, via its trove for cleanup).
function InteractionService.register(
	role: string,
	handler: (actor: Participant, part: BasePart) -> ()
): () -> ()
	handlers[role] = handler
	refreshPromptStates()
	-- Return an unregister function the caller can add to its trove.
	return function()
		if handlers[role] == handler then
			handlers[role] = nil
			refreshPromptStates()
		end
	end
end

-- Enable/disable a prompt's action text dynamically (e.g. change "Grab" once grabbed).
function InteractionService.setActionText(part: BasePart, text: string)
	local prompt = prompts[part]
	if prompt then
		prompt.ActionText = text
	end
end

function InteractionService.getPrompt(part: BasePart): ProximityPrompt?
	return prompts[part]
end

-- Drive an interaction on behalf of a participant that cannot press a button -- i.e. a bot.
--
-- Held to the same rules a human gets: the role must have a live handler, the prompt must exist
-- and be enabled, and the actor must be within reach. Returns whether it actually fired, so a bot
-- driver can tell "too far away, keep walking" from "done".
function InteractionService.simulate(role: string, actor: Participant, part: BasePart): boolean
	local handler = handlers[role]
	if not handler then
		return false
	end
	if part:GetAttribute("Role") ~= role then
		return false
	end
	local prompt = prompts[part]
	if prompt and not prompt.Enabled then
		return false
	end
	local root = Participant.rootPart(actor)
	if not root or (root.Position - part.Position).Magnitude > SIMULATED_REACH then
		return false
	end
	handler(actor, part)
	return true
end

function InteractionService.start()
	local function onTagged(part: Instance)
		if part:IsA("BasePart") then
			ensurePrompt(part)
		end
	end
	for _, part in CollectionService:GetTagged(Tags.Interactable) do
		onTagged(part)
	end
	CollectionService:GetInstanceAddedSignal(Tags.Interactable):Connect(onTagged)
end

return InteractionService
