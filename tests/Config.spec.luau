--!nocheck
-- TestEZ spec for config integrity — catches typos that would break selection/rewards at
-- runtime (GDD §5 activity/event pools, §9 rewards, §10 scrapbook, §11 cosmetics).

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Shared = ReplicatedStorage.Shared
	local ActivityConfig = require(Shared.config.ActivityConfig)
	local EventConfig = require(Shared.config.EventConfig)
	local ScrapbookConfig = require(Shared.config.ScrapbookConfig)
	local CosmeticConfig = require(Shared.config.CosmeticConfig)

	describe("ActivityConfig", function()
		it("has the five MVP activities with positive weights", function()
			expect(#ActivityConfig.activities).to.equal(5)
			for _, def in ActivityConfig.activities do
				expect(def.weight > 0).to.equal(true)
				expect(type(def.module)).to.equal("string")
			end
		end)
	end)

	describe("EventConfig", function()
		it("has the three MVP chaos events", function()
			expect(#EventConfig.events).to.equal(3)
		end)

		it("references only real scrapbook ids", function()
			for _, def in EventConfig.events do
				if def.settings.scrapbook then
					expect(ScrapbookConfig.get(def.settings.scrapbook)).to.be.ok()
				end
			end
		end)
	end)

	describe("CosmeticConfig", function()
		it("provides a default equip for every default item's slot", function()
			for slot, id in CosmeticConfig.defaultEquipped do
				local def = CosmeticConfig.get(id)
				expect(def).to.be.ok()
				expect(def.slot).to.equal(slot)
			end
		end)

		it("has at least one default-owned cosmetic", function()
			local count = 0
			for _ in CosmeticConfig.defaultOwned do
				count += 1
			end
			expect(count > 0).to.equal(true)
		end)
	end)
end
