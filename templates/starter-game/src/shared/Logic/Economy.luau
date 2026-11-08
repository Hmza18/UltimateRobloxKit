--!strict
-- Currency maths. Pure Luau. Currency results are finite whole numbers clamped to [0, MAX_CURRENCY].

local Economy = {}

-- Doubles stop representing every integer above 2^53, so balances stay well below it.
Economy.MAX_CURRENCY = 1e15

local SUFFIXES = { "", "K", "M", "B", "T", "Qa" }

function Economy.isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Rounds half away from zero. The tiny relative nudge absorbs binary error, so 1.005 rounds to 1.01.
function Economy.round(value: number, decimals: number?): number
	if not Economy.isFinite(value) then
		return 0
	end
	local factor = 10 ^ (decimals or 0)
	local scaled = math.abs(value) * factor
	local rounded = math.floor(scaled + 0.5 + scaled * 1e-12) / factor
	return if value < 0 then -rounded else rounded
end

-- Whole number in [0, MAX_CURRENCY]. NaN, infinities and negatives become 0.
function Economy.clamp(value: number): number
	if not Economy.isFinite(value) or value <= 0 then
		return 0
	end
	return math.min(math.floor(value), Economy.MAX_CURRENCY)
end

-- Adds `delta` (which may be negative) to `balance` and clamps the result.
function Economy.add(balance: number, delta: number): number
	return Economy.clamp(balance + delta)
end

function Economy.canAfford(balance: number, cost: number): boolean
	return Economy.isFinite(balance) and Economy.isFinite(cost) and cost >= 0 and balance >= cost
end

-- Price of the next item when `owned` are already bought: base * growth ^ owned, rounded.
function Economy.price(base: number, growth: number, owned: number): number
	return Economy.clamp(Economy.round(base * growth ^ owned))
end

-- Total for `quantity` more items (at most 1000). It sums the same per-item prices,
-- so buying ten at once always costs the same as buying one ten times.
function Economy.bulkPrice(base: number, growth: number, owned: number, quantity: number): number
	local total = 0
	for index = 0, math.min(quantity, 1000) - 1 do
		total += Economy.price(base, growth, owned + index)
	end
	return Economy.clamp(total)
end

-- How many items `balance` can buy (at most `limit`, default 1000) and their total cost.
function Economy.maxAffordable(balance: number, base: number, growth: number, owned: number, limit: number?)
	local cap = math.min(limit or 1000, 1000)
	local count, total = 0, 0
	while count < cap do
		local nextPrice = Economy.price(base, growth, owned + count)
		if total + nextPrice > balance then
			break
		end
		total += nextPrice
		count += 1
	end
	return count, total
end

-- 1 + rebirths * bonus, so a bonus of 0.5 gives x1.5 after one rebirth and x2 after two.
function Economy.rebirthMultiplier(rebirths: number, bonus: number): number
	return 1 + math.max(rebirths, 0) * bonus
end

function Economy.rebirthCost(base: number, scale: number, rebirths: number): number
	return Economy.price(base, scale, rebirths)
end

-- Applies a multiplier to earnings, rounding down so multipliers never create fractional currency.
function Economy.applyMultiplier(amount: number, multiplier: number): number
	return Economy.clamp(amount * multiplier)
end

-- Formats 1234567 as "1.23M". Values under 1000 print as whole numbers.
function Economy.abbreviate(value: number): string
	if not Economy.isFinite(value) then
		return "0"
	end
	local sign = if value < 0 then "-" else ""
	local amount = math.abs(value)
	local tier = 1
	while amount >= 1000 and tier < #SUFFIXES do
		amount /= 1000
		tier += 1
	end
	if tier == 1 then
		return sign .. tostring(math.floor(amount))
	end
	local text = string.format("%.2f", math.floor(amount * 100 + 1e-9) / 100)
	local trimmed = string.gsub(text, "0+$", "")
	trimmed = string.gsub(trimmed, "%.$", "")
	return sign .. trimmed .. SUFFIXES[tier]
end

return Economy
