--!strict
-- Props — the greybox furniture kit (GDD §16). One builder per prop kind; HouseConfig.furniture
-- places them.
--
-- These are readable blocks, not art. The point is that a player can tell a pantry from a fridge
-- at a glance, because Hide & Seek's "In the pantry" is only a real instruction if there is a
-- visible pantry to run to. When the art pass lands, these builders get swapped for real models
-- and nothing else in the codebase has to move.
--
-- Conventions:
--   * A prop's base CFrame sits ON THE FLOOR, so local offsets are measured up from y = 0.
--   * Every builder returns the part that should carry any gameplay role (hiding-spot prompt,
--     bed zone, snack source). HouseBuilder tags that part; Props stays gameplay-agnostic.

local Props = {}

local WOOD = Color3.fromRGB(150, 111, 76)
local DARK_WOOD = Color3.fromRGB(102, 76, 54)
local FABRIC = Color3.fromRGB(196, 164, 200)
local WHITE = Color3.fromRGB(238, 238, 240)
local METAL = Color3.fromRGB(178, 182, 188)
local SCREEN = Color3.fromRGB(28, 30, 38)
local CARDBOARD = Color3.fromRGB(178, 145, 101)

type Adder = (
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?,
	canCollide: boolean?
) -> BasePart

-- Four legs under a tabletop, so tables read as tables instead of floating slabs.
local function legs(add: Adder, spanX: number, spanZ: number, height: number, color: Color3)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			add(
				"Leg",
				Vector3.new(0.4, height, 0.4),
				CFrame.new(sx * spanX / 2, height / 2, sz * spanZ / 2),
				color,
				Enum.Material.Wood
			)
		end
	end
end

