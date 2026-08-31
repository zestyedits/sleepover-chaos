--!strict
-- RandomUtil — small helpers for weighted selection and no-immediate-repeat picking.
-- Used by ActivityManager / EventManager to choose the next thing to run (GDD §5).

local RandomUtil = {}

local rng = Random.new()

export type Weighted<T> = {
	value: T,
	weight: number,
}

-- Pick a value from a list of { value, weight } entries, proportional to weight.
function RandomUtil.weighted<T>(entries: { Weighted<T> }): T?
	local total = 0
	for _, entry in entries do
		total += math.max(entry.weight, 0)
	end
	if total <= 0 then
		return nil
	end

	local roll = rng:NextNumber(0, total)
	local cumulative = 0
	for _, entry in entries do
		cumulative += math.max(entry.weight, 0)
		if roll <= cumulative then
			return entry.value
		end
	end
	-- Floating point fallthrough: return the last entry.
	return entries[#entries] and entries[#entries].value or nil
end

-- Weighted pick that avoids returning `avoid` when other options exist. Keeps the
-- session from playing the same activity/event twice in a row (GDD §5 "no immediate repeat").
function RandomUtil.weightedAvoiding<T>(entries: { Weighted<T> }, avoid: T?): T?
	if avoid == nil then
		return RandomUtil.weighted(entries)
	end

	local filtered = {}
	for _, entry in entries do
		if entry.value ~= avoid then
			table.insert(filtered, entry)
		end
	end

	if #filtered == 0 then
		-- Only the avoided option was available.
		return RandomUtil.weighted(entries)
	end
	return RandomUtil.weighted(filtered)
end

function RandomUtil.pick<T>(list: { T }): T?
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

function RandomUtil.chance(probability: number): boolean
	return rng:NextNumber(0, 1) <= probability
end

function RandomUtil.range(min: number, max: number): number
	return rng:NextNumber(min, max)
end

return RandomUtil
