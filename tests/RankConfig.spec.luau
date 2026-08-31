--!nocheck
-- TestEZ spec for RankConfig (pure progression math, GDD §9).
-- Run in Studio via a TestEZ runner (see README "Running tests").

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RankConfig = require(ReplicatedStorage.Shared.config.RankConfig)

	describe("RankConfig.xpForLevel", function()
		it("requires no xp to be at level 1", function()
			expect(RankConfig.xpForLevel(1)).to.equal(0)
		end)

		it("increases monotonically with level", function()
			local last = -1
			for level = 1, 20 do
				local xp = RankConfig.xpForLevel(level)
				expect(xp >= last).to.equal(true)
				last = xp
			end
		end)
	end)

	describe("RankConfig.rankForLevel", function()
		it("starts at Guest", function()
			expect(RankConfig.rankForLevel(1)).to.equal("Guest")
		end)

		it("promotes at each threshold", function()
			expect(RankConfig.rankForLevel(5)).to.equal("Regular")
			expect(RankConfig.rankForLevel(12)).to.equal("Bestie")
			expect(RankConfig.rankForLevel(25)).to.equal("Sleepover Pro")
			expect(RankConfig.rankForLevel(40)).to.equal("Party Legend")
		end)

		it("holds the highest reached rank between thresholds", function()
			expect(RankConfig.rankForLevel(11)).to.equal("Regular")
			expect(RankConfig.rankForLevel(24)).to.equal("Bestie")
		end)
	end)
end
