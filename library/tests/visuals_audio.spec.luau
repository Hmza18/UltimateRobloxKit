--!strict
local AudioLogic = require("../src/Visuals/Audio/AudioLogic")
local t = require("./lib/t")

return {
	["ids are normalised"] = function()
		t.equal(AudioLogic.normalizeId(123), "rbxassetid://123")
		t.equal(AudioLogic.normalizeId("123"), "rbxassetid://123")
		t.equal(AudioLogic.normalizeId(" 123 "), "rbxassetid://123")
		t.equal(AudioLogic.normalizeId("rbxassetid://9876543210"), "rbxassetid://9876543210")
		t.equal(AudioLogic.normalizeId(9876543210), "rbxassetid://9876543210")
		t.equal(AudioLogic.normalizeId("https://www.roblox.com/asset/?id=55"), "rbxassetid://55")
		t.equal(
			AudioLogic.normalizeId("rbxasset://sounds/electronicpingshort.wav"),
			"rbxasset://sounds/electronicpingshort.wav"
		)
		for _, bad in { 0, -5, 1.5, "", "abc", "rbxassetid://", "rbxassetid://x", "0", true, {} } :: { any } do
			t.equal(AudioLogic.normalizeId(bad), nil, tostring(bad))
		end
		t.equal(AudioLogic.normalizeId(nil), nil)
	end,
	["register accepts an id or options and applies defaults"] = function()
		local state = AudioLogic.new()
		t.falsy(AudioLogic.isRegistered(state, "coin"))
		local coin = AudioLogic.register(state, "coin", 111) :: AudioLogic.Cue
		t.deepEqual(coin, {
			id = "rbxassetid://111",
			volume = 0.6,
			pitch = 1,
			pitchVariance = 0,
			cooldown = 0.03,
			maxConcurrent = 4,
			group = "sfx",
		})
		local press =
			AudioLogic.register(state, "ui.press", { id = "222", volume = 0.3, maxConcurrent = 2.9 }) :: AudioLogic.Cue
		t.equal(press.group, "ui")
		t.equal(press.volume, 0.3)
		t.equal(press.maxConcurrent, 2)
		AudioLogic.register(state, "music.menu", { id = 5, group = "music" })
		t.deepEqual(AudioLogic.registered(state), { "coin", "music.menu", "ui.press" })
		t.truthy(AudioLogic.isRegistered(state, "coin"))
		AudioLogic.register(state, "coin", nil)
		t.falsy(AudioLogic.isRegistered(state, "coin"))
		t.falsy(AudioLogic.isRegistered(state, 5))
	end,
	["invalid registrations raise"] = function()
		local state = AudioLogic.new()
		local register: any = AudioLogic.register
		for _, options in
			{
				"abc",
				{},
				{ id = 1, volume = 2 },
				{ id = 1, pitch = 0 },
				{ id = 1, cooldown = -1 },
				{ id = 1, pitchVariance = 0.9 },
				{ id = 1, maxConcurrent = 0 },
				{ id = 1, group = "" },
			} :: { any }
		do
			t.throws(function()
				register(state, "x", options)
			end)
		end
		t.throws(function()
			register(state, "", 1)
		end)
		t.equal(#AudioLogic.registered(state), 0)
	end,
	["unregistered cues are silent"] = function()
		local state = AudioLogic.new()
		local play, reason = AudioLogic.decide(state, "coin", 0)
		t.equal(play, nil)
		t.equal(reason, "unregistered")
	end,
	["cooldown"] = function()
		local state = AudioLogic.new()
		AudioLogic.register(state, "tap", { id = 1, cooldown = 0.1, maxConcurrent = 16 })
		t.truthy((AudioLogic.decide(state, "tap", 0)))
		local play, reason = AudioLogic.decide(state, "tap", 0.05)
		t.equal(play, nil)
		t.equal(reason, "cooldown")
		t.truthy((AudioLogic.decide(state, "tap", 0.05, { force = true })), "force ignores the cooldown")
		t.falsy((AudioLogic.decide(state, "tap", 0.1)), "the forced play restarted the cooldown")
		t.truthy((AudioLogic.decide(state, "tap", 0.16)))
	end,
	["concurrency"] = function()
		local state = AudioLogic.new()
		AudioLogic.register(state, "coin", { id = 1, cooldown = 0, maxConcurrent = 2 })
		t.truthy((AudioLogic.decide(state, "coin", 0)))
		t.truthy((AudioLogic.decide(state, "coin", 0)))
		local play, reason = AudioLogic.decide(state, "coin", 0)
		t.equal(play, nil)
		t.equal(reason, "concurrency")
		t.equal(AudioLogic.live(state, "coin"), 2)
		AudioLogic.ended(state, "coin")
		t.truthy((AudioLogic.decide(state, "coin", 0)))
		AudioLogic.ended(state, "coin")
		AudioLogic.ended(state, "coin")
		AudioLogic.ended(state, "coin")
		AudioLogic.ended(state, "never")
		t.equal(AudioLogic.live(state, "coin"), 0, "never negative")
	end,
	["pitch variance is deterministic and bounded"] = function()
		local a, b = AudioLogic.new(), AudioLogic.new()
		for _, state in { a, b } do
			AudioLogic.register(state, "tap", { id = 1, cooldown = 0, pitchVariance = 0.12, maxConcurrent = 16 })
		end
		local distinct: { [number]: boolean } = {}
		local count = 0
		for i = 1, 12 do
			local first = AudioLogic.decide(a, "tap", i) :: AudioLogic.Play
			local second = AudioLogic.decide(b, "tap", i) :: AudioLogic.Play
			t.equal(first.pitch, second.pitch, "same cue and count, same pitch")
			t.truthy(first.pitch >= 0.88 - 1e-9 and first.pitch <= 1.12 + 1e-9)
			if not distinct[first.pitch] then
				distinct[first.pitch] = true
				count += 1
			end
			AudioLogic.ended(a, "tap")
			AudioLogic.ended(b, "tap")
		end
		t.truthy(count >= 10, "plays differ")
		local low, high = 1, -1
		for n = 1, 500 do
			local v = AudioLogic.variation("coin", n)
			low, high = math.min(low, v), math.max(high, v)
			t.equal(v, AudioLogic.variation("coin", n))
		end
		t.truthy(low >= -1 and low < -0.9)
		t.truthy(high <= 1 and high > 0.9)
		t.truthy(AudioLogic.variation("coin", 1) ~= AudioLogic.variation("gem", 1))
		-- No variance: exact pitch; options multiply.
		local state = AudioLogic.new()
		AudioLogic.register(state, "x", { id = 1, pitch = 1.5, cooldown = 0 })
		t.equal((AudioLogic.decide(state, "x", 0) :: AudioLogic.Play).pitch, 1.5)
		t.equal((AudioLogic.decide(state, "x", 0, { pitch = 2 }) :: AudioLogic.Play).pitch, 3)
		local varied = (AudioLogic.decide(state, "x", 0, { pitchVariance = 0.2 }) :: AudioLogic.Play).pitch
		t.truthy(varied ~= 1.5 and varied >= 1.2 and varied <= 1.8)
	end,
	["volume combines cue, option, group and master, and mute silences"] = function()
		local state = AudioLogic.new()
		AudioLogic.register(state, "coin", { id = 1, volume = 0.8, cooldown = 0, maxConcurrent = 16 })
		AudioLogic.register(state, "ui.pop", { id = 2, volume = 0.5, cooldown = 0, maxConcurrent = 16 })
		t.near((AudioLogic.decide(state, "coin", 0) :: AudioLogic.Play).volume, 0.8)
		t.near((AudioLogic.decide(state, "coin", 0, { volume = 0.5 }) :: AudioLogic.Play).volume, 0.4)
		AudioLogic.setVolume(state, "sfx", 0.5)
		t.near((AudioLogic.decide(state, "coin", 0) :: AudioLogic.Play).volume, 0.4)
		t.near((AudioLogic.decide(state, "ui.pop", 0) :: AudioLogic.Play).volume, 0.5, 1e-9, "other groups untouched")
		AudioLogic.setVolume(state, nil, 0.5)
		t.near((AudioLogic.decide(state, "coin", 0) :: AudioLogic.Play).volume, 0.2)
		AudioLogic.setVolume(state, "ui", 7)
		t.equal(AudioLogic.groupVolume(state, "ui"), 1, "clamped")
		t.equal(AudioLogic.groupVolume(state, nil), 0.5)
		t.equal(AudioLogic.groupVolume(state, "music"), 1)
		state.muted = true
		local play, reason = AudioLogic.decide(state, "coin", 1)
		t.equal(play, nil)
		t.equal(reason, "muted")
	end,
	["the documented cue list"] = function()
		local seen: { [string]: boolean } = {}
		for _, cue in AudioLogic.CUES do
			t.falsy(seen[cue], cue .. " listed twice")
			seen[cue] = true
		end
		for _, cue in
			{
				"ui.hover",
				"ui.press",
				"ui.pop",
				"ui.close",
				"tap",
				"coin",
				"gem",
				"error",
				"success",
				"egg.land",
				"egg.wobble",
				"egg.crack",
				"egg.reveal",
				"reward.reveal",
				"level.up",
				"quest.complete",
				"whoosh",
				"impact",
				"pet.happy",
				"food.throw",
				"food.hit",
			}
		do
			t.truthy(seen[cue], cue)
		end
		for _, rarity in { "common", "uncommon", "rare", "epic", "legendary", "mythic", "secret" } do
			t.truthy(seen["rarity." .. rarity], rarity)
		end
		t.equal(AudioLogic.defaultGroup("ui.hover"), "ui")
		t.equal(AudioLogic.defaultGroup("coin"), "sfx")
	end,
}
