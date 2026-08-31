--!strict
-- Server bootstrap — wires the systems together in dependency order and kicks off the round
-- loop (GDD §14 development order / §15 phase 1 foundation). Nothing here implements game
-- mechanics; it only starts the services that do.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.net.Remotes)

local systems = script:WaitForChild("systems")
local world = script:WaitForChild("world")

local PlayerDataService = require(systems.PlayerDataService)
local RewardService = require(systems.RewardService)
local CosmeticService = require(systems.CosmeticService)
local InteractionService = require(systems.InteractionService)
local NPCManager = require(systems.NPCManager)
local ActivityManager = require(systems.ActivityManager)
local EventManager = require(systems.EventManager)
local GameRoundManager = require(systems.GameRoundManager)
local HouseLoader = require(world.HouseLoader)

-- 1. Networking (server creates the remote instances first).
Remotes.init()

-- 2. Data + economy.
PlayerDataService.start()
RewardService.start()
CosmeticService.start()

-- 3. World: load the configured house (procedural, or a model from assets/houses), then wire
-- interactions on its tagged props.
HouseLoader.ensureToolboxFolder() -- somewhere obvious to drop Toolbox models
HouseLoader.load()
InteractionService.start()

-- 4. Population + content managers.
NPCManager.start()
ActivityManager.start()
EventManager.start()

-- 5. Session loop (GDD §3).
GameRoundManager.start()

print("[SleepoverChaos] server started — welcome to the sleepover.")
