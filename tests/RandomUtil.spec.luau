--!nocheck
-- TestEZ spec for RandomUtil (weighted / no-immediate-repeat selection, GDD §5).

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RandomUtil = require(ReplicatedStorage.Shared.util.RandomUtil)

	describe("RandomUtil.weighted", function()
		it("returns nil for an empty pool", function()
			expect(RandomUtil.weighted({})).to.equal(nil)
		end)

		it("always returns the only positive-weight option", function()
			local pool = { { value = "a", weight = 1 }, { value = "b", weight = 0 } }
			for _ = 1, 25 do
				expect(RandomUtil.weighted(pool)).to.equal("a")
			end
		end)
	end)

	describe("RandomUtil.weightedAvoiding", function()
		it("never returns the avoided value when alternatives exist", function()
			local pool = {
				{ value = "a", weight = 5 },
				{ value = "b", weight = 5 },
			}
			for _ = 1, 50 do
				expect(RandomUtil.weightedAvoiding(pool, "a")).to.equal("b")
			end
		end)

		it("falls back to the avoided value when it is the only option", function()
			local pool = { { value = "solo", weight = 3 } }
			expect(RandomUtil.weightedAvoiding(pool, "solo")).to.equal("solo")
		end)
	end)

	describe("RandomUtil.chance", function()
		it("is always true at probability 1 and false at 0", function()
			expect(RandomUtil.chance(1)).to.equal(true)
			expect(RandomUtil.chance(0)).to.equal(false)
		end)
	end)
end
