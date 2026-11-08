--!strict
local Validate = require("../src/shared/Logic/Validate")
local t = require("./lib/t")

return {
	["number checks range, integers and finiteness"] = function()
		local check = Validate.number({ min = 0, max = 10 })
		t.truthy(check(5))
		t.falsy(check(11))
		t.falsy(check(-1))
		t.falsy(check(math.sqrt(-1)), "NaN")
		t.falsy(check(math.huge), "infinity")
		t.falsy(check("5"), "string")
		t.falsy(Validate.integer(1, 5)(2.5))
		t.truthy(Validate.integer(1, 5)(5))
	end,

	["string checks type, length and pattern"] = function()
		local check = Validate.string({ minLength = 1, maxLength = 5, pattern = "^%a+$" })
		t.truthy(check("abc"))
		t.falsy(check(""))
		t.falsy(check("abcdef"))
		t.falsy(check("ab1"))
		t.falsy(check(12))
		t.falsy(Validate.string()(string.rep("x", 1000)))
	end,

	["oneOf and optional"] = function()
		local check = Validate.oneOf({ "Apple", "Gem" })
		t.truthy(check("Gem"))
		t.falsy(check("Rock"))
		t.falsy(check(nil))
		t.truthy(Validate.optional(check)(nil))
		t.falsy(Validate.optional(check)("Rock"))
	end,

	["array rejects holes, wrong keys and long input"] = function()
		local check = Validate.array(Validate.integer(), 3)
		t.truthy(check({ 1, 2, 3 }))
		t.falsy(check({ 1, 2, 3, 4 }), "too long")
		t.falsy(check({ 1, 2.5 }), "bad item")
		t.falsy(check({ [1] = 1, [3] = 3 }), "hole")
		t.falsy(check({ a = 1 }), "string key")
	end,

	["struct rejects unknown keys"] = function()
		local check = Validate.struct({ id = Validate.string(), amount = Validate.optional(Validate.integer(1)) })
		t.truthy(check({ id = "Apple" }))
		t.truthy(check({ id = "Apple", amount = 2 }))
		t.falsy(check({ id = "Apple", admin = true }))
		t.falsy(check({ amount = 2 }))
		t.falsy(check("Apple"))
	end,

	["args checks the whole argument list"] = function()
		local check = Validate.args({ Validate.string(), Validate.integer(1, 10) })
		t.truthy(check("Apple", 3))
		t.falsy(check("Apple"), "missing argument")
		t.falsy(check("Apple", 3, "extra"), "extra argument")
		t.truthy(Validate.args({})())
		t.falsy(Validate.args({})(1))
	end,
}
