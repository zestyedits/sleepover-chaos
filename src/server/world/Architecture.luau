--!strict
-- Architecture — the detail layer that makes a room read as a room rather than a box.
--
-- HouseBuilder emits structure: slabs, walls, openings, stairs. That gets you a floorplan you can
-- walk, and it looks like a floorplan you can walk. This module is everything on top — trim,
-- panelling, window frames, vaulted ceilings, string lights, candles.
--
-- ── Why trim matters more than it sounds ────────────────────────────────────────────────────
-- A flat wall gives the eye nothing to measure depth or scale against, so it reads as a
-- rectangle regardless of how well it is lit. Add a baseboard, a chair rail and panel insets and
-- the same wall suddenly has craft. In testing this changed a screenshot more than any lighting
-- tweak did, for about 80 parts a room. It is the cheapest quality win available.
--
-- ── The Neon trick ──────────────────────────────────────────────────────────────────────────
-- Roblox has a per-frame budget for local lights, and a string of forty PointLights will blow it
-- and start getting culled. Neon emits VISUALLY without being a light source, so a garland is
-- forty Neon beads plus three or four real lights for the actual pools. Forty glowing points for
-- the cost of four.
--
-- Related trap, learned the hard way: a large Neon surface always renders at full brightness, so
-- a Neon lampshade the size of a television blows out to a white rectangle. Shades are ordinary
-- fabric with a small Neon bulb inside them.

local Architecture = {}

-- The proven palette. Warm, dark, low saturation -- the walls have to stay readable at
-- Brightness 0.35 without turning orange.
Architecture.palette = {
	floor = Color3.fromRGB(60, 40, 28),
	wall = Color3.fromRGB(46, 34, 27),
	ceiling = Color3.fromRGB(30, 22, 18),
	trim = Color3.fromRGB(38, 28, 22),
	panel = Color3.fromRGB(54, 40, 32),
	beam = Color3.fromRGB(40, 29, 22),
	brick = Color3.fromRGB(104, 62, 48),
	glass = Color3.fromRGB(28, 34, 52),
	shade = Color3.fromRGB(214, 186, 146),
	bulb = Color3.fromRGB(255, 214, 160),
	flame = Color3.fromRGB(255, 190, 120),
	warmLight = Color3.fromRGB(255, 170, 92),
}

local P = Architecture.palette