local BUILDERS: { [string]: (add: Adder) -> BasePart } = {
	Sofa = function(add)
		local seat = add(
			"Seat",
			Vector3.new(8, 1.6, 3.4),
			CFrame.new(0, 1.4, 0),
			FABRIC,
			Enum.Material.Fabric
		)
		add(
			"Back",
			Vector3.new(8, 2.6, 0.8),
			CFrame.new(0, 2.5, -1.7),
			FABRIC,
			Enum.Material.Fabric
		)
		for _, sx in { -1, 1 } do
			add(
				"Arm",
				Vector3.new(0.8, 2.2, 3.4),
				CFrame.new(sx * 3.6, 1.7, 0),
				FABRIC,
				Enum.Material.Fabric
			)
		end
		return seat
	end,

	TV = function(add)
		local stand =
			add("Stand", Vector3.new(6, 2, 1.8), CFrame.new(0, 1, 0), DARK_WOOD, Enum.Material.Wood)
		add("Screen", Vector3.new(7, 4, 0.4), CFrame.new(0, 4.2, 0), SCREEN, Enum.Material.Glass)
		return stand
	end,

	CoffeeTable = function(add)
		local top =
			add("Top", Vector3.new(5, 0.4, 2.6), CFrame.new(0, 1.9, 0), WOOD, Enum.Material.Wood)
		legs(add, 4.4, 2, 1.7, DARK_WOOD)
		return top
	end,

	Rug = function(add)
		-- Non-collidable so it does not create a lip to trip over.
		return add(
			"Rug",
			Vector3.new(12, 0.1, 8),
			CFrame.new(0, 0.06, 0),
			Color3.fromRGB(180, 120, 130),
			Enum.Material.Fabric,
			false
		)
	end,

	Bookshelf = function(add)
		local body =
			add("Body", Vector3.new(6, 8, 1.6), CFrame.new(0, 4, 0), DARK_WOOD, Enum.Material.Wood)
		for i = 1, 3 do
			add(
				"Books",
				Vector3.new(5.2, 1.2, 1),
				CFrame.new(0, i * 2, 0.2),
				Color3.fromRGB(120 + i * 30, 90, 140),
				Enum.Material.SmoothPlastic,
				false
			)
		end
		return body
	end,

	Lamp = function(add)
		add("Pole", Vector3.new(0.4, 6.4, 0.4), CFrame.new(0, 3.2, 0), METAL, Enum.Material.Metal)
		-- Returned as the primary so HouseBuilder can wire it into the blackout light group.
		return add(
			"Shade",
			Vector3.new(2.2, 1.8, 2.2),
			CFrame.new(0, 7.2, 0),
			Color3.fromRGB(255, 244, 214),
			Enum.Material.Neon
		)
	end,

	Counter = function(add)
		local body = add(
			"Body",
			Vector3.new(12, 3.4, 2.4),
			CFrame.new(0, 1.7, 0),
			WHITE,
			Enum.Material.SmoothPlastic
		)
		add(
			"Top",
			Vector3.new(12.4, 0.3, 2.8),
			CFrame.new(0, 3.55, 0),
			DARK_WOOD,
			Enum.Material.Wood
		)
		return body
	end,

	Fridge = function(add)
		local body =
			add("Body", Vector3.new(3.6, 7, 3), CFrame.new(0, 3.5, 0), WHITE, Enum.Material.Metal)
		add(
			"Handle",
			Vector3.new(0.25, 3, 0.25),
			CFrame.new(1.4, 4.4, 1.6),
			METAL,
			Enum.Material.Metal,
			false
		)
		return body
	end,

	Stove = function(add)
		local body =
			add("Body", Vector3.new(4.4, 3.4, 3), CFrame.new(0, 1.7, 0), METAL, Enum.Material.Metal)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				add(
					"Burner",
					Vector3.new(1.1, 0.15, 1.1),
					CFrame.new(sx * 1.1, 3.48, sz * 0.7),
					SCREEN,
					Enum.Material.Slate,
					false
				)
			end
		end
		return body
	end,

	DiningTable = function(add)
		local top =
			add("Top", Vector3.new(7, 0.4, 4), CFrame.new(0, 3, 0), WOOD, Enum.Material.Wood)
		legs(add, 6, 3.2, 2.8, DARK_WOOD)
		return top
	end,

	Chair = function(add)
		local seat =
			add("Seat", Vector3.new(2.2, 0.3, 2.2), CFrame.new(0, 1.9, 0), WOOD, Enum.Material.Wood)
		add("Back", Vector3.new(2.2, 2.4, 0.3), CFrame.new(0, 3.1, -1), WOOD, Enum.Material.Wood)
		legs(add, 1.8, 1.8, 1.75, DARK_WOOD)
		return seat
	end,

	Pantry = function(add)
		add("Cabinet", Vector3.new(4.4, 9, 2.6), CFrame.new(0, 4.5, 0), WOOD, Enum.Material.Wood)
		-- The door is the primary: it is what you interact with, and it is the face you see.
		return add(
			"Door",
			Vector3.new(4, 8, 0.3),
			CFrame.new(0, 4.4, 1.4),
			DARK_WOOD,
			Enum.Material.Wood
		)
	end,

	Closet = function(add)
		add("Cabinet", Vector3.new(5.4, 9, 3), CFrame.new(0, 4.5, 0), WOOD, Enum.Material.Wood)
		return add(
			"Door",
			Vector3.new(5, 8, 0.3),
			CFrame.new(0, 4.4, 1.6),
			DARK_WOOD,
			Enum.Material.Wood
		)
	end,

	Bed = function(add)
		add("Frame", Vector3.new(7, 1.2, 4), CFrame.new(0, 0.6, 0), DARK_WOOD, Enum.Material.Wood)
		add(
			"Headboard",
			Vector3.new(0.4, 4, 4),
			CFrame.new(-3.5, 2, 0),
			DARK_WOOD,
			Enum.Material.Wood
		)
		add(
			"Pillow",
			Vector3.new(1.6, 0.6, 2.6),
			CFrame.new(-2.4, 2.1, 0),
			WHITE,
			Enum.Material.Fabric,
			false
		)
		-- The mattress is both the "get in bed" target and the under-the-bed hiding anchor.
		return add(
			"Mattress",
			Vector3.new(6.6, 1, 3.8),
			CFrame.new(0, 1.7, 0),
			FABRIC,
			Enum.Material.Fabric
		)
	end,

	Nightstand = function(add)
		return add(
			"Body",
			Vector3.new(2.6, 2.6, 2.4),
			CFrame.new(0, 1.3, 0),
			WOOD,
			Enum.Material.Wood
		)
	end,

	Dresser = function(add)
		local body =
			add("Body", Vector3.new(6, 4, 2.6), CFrame.new(0, 2, 0), WOOD, Enum.Material.Wood)
		for i = 0, 2 do
			add(
				"Drawer",
				Vector3.new(5.4, 1, 0.2),
				CFrame.new(0, 0.8 + i * 1.2, 1.35),
				DARK_WOOD,
				Enum.Material.Wood,
				false
			)
		end
		return body
	end,

	Bathtub = function(add)
		add(
			"Shell",
			Vector3.new(7, 2.8, 4),
			CFrame.new(0, 1.4, 0),
			WHITE,
			Enum.Material.SmoothPlastic
		)
		-- A recessed lip so it reads as something you can climb into.
		return add(
			"Basin",
			Vector3.new(6, 0.4, 3),
			CFrame.new(0, 2.7, 0),
			Color3.fromRGB(206, 230, 240),
			Enum.Material.SmoothPlastic,
			false
		)
	end,

	Sink = function(add)
		add(
			"Pedestal",
			Vector3.new(1.6, 3, 1.6),
			CFrame.new(0, 1.5, 0),
			WHITE,
			Enum.Material.SmoothPlastic
		)
		return add(
			"Basin",
			Vector3.new(3, 1, 2.4),
			CFrame.new(0, 3.5, 0),
			WHITE,
			Enum.Material.SmoothPlastic
		)
	end,

	Toilet = function(add)
		local bowl = add(
			"Bowl",
			Vector3.new(2.2, 2.2, 3),
			CFrame.new(0, 1.1, 0),
			WHITE,
			Enum.Material.SmoothPlastic
		)
		add(
			"Tank",
			Vector3.new(2.2, 2.4, 1),
			CFrame.new(0, 2.4, -1.6),
			WHITE,
			Enum.Material.SmoothPlastic
		)
		return bowl
	end,

	ToyChest = function(add)
		local body = add(
			"Body",
			Vector3.new(5, 2.6, 3),
			CFrame.new(0, 1.3, 0),
			Color3.fromRGB(214, 126, 92),
			Enum.Material.Wood
		)
		add("Lid", Vector3.new(5.2, 0.5, 3.2), CFrame.new(0, 2.8, 0), DARK_WOOD, Enum.Material.Wood)
		return body
	end,

	Curtains = function(add)
		add(
			"Rod",
			Vector3.new(9, 0.25, 0.25),
			CFrame.new(0, 9.4, 0),
			METAL,
			Enum.Material.Metal,
			false
		)
		-- Non-collidable: the whole point is that you can step behind them.
		local left = add(
			"PanelLeft",
			Vector3.new(3.4, 9, 0.3),
			CFrame.new(-2.6, 4.6, 0),
			Color3.fromRGB(168, 96, 120),
			Enum.Material.Fabric,
			false
		)
		add(
			"PanelRight",
			Vector3.new(3.4, 9, 0.3),
			CFrame.new(2.6, 4.6, 0),
			Color3.fromRGB(168, 96, 120),
			Enum.Material.Fabric,
			false
		)
		return left
	end,

	AtticBox = function(add)
		return add(
			"Box",
			Vector3.new(3, 3, 3),
			CFrame.new(0, 1.5, 0),
			CARDBOARD,
			Enum.Material.Cardboard
		)
	end,

	SnackBowl = function(add)
		local bowl = add(
			"Bowl",
			Vector3.new(2.2, 1, 2.2),
			CFrame.new(0, 0.5, 0),
			WHITE,
			Enum.Material.SmoothPlastic
		)
		add(
			"Contents",
			Vector3.new(1.8, 0.7, 1.8),
			CFrame.new(0, 1.2, 0),
			Color3.fromRGB(228, 186, 84),
			Enum.Material.SmoothPlastic,
			false
		)
		return bowl
	end,
}

-- Build one prop. `baseCFrame` sits on the floor at the prop's footprint centre.
-- Returns the model and the part that should carry any gameplay role.
function Props.build(kind: string, baseCFrame: CFrame): (Model?, BasePart?)
	local builder = BUILDERS[kind]
	if not builder then
		warn(`[Props] unknown prop kind: {kind}`)
		return nil, nil
	end

	local model = Instance.new("Model")
	model.Name = kind

	local add: Adder = function(name, size, offset, color, material, canCollide)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = baseCFrame * offset
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = if canCollide == nil then true else canCollide
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
		return part
	end

	local primary = builder(add)
	model.PrimaryPart = primary
	return model, primary
end

function Props.exists(kind: string): boolean
	return BUILDERS[kind] ~= nil
end

return Props
