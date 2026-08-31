--!strict
-- CosmeticConfig — the cosmetic catalog (GDD §11). COSMETIC ONLY — nothing here touches
-- gameplay power (GDD §12). Items are unlocked with Sleepover Stars, or (scaffold) bought
-- with Robux via developer products / game passes.
--
-- `robuxProductId` / `gamePassId` are PLACEHOLDERS (0 = not for sale yet). Replace with real
-- asset ids from the Creator Dashboard before shipping monetization.

export type CosmeticDef = {
	id: string,
	displayName: string,
	slot: string, -- matches Types.CosmeticSlot
	starCost: number?, -- unlockable with stars (nil = not star-purchasable)
	robuxProductId: number?, -- developer product id (placeholder 0)
	color: { number }?, -- greybox tint used until real assets exist
	default: boolean?, -- granted free to every new profile
}

local CosmeticConfig = {
	catalog = {
		-- Pajamas
		{
			id = "pj_classic",
			displayName = "Classic PJs",
			slot = "Pajamas",
			default = true,
			color = { 0.6, 0.7, 0.9 },
		},
		{
			id = "pj_star",
			displayName = "Starry Night PJs",
			slot = "Pajamas",
			starCost = 120,
			color = { 0.2, 0.2, 0.5 },
		},
		{
			id = "pj_glam",
			displayName = "Glam Robe",
			slot = "Pajamas",
			robuxProductId = 0,
			color = { 0.9, 0.3, 0.6 },
		},

		-- Slippers
		{
			id = "slip_bunny",
			displayName = "Bunny Slippers",
			slot = "Slippers",
			default = true,
			color = { 0.95, 0.9, 0.9 },
		},
		{
			id = "slip_dino",
			displayName = "Dino Slippers",
			slot = "Slippers",
			starCost = 80,
			color = { 0.4, 0.8, 0.4 },
		},

		-- Plushies (carried)
		{
			id = "plush_bear",
			displayName = "Teddy Bear",
			slot = "Plushie",
			default = true,
			color = { 0.7, 0.5, 0.3 },
		},
		{
			id = "plush_cat",
			displayName = "Sleepy Cat",
			slot = "Plushie",
			starCost = 100,
			color = { 0.8, 0.8, 0.85 },
		},

		-- Phone skins
		{
			id = "phone_default",
			displayName = "Plain Case",
			slot = "PhoneSkin",
			default = true,
			color = { 0.2, 0.2, 0.2 },
		},
		{
			id = "phone_holo",
			displayName = "Holo Case",
			slot = "PhoneSkin",
			starCost = 60,
			color = { 0.6, 0.9, 0.95 },
		},

		-- Emotes
		{ id = "emote_wave", displayName = "Wave", slot = "Emote", default = true },
		{ id = "emote_dance", displayName = "Sleepover Shuffle", slot = "Emote", starCost = 150 },

		-- Nameplates
		{
			id = "plate_default",
			displayName = "Default Nameplate",
			slot = "Nameplate",
			default = true,
		},
		{ id = "plate_gold", displayName = "Golden Nameplate", slot = "Nameplate", starCost = 300 },

		-- Themes (cosmetic room/effect themes, GDD §11)
		{ id = "theme_cozy", displayName = "Cozy", slot = "Theme", default = true },
		{ id = "theme_y2k", displayName = "Y2K", slot = "Theme", starCost = 250 },
		{ id = "theme_spooky", displayName = "Spooky", slot = "Theme", robuxProductId = 0 },
	} :: { CosmeticDef },

	-- Host Pass (GDD §11) — convenience only, never gameplay power. Scaffold id.
	hostPassId = 0,
}

-- id -> def lookup and per-slot default equips, built once.
local byId: { [string]: CosmeticDef } = {}
local defaults: { [string]: string } = {}
local defaultOwned: { [string]: boolean } = {}
for _, item in CosmeticConfig.catalog do
	byId[item.id] = item
	if item.default then
		defaults[item.slot] = item.id
		defaultOwned[item.id] = true
	end
end
CosmeticConfig.byId = byId
CosmeticConfig.defaultEquipped = defaults
CosmeticConfig.defaultOwned = defaultOwned

function CosmeticConfig.get(id: string): CosmeticDef?
	return byId[id]
end

return CosmeticConfig
