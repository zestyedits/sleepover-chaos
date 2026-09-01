--!strict
-- SleepingBags — the cosmetic every player actually sees themselves in.
--
-- A sleeping bag is the one cosmetic that is visible from across the room, sits in the middle of
-- the social space, and stays on screen for the whole sleepover. That makes it the natural thing
-- to monetise, and the natural thing to make readable at a glance: each design is a distinct
-- SILHOUETTE and colour block, not a texture you have to walk up to.
--
-- Built procedurally rather than modelled because the shape is genuinely trivial -- a quilted mat
-- and a pillow -- and because generating them means a new design is a table entry, not an asset
-- pipeline. Roughly 20 parts each.
--
-- Ownership, pricing and equipping all live in the existing cosmetic system (CosmeticConfig,
-- CosmeticService, PlayerDataService). This module only knows how to draw one.

local SleepingBags = {}

export type Design = {
	id: string,
	base: Color3, -- the mat
	quilt: Color3, -- the raised padded segments
	pillow: Color3,
	accent: Color3, -- motif colour
	quiltAlt: Color3?, -- alternating segment colour, for banded designs
	motif: string?, -- "stars" | "moon" | "dino" | "pizza" | "cat" | nil
}

-- Dimensions. A little wider and longer than a real bedroll, because Roblox reads small objects
-- as clutter and an avatar is 2 studs wide.
local WIDTH = 5
local LENGTH = 13
local PAD_HEIGHT = 0.4
local QUILT_HEIGHT = 0.35
local SEGMENTS = 4

-- Motifs sit on TOP of the quilting, not on the mat. Placing them at mat height buried every
-- pattern underneath the padded segments -- the bags rendered as plain colour blocks and only the
-- cat face showed, because that one lives on the pillow.
local MOTIF_Y = PAD_HEIGHT + QUILT_HEIGHT + 0.09

local DESIGNS: { [string]: Design } = {
	-- The one every new profile starts with. Deliberately plain: it has to read as "yours" but
	-- also make the paid ones look like an upgrade.
	bag_default = {
		id = "bag_default",
		base = Color3.fromRGB(126, 134, 148),
		quilt = Color3.fromRGB(150, 158, 172),
		pillow = Color3.fromRGB(226, 228, 234),
		accent = Color3.fromRGB(170, 178, 190),
	},
	bag_stargazer = {
		id = "bag_stargazer",
		base = Color3.fromRGB(178, 44, 46),
		quilt = Color3.fromRGB(198, 58, 60),
		pillow = Color3.fromRGB(214, 74, 76),
		accent = Color3.fromRGB(250, 206, 84),
		motif = "stars",
	},
	bag_galaxy = {
		id = "bag_galaxy",
		base = Color3.fromRGB(48, 30, 84),
		quilt = Color3.fromRGB(62, 40, 104),
		pillow = Color3.fromRGB(78, 52, 126),
		accent = Color3.fromRGB(246, 244, 255),
		motif = "moon",
	},
	bag_kitty = {
		id = "bag_kitty",
		base = Color3.fromRGB(240, 158, 196),
		quilt = Color3.fromRGB(252, 226, 238),
		pillow = Color3.fromRGB(255, 248, 252),
		accent = Color3.fromRGB(80, 62, 72),
		quiltAlt = Color3.fromRGB(246, 176, 208),
		motif = "cat",
	},
	bag_dino = {
		id = "bag_dino",
		base = Color3.fromRGB(84, 158, 62),
		quilt = Color3.fromRGB(104, 180, 76),
		pillow = Color3.fromRGB(132, 200, 104),
		accent = Color3.fromRGB(46, 96, 40),
		motif = "dino",
	},
	bag_pizza = {
		id = "bag_pizza",
		base = Color3.fromRGB(46, 92, 176),
		quilt = Color3.fromRGB(60, 112, 200),
		pillow = Color3.fromRGB(84, 138, 220),
		accent = Color3.fromRGB(250, 196, 78),
		motif = "pizza",
	},
}

SleepingBags.designs = DESIGNS

