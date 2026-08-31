--!nocheck
-- TestEZ spec for the house geometry. HouseConfig is hand-authored coordinates, which is exactly
-- the kind of data where a transposed number produces a room you cannot enter, a doorway that
-- opens into a wall, or a sofa embedded in the kitchen — none of which the type checker or the
-- linter can see. These assertions are the cheap version of walking the whole house.

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Shared = ReplicatedStorage.Shared
	local HouseConfig = require(Shared.config.HouseConfig)

	local function levelById(id)
		for _, level in HouseConfig.levels do
			if level.id == id then
				return level
			end
		end
		return nil
	end

	local function roomById(id)
		for _, room in HouseConfig.rooms do
			if room.id == id then
				return room
			end
		end
		return nil
	end

	local function contains(rect, x, z)
		return x >= rect[1] and x <= rect[3] and z >= rect[2] and z <= rect[4]
	end

	-- Strict overlap: rooms that merely share an edge (every interior wall) are fine.
	local function overlaps(a, b)
		return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
	end

	describe("levels", function()
		it("stack without gaps", function()
			for i = 2, #HouseConfig.levels do
				local below = HouseConfig.levels[i - 1]
				local above = HouseConfig.levels[i]
				expect(below.baseY + below.ceilingHeight).to.equal(above.baseY)
			end
		end)
	end)

	describe("rooms", function()
		it("each reference a real level and have positive area", function()
			for _, room in HouseConfig.rooms do
				expect(levelById(room.level)).to.be.ok()
				expect(room.rect[3] > room.rect[1]).to.equal(true)
				expect(room.rect[4] > room.rect[2]).to.equal(true)
			end
		end)

		it("do not overlap within a level", function()
			for i = 1, #HouseConfig.rooms do
				for j = i + 1, #HouseConfig.rooms do
					local a, b = HouseConfig.rooms[i], HouseConfig.rooms[j]
					if a.level == b.level then
						expect(overlaps(a.rect, b.rect)).to.equal(false)
					end
				end
			end
		end)

		it("keep every floor hole inside its own floor", function()
			for _, room in HouseConfig.rooms do
				if room.floorHole then
					expect(room.floorHole[1] >= room.rect[1]).to.equal(true)
					expect(room.floorHole[2] >= room.rect[2]).to.equal(true)
					expect(room.floorHole[3] <= room.rect[3]).to.equal(true)
					expect(room.floorHole[4] <= room.rect[4]).to.equal(true)
				end
			end
		end)
	end)

	describe("walls", function()
		it("are axis-aligned and reference a real level", function()
			for _, wall in HouseConfig.walls do
				expect(levelById(wall.level)).to.be.ok()
				local sameX = wall.from[1] == wall.to[1]
				local sameZ = wall.from[2] == wall.to[2]
				-- Exactly one axis may vary; a diagonal wall would be built wrong, not rejected.
				expect(sameX ~= sameZ).to.equal(true)
			end
		end)

		it("keep every doorway inside its wall run", function()
			for _, wall in HouseConfig.walls do
				local alongX = wall.from[2] == wall.to[2]
				local a = if alongX then wall.from[1] else wall.from[2]
				local b = if alongX then wall.to[1] else wall.to[2]
				local runStart, runEnd = math.min(a, b), math.max(a, b)
				local wallHeight = wall.height or levelById(wall.level).ceilingHeight
				for _, opening in wall.openings or {} do
					local half = opening.width / 2
					expect(opening.at - half >= runStart).to.equal(true)
					expect(opening.at + half <= runEnd).to.equal(true)
					-- A doorway as tall as the wall leaves no header and reads as a missing wall.
					expect((opening.height or HouseConfig.doorHeight) < wallHeight).to.equal(true)
				end
			end
		end)
	end)

	describe("stairs", function()
		it("land exactly on the level above", function()
			for _, stair in HouseConfig.stairs do
				local room = roomById(stair.room)
				expect(room).to.be.ok()
				local topY = levelById(room.level).baseY + stair.to[2]
				-- The top tread must be flush with SOME level's floor, or you arrive at a lip.
				local landsOnALevel = false
				for _, level in HouseConfig.levels do
					if level.baseY == topY then
						landsOnALevel = true
					end
				end
				expect(landsOnALevel).to.equal(true)
				expect(stair.steps > 0).to.equal(true)
			end
		end)
	end)

	describe("placements", function()
		it("put every spawn, anchor, and prop inside its named room", function()
			local groups = {
				{ list = HouseConfig.spawns, label = "spawn" },
				{ list = HouseConfig.anchors, label = "anchor" },
				{ list = HouseConfig.furniture, label = "furniture" },
			}
			for _, group in groups do
				for _, item in group.list do
					local room = roomById(item.room)
					expect(room).to.be.ok()
					expect(contains(room.rect, item.at[1], item.at[3])).to.equal(true)
				end
			end
		end)

		it("gives every activity an anchor", function()
			local seen = {}
			for _, anchor in HouseConfig.anchors do
				seen[anchor.activity] = true
			end
			for _, activity in
				{ "PillowFight", "ParentCheck", "MidnightSnack", "HideAndSeek", "GhostStory" }
			do
				expect(seen[activity]).to.equal(true)
			end
		end)
	end)

	describe("hiding spots", function()
		it("are spread across at least three rooms with unique labels", function()
			local labels, rooms, count = {}, {}, 0
			for _, item in HouseConfig.furniture do
				if item.hides then
					expect(labels[item.hides]).to.equal(nil)
					labels[item.hides] = true
					rooms[item.room] = true
					count += 1
				end
			end
			expect(count >= 4).to.equal(true)

			local roomCount = 0
			for _ in rooms do
				roomCount += 1
			end
			expect(roomCount >= 3).to.equal(true)
		end)
	end)

	describe("snack sources", function()
		it("are all in the kitchen with unique names", function()
			local seen, count = {}, 0
			for _, item in HouseConfig.furniture do
				if item.snack then
					expect(seen[item.snack]).to.equal(nil)
					seen[item.snack] = true
					expect(item.room).to.equal("Kitchen")
					count += 1
				end
			end
			expect(count >= 3).to.equal(true)
		end)
	end)

	describe("attic access", function()
		it("puts the hatch inside the attic floor hole", function()
			local attic = roomById("Attic")
			expect(attic).to.be.ok()
			expect(attic.floorHole).to.be.ok()

			local access = HouseConfig.atticAccess
			local x, z = access.hatchCenter[1], access.hatchCenter[2]
			expect(contains(attic.floorHole, x, z)).to.equal(true)

			-- The hatch panel must actually cover the opening, or the attic is never sealed.
			expect(access.hatchSize[1] >= attic.floorHole[3] - attic.floorHole[1]).to.equal(true)
			expect(access.hatchSize[3] >= attic.floorHole[4] - attic.floorHole[2]).to.equal(true)
		end)

		it("runs the ladder between the landing and the attic floor", function()
			local access = HouseConfig.atticAccess
			expect(access.ladderBottomY).to.equal(levelById("Upper").baseY)
			expect(access.ladderTopY).to.equal(levelById("Attic").baseY)
		end)
	end)
end