local function make(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.Wood
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

Architecture.make = make

local function pointLight(
	host: Instance,
	brightness: number,
	range: number,
	color: Color3?,
	shadows: boolean?
)
	local light = Instance.new("PointLight")
	light.Brightness = brightness
	light.Range = range
	light.Color = color or P.warmLight
	light.Shadows = shadows == true
	light.Parent = host
	return light
end

Architecture.pointLight = pointLight

--------------------------------------------------------------------------------------------------
-- Ceilings
--------------------------------------------------------------------------------------------------

-- A pitched/vaulted ceiling over a rectangular room, plus a ridge beam, cross beams and stepped
-- gable infill at each end.
--
-- Built from rotated slabs rather than WedgeParts on purpose. A WedgePart's slope axis is easy to
-- get wrong -- the first attempt at this produced two enormous vertical slabs standing in the
-- middle of the room. A slab rotated about Z is unambiguous: positive angle raises the +X end.
function Architecture.vault(
	parent: Instance,
	centre: Vector3,
	width: number,
	depth: number,
	wallTop: number,
	peak: number,
	beams: number?
)
	local rise = peak - wallTop
	if rise <= 0 then
		return
	end
	local half = width / 2
	local angle = math.atan2(rise, half)
	local slope = math.sqrt(half * half + rise * rise)

	for _, side in { -1, 1 } do
		make(
			"Vault",
			Vector3.new(slope, 0.8, depth),
			CFrame.new(centre + Vector3.new(side * (half / 2), wallTop + rise / 2, 0))
				* CFrame.Angles(0, 0, -side * angle),
			P.ceiling,
			Enum.Material.WoodPlanks,
			parent
		)
	end

	make(
		"Ridge",
		Vector3.new(1.6, 1.6, depth),
		CFrame.new(centre + Vector3.new(0, peak - 0.6, 0)),
		P.beam,
		Enum.Material.Wood,
		parent
	)

	local count = beams or 5
	for i = 1, count do
		local t = (i / (count + 1)) - 0.5
		make(
			"Beam",
			Vector3.new(width, 1.1, 1.5),
			CFrame.new(centre + Vector3.new(0, wallTop + 0.8, t * depth)),
			P.beam,
			Enum.Material.Wood,
			parent
		)
	end

	-- Gable infill: the triangle above each end wall, stepped so it needs no wedge maths.
	for _, zside in { -1, 1 } do
		local steps = 7
		for i = 1, steps do
			local t = (i - 0.5) / steps
			make(
				"Gable",
				Vector3.new(width * (1 - t), rise / steps + 0.2, 1),
				CFrame.new(centre + Vector3.new(0, wallTop + rise * t, zside * (depth / 2))),
				P.wall,
				Enum.Material.Wood,
				parent
			)
		end
	end
end

--------------------------------------------------------------------------------------------------
-- Trim and panelling
--------------------------------------------------------------------------------------------------

-- Baseboard, chair rail and crown around the inside of a rectangular room.
function Architecture.trim(
	parent: Instance,
	centre: Vector3,
	width: number,
	depth: number,
	wallTop: number
)
	local runs = {
		{ size = Vector3.new(width, 1, 0.5), offset = Vector3.new(0, 0, depth / 2 - 0.75) },
		{ size = Vector3.new(width, 1, 0.5), offset = Vector3.new(0, 0, -depth / 2 + 0.75) },
		{ size = Vector3.new(0.5, 1, depth), offset = Vector3.new(-width / 2 + 0.75, 0, 0) },
		{ size = Vector3.new(0.5, 1, depth), offset = Vector3.new(width / 2 - 0.75, 0, 0) },
	}
	for _, run in runs do
		make(
			"Baseboard",
			run.size,
			CFrame.new(centre + run.offset + Vector3.new(0, 1.2, 0)),
			P.trim,
			nil,
			parent
		)
		make(
			"ChairRail",
			run.size * Vector3.new(1, 0.4, 1),
			CFrame.new(centre + run.offset + Vector3.new(0, 5.5, 0)),
			P.trim,
			nil,
			parent
		)
		make(
			"Crown",
			run.size * Vector3.new(1, 0.9, 1.4),
			CFrame.new(centre + run.offset + Vector3.new(0, wallTop - 0.6, 0)),
			P.trim,
			nil,
			parent
		)
	end
end

-- Inset panels between baseboard and chair rail along one wall.
-- `axis` is the axis the wall RUNS along: "x" for a wall spanning X, "z" for one spanning Z.
function Architecture.panelling(
	parent: Instance,
	centre: Vector3,
	axis: string,
	fixed: number,
	from: number,
	to: number,
	count: number
)
	local span = to - from
	for i = 0, count - 1 do
		local along = from + span * ((i + 0.5) / count)
		local offset = if axis == "x"
			then Vector3.new(along, 3.4, fixed)
			else Vector3.new(fixed, 3.4, along)
		local size = if axis == "x"
			then Vector3.new(span / count - 1.2, 3.4, 0.3)
			else Vector3.new(0.3, 3.4, span / count - 1.2)
		make("Panel", size, CFrame.new(centre + offset), P.panel, nil, parent)
	end
end

--------------------------------------------------------------------------------------------------
-- Windows
--------------------------------------------------------------------------------------------------

export type WindowSpec = {
	width: number,
	height: number,
	sill: number,
	mullionsX: number?,
	mullionsY: number?,
}

-- A framed, mullioned window in a wall. `cframe` sits in the wall plane, looking OUT of the room.
--
-- The mullion grid is what makes a window read as a window rather than a dark rectangle, and it
-- is also what sells the fake world outside: a grid in front of a flat backdrop reads as depth.
function Architecture.window(parent: Instance, cframe: CFrame, spec: WindowSpec)
	local width, height, sill = spec.width, spec.height, spec.sill
	local centreY = sill + height / 2

	local glass = make(
		"Glass",
		Vector3.new(0.2, height, width),
		cframe * CFrame.new(0, centreY, 0),
		P.glass,
		Enum.Material.Glass,
		parent
	)
	glass.Transparency = 0.35
	glass.Reflectance = 0.08

	make(
		"Frame",
		Vector3.new(0.5, height + 1.4, 0.8),
		cframe * CFrame.new(0, centreY, -width / 2 - 0.4),
		P.trim,
		nil,
		parent
	)
	make(
		"Frame",
		Vector3.new(0.5, height + 1.4, 0.8),
		cframe * CFrame.new(0, centreY, width / 2 + 0.4),
		P.trim,
		nil,
		parent
	)
	make(
		"Frame",
		Vector3.new(0.5, 0.8, width + 1.6),
		cframe * CFrame.new(0, sill - 0.4, 0),
		P.trim,
		nil,
		parent
	)
	make(
		"Frame",
		Vector3.new(0.5, 0.8, width + 1.6),
		cframe * CFrame.new(0, sill + height + 0.4, 0),
		P.trim,
		nil,
		parent
	)

	for i = 1, spec.mullionsX or 3 do
		local t = i / ((spec.mullionsX or 3) + 1)
		make(
			"Mullion",
			Vector3.new(0.35, height, 0.22),
			cframe * CFrame.new(0, centreY, -width / 2 + width * t),
			P.trim,
			nil,
			parent
		)
	end
	for i = 1, spec.mullionsY or 4 do
		local t = i / ((spec.mullionsY or 4) + 1)
		make(
			"Mullion",
			Vector3.new(0.35, 0.22, width),
			cframe * CFrame.new(0, sill + height * t, 0),
			P.trim,
			nil,
			parent
		)
	end
end

--------------------------------------------------------------------------------------------------
-- Light fixtures
--------------------------------------------------------------------------------------------------

-- A string of fairy lights sagging between two points. `realLights` is how many of the beads
-- become actual PointLights -- keep it small, that is the entire point of this function.
function Architecture.garland(
	parent: Instance,
	from: Vector3,
	to: Vector3,
	sag: number,
	beads: number,
	realLights: number
): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Garland"
	folder.Parent = parent

	local every = math.max(1, math.floor(beads / math.max(realLights, 1)))
	for i = 0, beads do
		local t = i / beads
		local position = from:Lerp(to, t) - Vector3.new(0, math.sin(t * math.pi) * sag, 0)
		local bead = make(
			"Bead",
			Vector3.new(0.35, 0.35, 0.35),
			CFrame.new(position),
			P.flame,
			Enum.Material.Neon,
			folder
		)
		bead.CastShadow = false
		if i % every == 0 then
			pointLight(bead, 0.45, 11)
		end
	end
	return folder
end

-- A lamp: fabric shade, small Neon bulb inside, one warm shadow-casting light.
function Architecture.lamp(parent: Instance, base: Vector3, poleHeight: number): Model
	local model = Instance.new("Model")
	model.Name = "Lamp"
	model.Parent = parent

	make(
		"Pole",
		Vector3.new(0.3, poleHeight, 0.3),
		CFrame.new(base + Vector3.new(0, poleHeight / 2, 0)),
		Color3.fromRGB(60, 45, 35),
		nil,
		model
	)
	local shade = make(
		"Shade",
		Vector3.new(3.2, 2.6, 3.2),
		CFrame.new(base + Vector3.new(0, poleHeight + 1, 0)),
		P.shade,
		Enum.Material.Fabric,
		model
	)
	shade.CastShadow = false
	local bulb =
		make("Bulb", Vector3.new(0.9, 0.9, 0.9), shade.CFrame, P.bulb, Enum.Material.Neon, model)
	bulb.CastShadow = false
	pointLight(shade, 1.5, 22, P.warmLight, true)
	return model
end

function Architecture.candle(parent: Instance, position: Vector3): Part
	local candle = make(
		"Candle",
		Vector3.new(0.4, 0.9, 0.4),
		CFrame.new(position),
		Color3.fromRGB(255, 240, 210),
		Enum.Material.Neon,
		parent
	)
	candle.CastShadow = false
	pointLight(candle, 0.8, 9)
	return candle
end

-- Wide, dim, shadowless lights near the ceiling. Roblox has no global illumination, so without
-- something faking bounce every surface not directly lit goes flat black and the trim disappears.
-- These are bounce, not sources -- hence shadows off and a very low brightness.
function Architecture.fillLight(parent: Instance, position: Vector3, range: number): Part
	local host = make("FillHost", Vector3.new(1, 1, 1), CFrame.new(position), P.wall, nil, parent)
	host.Transparency = 1
	host.CastShadow = false
	pointLight(host, 0.5, range, P.warmLight, false)
	return host
end

return Architecture
