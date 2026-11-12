-- "YOUR SUPERMARKET JOURNEY BEGINS": the 35-second intro, as data plus small cue functions.
--
-- Story beats: open the store -> stock a shelf -> welcome a customer -> scan and earn -> reveal.
-- Every shot has one job (named in `why`); positions are set-local studs (see StoreSet: entrance at the
-- origin, shop toward +Z). Shots can be retimed independently; cues reference only ctx helpers.

local TimelineDefinitions = {}

TimelineDefinitions.Duration = 35.0
TimelineDefinitions.Scenes = {
	{ name = "The Grand Opening", t0 = 0, t1 = 6 },
	{ name = "Stocking the Shelves", t0 = 6, t1 = 14 },
	{ name = "The First Customer", t0 = 14, t1 = 21.4 },
	{ name = "Checkout Satisfaction", t0 = 21.4, t1 = 28 },
	{ name = "Your Supermarket Empire", t0 = 28, t1 = 35 },
}

local function v(x, y, z)
	return { x, y, z }
end

TimelineDefinitions.Shots = {
	-- Scene 1 ------------------------------------------------------------------------------------
	{ name = "Establishing", why = "Show the whole storefront, then settle on the entrance and the greeter.",
		t0 = 0, t1 = 6.0, ease = "inOutSine",
		keys = {
			{ u = 0, pos = v(-24, 30, -50), look = v(0, 7, 0), fov = 50 },
			{ u = 0.55, pos = v(-11, 15, -33), look = v(1, 7, 0), fov = 46 },
			{ u = 1, pos = v(2.0, 6.8, -17.5), look = v(2.4, 6.4, 0), fov = 47 },
		} },
	-- Scene 2 ------------------------------------------------------------------------------------
	{ name = "WalkToBox", why = "Introduce the employee and the waiting box in one medium shot.",
		t0 = 6.0, t1 = 7.7, ease = "outSine",
		keys = {
			{ u = 0, pos = v(1.2, 5.4, 2.0), look = v(-7.0, 3.8, 7.0), fov = 46 },
			{ u = 1, pos = v(0.8, 5.2, 3.0), look = v(-3.0, 3.4, 9.0), fov = 44 },
		},
		track = { actor = "Employee", part = "UpperTorso", weight = 0.7, rate = 5 } },
	-- close-ups are keyed in the actor's own space (rel): -Z is the way the actor faces
	{ name = "BoxCloseUp", why = "From the open strip by the shelf, front three-quarter: hands close on the box, then the lift.",
		t0 = 7.7, t1 = 9.6, ease = "inOutSine",
		keys = {
			{ u = 0, pos = v(5.4, 4.4, 11.4), look = v(-3.0, 2.0, 9.6), fov = 32 },
			{ u = 1, pos = v(5.0, 4.8, 11.2), look = v(-3.0, 3.2, 9.4), fov = 34 },
		},
		track = { prop = "ProductBox", weight = 0.35, rate = 5 } },
	{ name = "CarryToShelf", why = "Over the shoulder: where the box is going (the half-empty shelf).",
		t0 = 9.6, t1 = 11.0, ease = "inOutSine",
		keys = {
			{ u = 0, rel = "Employee", pos = v(-2.8, 2.2, 6.2), look = v(0.6, -0.4, -5.0), fov = 50 },
			{ u = 1, rel = "Employee", pos = v(-2.6, 2.0, 5.6), look = v(0.4, -0.5, -4.0), fov = 48 },
		} },
	{ name = "Stocking", why = "Along the shelf from the placing-hand side: face, hand and slots in one frame.",
		t0 = 11.0, t1 = 12.9, ease = "inOutSine",
		keys = {
			{ u = 0, pos = v(-8.6, 5.2, 11.0), look = v(-0.2, 3.2, 11.8), fov = 32 },
			{ u = 1, pos = v(-8.2, 5.4, 10.8), look = v(-0.2, 3.5, 11.9), fov = 30 },
		},
		track = { actor = "Employee", part = "RightHand", weight = 0.25, rate = 4 } },
	{ name = "ShelfHero", why = "Payoff: the shelf fills itself in a satisfying cascade.",
		t0 = 12.9, t1 = 14.0, ease = "outSine",
		keys = {
			{ u = 0, pos = v(8.2, 5.2, 5.0), look = v(1.0, 3.0, 12.4), fov = 44 },
			{ u = 1, pos = v(6.6, 5.4, 5.4), look = v(-1.4, 3.0, 12.4), fov = 42 },
		} },
	-- Scene 3 ------------------------------------------------------------------------------------
	{ name = "CustomerEnters", why = "Track the first customer through the open doors.",
		t0 = 14.0, t1 = 17.1, ease = "inOutSine",
		keys = {
			{ u = 0, pos = v(7.0, 5.6, 9.6), look = v(-1.2, 4.0, -2.0), fov = 48 },
			{ u = 1, pos = v(6.0, 5.4, 9.2), look = v(-0.2, 3.8, 7.0), fov = 46 },
		},
		track = { actor = "Customer", part = "Head", weight = 0.6, rate = 4 } },
	{ name = "Browsing", why = "Along the shelf, basket side: the customer weighing up the stocked shelf.",
		t0 = 17.1, t1 = 18.7, ease = "inOutSine",
		keys = {
			{ u = 0, pos = v(8.8, 5.4, 10.8), look = v(0.4, 3.8, 11.4), fov = 34 },
			{ u = 1, pos = v(8.4, 5.2, 10.6), look = v(0.4, 3.6, 11.4), fov = 32 },
		} },
	{ name = "Selection", why = "Along the shelf, reaching side: hand takes the product, follow it into the basket.",
		t0 = 18.7, t1 = 20.6, ease = "inOutSine",
		keys = {
			{ u = 0, pos = v(-8.6, 5.0, 11.0), look = v(0.2, 3.0, 11.4), fov = 30 },
			{ u = 1, pos = v(-8.2, 4.8, 10.8), look = v(0.6, 2.4, 10.6), fov = 32 },
		},
		track = { actor = "Customer", part = "RightHand", weight = 0.3, rate = 4 } },
	{ name = "ToCheckout", why = "Swing with the customer toward the counter.",
		t0 = 20.6, t1 = 21.8, ease = "inOutSine", blend = 0.35,
		keys = {
			{ u = 0, pos = v(-2.4, 6.0, 4.6), look = v(1.0, 3.8, 9.0), fov = 48 },
			{ u = 1, pos = v(1.6, 6.2, 0.4), look = v(6.0, 3.6, 5.0), fov = 48 },
		},
		track = { actor = "Customer", part = "UpperTorso", weight = 0.8, rate = 5 } },
	-- Scene 4 ------------------------------------------------------------------------------------
	{ name = "Approach", why = "Behind the customer, long lens: the counter and a ready cashier ahead.",
		t0 = 21.8, t1 = 24.1, ease = "inOutSine",
		keys = {
			{ u = 0, pos = v(-2.2, 6.6, 6.8), look = v(9.0, 3.6, 4.4), fov = 34 },
			{ u = 1, pos = v(-1.2, 6.2, 6.2), look = v(11.0, 3.6, 5.0), fov = 30 },
		},
		track = { actor = "Customer", part = "Head", weight = 0.45, rate = 4 } },
	{ name = "ScannerClose", why = "Steep over the customer's head: grab, sweep, beep and flash on the counter.",
		t0 = 24.1, t1 = 25.8, ease = "inOutSine",
		keys = {
			{ u = 0, pos = v(12.8, 10.5, 2.4), look = v(11.2, 2.8, 5.8), fov = 44 },
			{ u = 1, pos = v(12.4, 10.2, 2.7), look = v(10.9, 2.8, 5.8), fov = 41 },
		},
		track = { actor = "Cashier", part = "RightHand", weight = 0.2, rate = 4 } },
	{ name = "Earnings", why = "High behind the cashier: the second scan, the money and the happy customer.",
		t0 = 25.8, t1 = 28.0, ease = "inOutSine",
		keys = {
			{ u = 0, pos = v(12.8, 10.5, 14.5), look = v(11.0, 3.2, 4.6), fov = 32 },
			{ u = 1, pos = v(12.4, 10.0, 13.8), look = v(11.0, 3.2, 4.4), fov = 30 },
		},
		shake = { amp = 0.02, rot = 0.15, freq = 0.8 } },
	-- Scene 5 ------------------------------------------------------------------------------------
	{ name = "Reveal", why = "From the checkout, an accelerating pull back into the busy shop.",
		t0 = 28.0, t1 = 36.0, ease = "inOutSine",
		keys = {
			{ u = 0, pos = v(14.5, 11.0, 0.4), look = v(11.2, 3.0, 6.0), fov = 34 },
			{ u = 0.18, pos = v(13.6, 9.6, 0.4), look = v(9.0, 3.4, 8.0), fov = 44 },
			{ u = 0.6, pos = v(-14.5, 12.2, 0.8), look = v(3.5, 3.4, 15.5), fov = 62 },
			{ u = 1, pos = v(-13.6, 12.6, 1.6), look = v(3.0, 3.6, 16.0), fov = 60 },
		} },
}

