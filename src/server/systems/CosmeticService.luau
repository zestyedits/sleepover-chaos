--!strict
-- CosmeticService — server-authoritative cosmetic ownership + equipping (GDD §11, §12).
-- Clients REQUEST equips/unlocks; the server validates against CosmeticConfig and the
-- player's stars. Cosmetics never affect gameplay power (GDD §12) — they only tint the
-- avatar greybox accessory and set nameplate/theme attributes for now.
--
-- Monetization is scaffolded: ProcessReceipt maps developer-product ids to unlocks, and a
-- Host Pass check is stubbed. All Robux ids in CosmeticConfig are PLACEHOLDER 0 — wire real
-- Creator-Dashboard ids before enabling purchases.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CosmeticConfig = require(Shared.config.CosmeticConfig)
local Remotes = require(Shared.net.Remotes)

local PlayerDataService = require(script.Parent.PlayerDataService)
local RewardService = require(script.Parent.RewardService)

local CosmeticService = {}

-- Product id -> cosmetic id, built from the catalog for ProcessReceipt.
local productToCosmetic: { [number]: string } = {}
for _, item in CosmeticConfig.catalog do
	if item.robuxProductId and item.robuxProductId ~= 0 then
		productToCosmetic[item.robuxProductId] = item.id
	end
end

local function pushView(player: Player)
	local view = PlayerDataService.view(player)
	if view then
		Remotes.event("DataUpdated"):FireClient(player, view)
	end
end

-- Apply a simple visual: tint a carried "plushie" part / accessory colors on the character.
-- Kept intentionally lightweight; real accessory meshes replace this later (GDD §16).
local function applyToCharacter(player: Player)
	local profile = PlayerDataService.get(player)
	local character = player.Character
	if not profile or not character then
		return
	end

	-- Nameplate / theme are exposed as attributes the client reads.
	player:SetAttribute("Theme", profile.cosmetics.equipped.Theme)
	player:SetAttribute("Nameplate", profile.cosmetics.equipped.Nameplate)

	-- Pajama tint -> shirt-ish color on the torso greybox.
	local pjId = profile.cosmetics.equipped.Pajamas
	local pj = pjId and CosmeticConfig.get(pjId)
	if pj and pj.color then
		local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
		if torso and torso:IsA("BasePart") then
			torso.Color = Color3.new(pj.color[1], pj.color[2], pj.color[3])
		end
	end
end
CosmeticService.applyToCharacter = applyToCharacter

-- Unlock a cosmetic with stars. Returns true/false + reason.
function CosmeticService.purchaseWithStars(player: Player, cosmeticId: string): (boolean, string)
	local def = CosmeticConfig.get(cosmeticId)
	if not def then
		return false, "unknown"
	end
	local profile = PlayerDataService.get(player)
	if not profile then
		return false, "no_profile"
	end
	if profile.cosmetics.owned[cosmeticId] then
		return false, "owned"
	end
	if not def.starCost then
		return false, "not_for_stars"
	end
	if profile.stars < def.starCost then
		return false, "insufficient_stars"
	end

	PlayerDataService.update(player, function(p)
		p.stars -= def.starCost
		p.cosmetics.owned[cosmeticId] = true
	end)
	pushView(player)
	return true, "ok"
end

-- Equip an owned cosmetic into its slot. Validated server-side.
function CosmeticService.equip(player: Player, slot: string, cosmeticId: string): (boolean, string)
	local def = CosmeticConfig.get(cosmeticId)
	if not def or def.slot ~= slot then
		return false, "invalid"
	end
	local profile = PlayerDataService.get(player)
	if not profile then
		return false, "no_profile"
	end
	if not profile.cosmetics.owned[cosmeticId] then
		return false, "not_owned"
	end

	PlayerDataService.update(player, function(p)
		p.cosmetics.equipped[slot] = cosmeticId
	end)
	applyToCharacter(player)
	pushView(player)
	return true, "ok"
end

function CosmeticService.ownsHostPass(player: Player): boolean
	if CosmeticConfig.hostPassId == 0 then
		return false -- not configured yet
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, CosmeticConfig.hostPassId)
	end)
	return ok and owns == true
end

local function onProcessReceipt(info): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local cosmeticId = productToCosmetic[info.ProductId]
	if not cosmeticId then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = PlayerDataService.get(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	PlayerDataService.update(player, function(p)
		p.cosmetics.owned[cosmeticId] = true
	end)
	pushView(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function CosmeticService.start()
	-- Client equip requests.
	Remotes.event("RequestEquip").OnServerEvent:Connect(function(player, slot, cosmeticId)
		if typeof(slot) ~= "string" or typeof(cosmeticId) ~= "string" then
			return
		end
		-- If not owned but star-purchasable, treat equip as buy-then-equip for convenience.
		local profile = PlayerDataService.get(player)
		if profile and not profile.cosmetics.owned[cosmeticId] then
			CosmeticService.purchaseWithStars(player, cosmeticId)
		end
		CosmeticService.equip(player, slot, cosmeticId)
	end)

	-- Apply cosmetics whenever a character spawns.
	local function hookCharacter(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait(0.5) -- let the rig assemble
			applyToCharacter(player)
		end)
		if player.Character then
			applyToCharacter(player)
		end
	end
	for _, player in Players:GetPlayers() do
		hookCharacter(player)
	end
	Players.PlayerAdded:Connect(hookCharacter)

	MarketplaceService.ProcessReceipt = onProcessReceipt

	-- Studio-only dev grant for testing the economy.
	if RunService:IsStudio() then
		Remotes.event("DevGrantStars").OnServerEvent:Connect(function(player, amount)
			if typeof(amount) == "number" then
				RewardService.grantStars(player, math.clamp(amount, 0, 100000))
			end
		end)
	end
end

return CosmeticService