local function piece(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.Fabric
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Motifs are deliberately chunky. A detailed pattern is invisible at play distance and costs
-- parts; a few bold shapes still read as "the dinosaur one" from across the room.
local function addMotif(model: Model, base: CFrame, design: Design)
	local motif = design.motif
	if not motif then
		return
	end
	local accent = design.accent

	if motif == "stars" then
		for i = 1, 7 do
			local x = ((i % 3) - 1) * 1.5
			local z = -4 + (i - 1) * 1.4
			local star = piece(
				model,
				"Star",
				Vector3.new(0.7, 0.12, 0.7),
				base * CFrame.new(x, MOTIF_Y, z) * CFrame.Angles(0, math.rad(45), 0),
				accent
			)
			star.Material = Enum.Material.Neon
			star.CastShadow = false
		end
	elseif motif == "moon" then
		-- A crescent: a bright disc with a base-coloured disc biting into it.
		local disc = piece(
			model,
			"Moon",
			Vector3.new(0.14, 2.4, 2.4),
			base * CFrame.new(0, MOTIF_Y, -3),
			accent
		)
		disc.Shape = Enum.PartType.Cylinder
		disc.CFrame = disc.CFrame * CFrame.Angles(0, 0, math.rad(90))
		disc.Material = Enum.Material.Neon
		disc.CastShadow = false
		local bite = piece(
			model,
			"MoonBite",
			Vector3.new(0.2, 2.0, 2.0),
			base * CFrame.new(0.9, MOTIF_Y + 0.03, -3.5),
			design.base
		)
		bite.Shape = Enum.PartType.Cylinder
		bite.CFrame = bite.CFrame * CFrame.Angles(0, 0, math.rad(90))
		bite.CastShadow = false
		for i = 1, 5 do
			local star = piece(
				model,
				"Star",
				Vector3.new(0.5, 0.12, 0.5),
				base * CFrame.new(((i % 2) * 2 - 1) * 1.6, MOTIF_Y, 0.5 + i * 1.1),
				accent
			)
			star.Material = Enum.Material.Neon
			star.CastShadow = false
		end
	elseif motif == "cat" then
		-- Face on the pillow: ears, eyes, nose. This one is a silhouette gag, so it goes at the
		-- head where a player looking at their own bag will see it.
		local head = base * CFrame.new(0, 0.95, -LENGTH / 2 + 1.1)
		for _, side in { -1, 1 } do
			local ear = piece(
				model,
				"Ear",
				Vector3.new(0.9, 0.7, 0.5),
				head * CFrame.new(side * 1.1, 0.5, 0),
				design.pillow
			)
			ear.CastShadow = false
		end
		for _, side in { -1, 1 } do
			piece(
				model,
				"Eye",
				Vector3.new(0.3, 0.3, 0.16),
				head * CFrame.new(side * 0.7, 0.1, -1.1),
				accent
			)
		end
		piece(
			model,
			"Nose",
			Vector3.new(0.28, 0.2, 0.16),
			head * CFrame.new(0, -0.2, -1.1),
			Color3.fromRGB(240, 150, 170)
		)
	elseif motif == "dino" then
		for i = 1, 4 do
			local z = -3.5 + (i - 1) * 2.6
			local x = ((i % 2) * 2 - 1) * 1.2
			-- body + tail + a spine ridge: enough to read as a lizard from above
			piece(
				model,
				"Dino",
				Vector3.new(1.5, 0.14, 0.8),
				base * CFrame.new(x, MOTIF_Y, z),
				accent
			)
			piece(
				model,
				"DinoTail",
				Vector3.new(0.7, 0.14, 0.4),
				base * CFrame.new(x - 1, MOTIF_Y, z + 0.4),
				accent
			)
			piece(
				model,
				"DinoHead",
				Vector3.new(0.5, 0.14, 0.5),
				base * CFrame.new(x + 0.9, MOTIF_Y, z - 0.3),
				accent
			)
		end
	elseif motif == "pizza" then
		for i = 1, 5 do
			local z = -4 + (i - 1) * 2.2
			local x = ((i % 2) * 2 - 1) * 1.3
			local slice = piece(
				model,
				"Pizza",
				Vector3.new(1.3, 0.14, 1.3),
				base * CFrame.new(x, MOTIF_Y, z) * CFrame.Angles(0, math.rad(45), 0),
				accent
			)
			slice.CastShadow = false
			piece(
				model,
				"Pepperoni",
				Vector3.new(0.34, 0.16, 0.34),
				base * CFrame.new(x, MOTIF_Y + 0.02, z),
				Color3.fromRGB(196, 62, 48)
			)
		end
	end
end

-- Build one bag. `baseCFrame` sits on the floor at the bag's centre; the pillow is at -Z.
function SleepingBags.build(id: string, baseCFrame: CFrame): (Model?, BasePart?)
	local design = DESIGNS[id] or DESIGNS.bag_default
	local model = Instance.new("Model")
	model.Name = id

	local mat = piece(
		model,
		"Mat",
		Vector3.new(WIDTH, PAD_HEIGHT, LENGTH),
		baseCFrame * CFrame.new(0, PAD_HEIGHT / 2, 0),
		design.base
	)
	model.PrimaryPart = mat

	-- Quilted segments. The gaps between them are what make it read as padded rather than as a
	-- painted rectangle on the floor.
	local usable = LENGTH - 3.2
	for i = 1, SEGMENTS do
		local t = (i - 0.5) / SEGMENTS
		-- Banded designs alternate segment colour; everything else uses one quilt tone.
		local tone = if design.quiltAlt and i % 2 == 0 then design.quiltAlt else design.quilt
		piece(
			model,
			"Quilt",
			Vector3.new(WIDTH - 0.5, QUILT_HEIGHT, usable / SEGMENTS - 0.35),
			baseCFrame
				* CFrame.new(0, PAD_HEIGHT + QUILT_HEIGHT / 2, -usable / 2 + usable * t + 1.4),
			tone
		)
	end

	piece(
		model,
		"Pillow",
		Vector3.new(WIDTH - 0.8, 0.75, 2.4),
		baseCFrame * CFrame.new(0, PAD_HEIGHT + 0.38, -LENGTH / 2 + 1.5),
		design.pillow
	)

	addMotif(model, baseCFrame, design)
	return model, mat
end

function SleepingBags.exists(id: string): boolean
	return DESIGNS[id] ~= nil
end

return SleepingBags