-- Cast: role -> starting mark and starting clip.
TimelineDefinitions.Cast = {
	{ name = "Employee", look = "Employee", mark = "EmployeeGreet", clip = "SM_Idle" },
	{ name = "Cashier", look = "Cashier", mark = "Cashier", clip = "SM_CashierIdle" },
	{ name = "Customer", look = "Customer", mark = "CustomerOutside", clip = "SM_BasketIdle" },
	{ name = "ShopperA", look = "Shopper", mark = "ShopperA", clip = "SM_BasketIdle", optional = true },
	{ name = "ShopperB", look = "Shopper2", mark = "ShopperB", clip = "SM_BasketIdle", optional = true },
}

-- Cues. ctx: see Cinematic.lua (actors, set, vfx, ui, audio, helpers). Times in seconds.
function TimelineDefinitions.cues(ctx)
	local A = ctx.actors
	local C = ctx.contacts
	local cues = {}
	local function at(t, name, run)
		cues[#cues + 1] = { t = t, name = name, run = run }
	end
	local state = ctx.state

	-- 0:00 THE GRAND OPENING ------------------------------------------------------------------------
	at(0.0, "open:fadeIn", function()
		ctx.ui:fadeTo(1, 0.9, Color3.new(1, 1, 1))
		ctx.ui:letterbox(true, 0.8)
		ctx.audio:play("Music", { looped = true })
	end)
	at(1.2, "open:signLights", function()
		ctx.vfx:signGlow(ctx.set, 0.6)
		ctx.audio:play("StoreOpen")
	end)
	at(2.0, "open:doors", function()
		ctx:openDoors(0.9)
	end)
	at(2.4, "open:wave", function()
		A.Employee:play("SM_Wave", { fade = 0.2, onEnd = function()
			A.Employee:play("SM_Idle", { fade = 0.35 })
		end })
	end)
	at(2.8, "open:celebrate", function()
		local o = ctx.set.origin
		ctx.vfx:confettiAt(o * CFrame.new(-5.2, 1.2, -2.4))
		ctx.vfx:confettiAt(o * CFrame.new(5.2, 1.2, -2.4))
		ctx.ui:showBadge("GRAND OPENING!", 2.2)
	end)

	-- 0:06 STOCKING THE SHELVES ----------------------------------------------------------------------
	at(6.0, "stock:cut", function()
		ctx.ui:flash(0.22)
		A.Employee:place(ctx:mark("EmployeeBackroom"))
		A.Employee:walk({ ctx:mark("EmployeeAtBox").Position }, { clip = "SM_Walk", arrive = "SM_Idle", arriveBy = 1.65, face = ctx:dir(0, 1) })
	end)
	at(7.75, "stock:lift", function()
		A.Employee:play("SM_BoxLift", { fade = 0.25, onMarker = function(m)
			if m == "Grab" then
				A.Employee:hold(ctx.props.ProductBox, "RightHand", nil, true)
				ctx.audio:play("BoxHandle", { at = ctx.props.ProductBox.Position })
			end
		end })
	end)
	at(9.6, "stock:carry", function()
		A.Employee:walk({ ctx:point(-1.6, 9.0), ctx:point(0, 10.55) }, { clip = "SM_CarryWalk", arriveBy = 1.3, face = ctx:dir(0, 1) })
	end)
	at(11.05, "stock:stock", function()
		local stocker = ctx:mark("EmployeeStock")
		local keys = { "TamsCereal", "BlueFlour", "InstantNoodles" }
		state.handSlots = {}
		local current
		A.Employee:play("SM_Stock", { fade = 0.3, onMarker = function(m)
			if m == "BoxToLeft" then
				A.Employee:hold(ctx.props.ProductBox, "LeftHand", nil, true)
			elseif m:sub(1, 4) == "Take" then
				local i = tonumber(m:sub(5))
				local prop, primary, height = ctx:product(keys[i], "Stock" .. i)
				primary.CFrame = ctx.props.ProductBox.CFrame * CFrame.new(0, 0.2, 0)
				current = { prop = prop, primary = primary, height = height, i = i }
				ctx:grab(A.Employee, prop, primary, "RightHand", 0.12)
			elseif m:sub(1, 5) == "Place" and current then
				local slot = ctx:slotFor(stocker, C.StockSlots[current.i], current.height)
				state.handSlots[current.i] = { cf = slot, prop = current.prop, primary = current.primary, height = current.height }
				ctx:place(A.Employee, current.prop, current.primary, slot, 0.22)
				current = nil
			end
		end })
	end)
	at(13.15, "stock:cascade", function()
		ctx:cascadeShelf(0.05) -- every drop lands before the 14.0 cut
	end)

	-- 0:14 THE FIRST CUSTOMER ------------------------------------------------------------------------
	at(14.0, "customer:cut", function()
		-- tidy the stock scene: the box goes down by the shelf, the employee steps aside
		local box = ctx.props.ProductBox
		A.Employee:release(box)
		box.CFrame = ctx.set.origin * CFrame.new(-5.6, 0.45, 10.9) * CFrame.Angles(0, math.rad(20), 0)
		A.Employee:place(ctx:mark("EmployeeAside"))
		A.Employee:play("SM_Idle", { fade = 0 })
		-- the customer walks in toward the product the employee placed (slot 2)
		local target = state.handSlots and state.handSlots[2]
		local pick = ctx:standFor(target and target.cf or ctx.set.origin * CFrame.new(0.1, 2.6, 12.4), C.PickWrist, ctx:dir(0, 1))
		state.pickMark = pick
		A.Customer:place(ctx:mark("CustomerOutside") * CFrame.new(0, 0, -6))
		A.Customer:walk({ ctx:point(-1.3, -1.0), Vector3.new(pick.Position.X, 0, pick.Position.Z - 2.2), pick.Position },
			{ clip = "SM_BasketWalk", arrive = "SM_BasketIdle", arriveBy = 3.0, face = ctx:dir(0, 1) })
	end)
	at(17.2, "customer:browse", function()
		A.Customer:play("SM_Browse", { fade = 0.25 })
	end)
	at(18.7, "customer:pick", function()
		local target = state.handSlots and state.handSlots[2]
		A.Customer:play("SM_ReachPick", { fade = 0.25, onMarker = function(m)
			if m == "Grab" and target then
				ctx:grab(A.Customer, target.prop, target.primary, "RightHand", 0.1)
				state.picked = target
			elseif m == "Drop" and state.picked then
				ctx:intoBasket(A.Customer, state.picked.prop, state.picked.primary, Vector3.new(0.25, 0.35, 0))
				ctx.audio:play("BasketDrop")
			end
		end, onEnd = function()
			A.Customer:play("SM_BasketIdle", { fade = 0.3 })
		end })
	end)
	at(20.95, "customer:toCheckout", function()
		local m = ctx:mark("CustomerCheckout")
		A.Customer:walk({ ctx:point(3.5, 4.6), m.Position }, { clip = "SM_BasketWalk", arrive = "SM_BasketIdle", arriveBy = 2.9, face = ctx:dir(0, 1) })
	end)

	-- 0:21 CHECKOUT SATISFACTION ----------------------------------------------------------------------
	local function scan(item, earning, last)
		A.Cashier:play("SM_Scan", { fade = 0.2, onMarker = function(m)
			if m == "Grab" then
				ctx:grab(A.Cashier, item.prop, item.primary, "RightHand", 0.1)
			elseif m == "Beep" then
				ctx.vfx:scannerPulse(ctx.set)
				ctx.audio:play("ScannerBeep", { at = ctx.set.parts.scanner.Position })
				ctx.vfx:moneyPopup(ctx.set.parts.scanner.Position + Vector3.new(0, 1.6, 0), earning, ctx.config.Font)
				ctx:addToTotal(earning)
			elseif m == "Release" then
				ctx:intoBag(A.Cashier, item.prop, item.primary)
				if last then
					ctx:after(0.15, function()
						ctx.audio:play("CheckoutSuccess")
						ctx.vfx:confettiAt(ctx.set.parts.scanner.CFrame * CFrame.new(0, 0.3, 0), 0.5)
					end)
				end
			end
		end, onEnd = function()
			A.Cashier:play("SM_CashierIdle", { fade = 0.3 })
		end })
	end
	at(23.95, "checkout:unload1", function()
		state.item1 = ctx:toCounter(A.Customer, "basketItem", 0.45)
	end)
	at(24.2, "checkout:scan1", function()
		if state.item1 then
			scan(state.item1, ctx.config.EarningsText[1], false)
		end
	end)
	at(25.9, "checkout:unload2", function()
		state.item2 = ctx:toCounter(A.Customer, "picked", 0.45)
	end)
	at(26.2, "checkout:scan2", function()
		if state.item2 then
			scan(state.item2, ctx.config.EarningsText[2] or ctx.config.EarningsText[1], true)
		end
	end)

	-- 0:28 YOUR SUPERMARKET EMPIRE ------------------------------------------------------------------------
	at(28.2, "empire:life", function()
		if A.ShopperA then
			A.ShopperA:walk({ ctx:point(-7.0, 14.3) }, { clip = "SM_BasketWalk", arrive = "SM_BasketIdle", arriveBy = 4.5, face = ctx:dir(0, 1) })
		end
		if A.ShopperB then
			A.ShopperB:play("SM_Browse", { fade = 0.3, onEnd = function()
				A.ShopperB:play("SM_BasketIdle", { fade = 0.3 })
			end })
		end
		A.Customer:walk({ ctx:point(3.0, 2.0), ctx:point(-1.0, -3.0) }, { clip = "SM_BasketWalk", arrive = "SM_BasketIdle", arriveBy = 5.0 })
		A.Employee:play("SM_Idle", { fade = 0.3 })
	end)
	at(30.0, "empire:revealLight", function()
		ctx.vfx:reveal()
	end)
	at(30.3, "empire:cheer", function()
		A.Cashier:play("SM_Cheer", { fade = 0.2, onEnd = function()
			A.Cashier:play("SM_CashierIdle", { fade = 0.35 })
		end })
		ctx:after(0.25, function()
			A.Employee:play("SM_Cheer", { fade = 0.2, onEnd = function()
				A.Employee:play("SM_Idle", { fade = 0.35 })
			end })
		end)
	end)
	at(30.8, "empire:revealSound", function()
		ctx.audio:play("FinalReveal")
	end)
	at(31.0, "empire:title", function()
		ctx.ui:showTitle()
	end)
	at(34.3, "empire:fadeOut", function()
		ctx.ui:fadeTo(0, 0.6, Color3.new(1, 1, 1))
	end)
	at(TimelineDefinitions.Duration, "end", function() end)
	return cues
end

return TimelineDefinitions
