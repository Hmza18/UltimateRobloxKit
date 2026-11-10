--!strict
-- SpinWheel screen: a prize wheel. The spin button raises SpinRequested; the server picks the
-- result and the game calls screen:spin(index). The wheel then winds up, spins, slows down and
-- settles on that segment (ScreensLogic.spinPlan / spinAngle), raises Landed(index) and reveals
-- the segment's reward with Rewards.reveal. The wheel never chooses a result.
--
-- The wheel is drawn from Frames and rotations: a round disc, a divider per boundary, and for
-- each segment an arm (a full-size frame turned to the segment's centre) carrying its petal.
--
-- NOT run in Studio: see README.md.

local Host = require("../Runtime/Host")
local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")
local Style = require("../../UI/Style/Style")

local Game = ScreenKit.Game
local UI = ScreenKit.UI

local FOOTER = 64
local PALETTES = { "red", "orange", "yellow", "green", "teal", "blue", "purple", "pink" }

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local wheel = ScreensLogic.wheel(props.segments)
	local window = shell:window({ title = props.title, headerPalette = "purple", scroll = false })
	local content = window.content
	for _, child in ipairs(content:GetChildren()) do
		if child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	local outline = hex(Style.outlineColor(shell.style))

	local disc = Instance.new("Frame")
	disc.Name = "Wheel"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.52)
	disc.BackgroundColor3 = hex(Style.surface(shell.style, "dark").top)
	disc.BorderSizePixel = 0
	disc.Parent = content
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = disc
	local rim = Instance.new("UIStroke")
	rim.Thickness = Style.outline(shell.style, "heavy") + 2
	rim.Color = outline
	rim.Parent = disc

	-- The pointer does not turn with the wheel: a small diamond at the top.
	local pointer = Instance.new("Frame")
	pointer.Name = "Pointer"
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Size = UDim2.fromOffset(26, 26)
	pointer.Rotation = 45
	pointer.BackgroundColor3 = hex(Style.palette(shell.style, "gold").top)
	pointer.BorderSizePixel = 0
	pointer.ZIndex = 5
	pointer.Parent = content
	local pointerStroke = Instance.new("UIStroke")
	pointerStroke.Thickness = Style.outline(shell.style, "thick")
	pointerStroke.Color = outline
	pointerStroke.Parent = pointer

	local petals: { Frame } = {}
	local parts: { any } = {}
	local function clearSegments()
		for _, part in ipairs(parts) do
			part:destroy()
		end
		table.clear(parts)
		table.clear(petals)
		for _, child in ipairs(disc:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
	end
	shell.trove:Add(clearSegments)

	local function buildSegments()
		clearSegments()
		for _, segment in ipairs(wheel.segments) do
			local data: any = if type(segment.data) == "table" then segment.data else { text = tostring(segment.data) }
			-- Divider on the segment's leading edge.
			local divider = Instance.new("Frame")
			divider.Name = "Divider"
			divider.AnchorPoint = Vector2.new(0.5, 0.5)
			divider.Position = UDim2.fromScale(0.5, 0.5)
			divider.Size = UDim2.fromScale(1, 1)
			divider.BackgroundTransparency = 1
			divider.Rotation = segment.start
			divider.Parent = disc
			local line = Instance.new("Frame")
			line.AnchorPoint = Vector2.new(0.5, 0)
			line.Position = UDim2.fromScale(0.5, 0)
			line.Size = UDim2.new(0, 3, 0.5, 0)
			line.BackgroundColor3 = outline
			line.BorderSizePixel = 0
			line.Parent = divider
			-- Arm turned to the segment's centre, with the petal near the rim.
			local arm = Instance.new("Frame")
			arm.Name = "Arm" .. tostring(segment.index)
			arm.AnchorPoint = Vector2.new(0.5, 0.5)
			arm.Position = UDim2.fromScale(0.5, 0.5)
			arm.Size = UDim2.fromScale(1, 1)
			arm.BackgroundTransparency = 1
			arm.Rotation = segment.centre
			arm.Parent = disc
			-- The petal is as wide as the segment's chord at two thirds of the radius.
			local chord = 2 * 0.33 * math.tan(math.rad(math.min(segment.sweep, 120) / 2))
			local swatch = Style.palette(shell.style, data.palette or PALETTES[(segment.index - 1) % #PALETTES + 1])
			local petal = Instance.new("Frame")
			petal.Name = "Petal"
			petal.AnchorPoint = Vector2.new(0.5, 0)
			petal.Position = UDim2.fromScale(0.5, 0.04)
			petal.Size = UDim2.fromScale(math.clamp(chord * 0.86, 0.1, 0.42), 0.3)
			petal.BackgroundColor3 = Color3.new(1, 1, 1)
			petal.BorderSizePixel = 0
			petal.Parent = arm
			local gradient = Instance.new("UIGradient")
			gradient.Rotation = 90
			gradient.Color = ColorSequence.new(hex(swatch.top), hex(swatch.bottom))
			gradient.Parent = petal
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.25, 0)
			corner.Parent = petal
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = Style.outline(shell.style, "regular")
			stroke.Color = outline
			stroke.Parent = petal
			local image = Instance.new("ImageLabel")
			image.BackgroundTransparency = 1
			image.AnchorPoint = Vector2.new(0.5, 0)
			image.Position = UDim2.fromScale(0.5, 0.06)
			image.Size = UDim2.fromScale(0.7, 0.5)
			image.ScaleType = Enum.ScaleType.Fit
			image.Parent = petal
			ScreenKit.icon(image, data.icon or (if data.image == nil then "gift-color" else nil), data.image)
			table.insert(
				parts,
				Game.GameText.new({
					style = shell.styleName,
					parent = petal,
					text = tostring(data.text or data.amount or ""),
					role = "caption",
					size = UDim2.fromScale(1, 0.38),
					position = UDim2.fromScale(0, 0.6),
				})
			)
			petals[segment.index] = petal
		end
	end

	local footer = window.setFooter(FOOTER)
	local spinButton = shell:button(footer, {
		premium = true,
		name = "Spin",
		text = props.spinText,
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.new(0.7, 0, 0, FOOTER - 8),
	})

	local rotation = 0
	local spinning = false
	local stopJob: (() -> ())? = nil
	local reveal: any = nil

	local function refreshButton()
		local spins = shell.props.spins
		local available = spins == nil or spins > 0
		local text = shell.props.spinText
		if type(spins) == "number" then
			text = string.format("%s (%d)", text, spins)
		end
		spinButton:update({ enabled = available and not spinning, text = text })
	end

	local function landed(index: number)
		spinning = false
		refreshButton()
		local petal: Frame? = petals[index]
		if petal ~= nil then
			UI.animate(petal, "UpgradePulse")
		end
		UI.animate(pointer, "Bounce")
		shell:fire("Landed", index)
		local segment = wheel.segments[index]
		local data: any = if segment and type(segment.data) == "table" then segment.data else nil
		if shell.props.reveal == false or data == nil or data.reward == nil then
			return
		end
		-- Show what was won (already granted by the server) with the reward reveal.
		local ok, Rewards = pcall(function(): any
			return require("../Rewards/Rewards")
		end)
		if not ok then
			return
		end
		local parent = if shell.gui then shell.gui.Parent else shell.root
		reveal = Rewards.reveal(data.rarity or data.reward.rarity or "Common", data.reward, { parent = parent })
		reveal.Completed:Once(function(dismissed: boolean)
			reveal = nil
			if dismissed then
				shell:fire("Claimed", index)
			end
		end)
	end

	local function spin(index: number, options: { [string]: any }?): boolean
		if spinning or wheel.segments[index] == nil then
			return false
		end
		local opts: { [string]: any } = options or {}
		local target = ScreensLogic.landingAngle(wheel, index, {
			from = rotation,
			turns = opts.turns,
			offset = opts.offset,
		}) :: number
		local plan = ScreensLogic.spinPlan(rotation, target, {
			duration = opts.duration,
			sweep = wheel.segments[index].sweep,
			reducedMotion = Host.settings().reducedMotion,
		})
		spinning = true
		refreshButton()
		local elapsed = 0
		stopJob = Host.clock:add(function(dt: number): boolean?
			elapsed += dt
			local angle, phase = ScreensLogic.spinAngle(plan, elapsed)
			rotation = angle
			disc.Rotation = angle
			if phase == "done" then
				stopJob = nil
				-- Keep the number small; the pointer sees the same segment.
				rotation = angle % 360
				disc.Rotation = rotation
				landed(index)
				return false
			end
			return nil
		end)
		return true
	end

	shell.trove:Add(function()
		if stopJob then
			stopJob()
		end
		if reveal ~= nil then
			reveal.cancel()
		end
	end)
	shell.trove:Add(spinButton.Activated:Connect(function()
		if not spinning then
			shell:fire("SpinRequested")
		end
	end))

	shell:onLayout(function(_env: ScreensLogic.Env)
		local size = content.AbsoluteSize
		local width, height = size.X, size.Y
		if width <= 0 then
			local body = window.body()
			width, height = body.content.w, body.content.h - FOOTER
		end
		local side = math.floor(math.max(120, math.min(width, height - 30) - 16))
		disc.Size = UDim2.fromOffset(side, side)
		pointer.Position = UDim2.new(0.5, 0, 0.52, -math.floor(side / 2) - 4)
	end)

	buildSegments()
	refreshButton()
	shell:focusables({ spinButton.Instance })
	shell.onOpened = function()
		UI.animate(disc, "ScaleIn")
	end

	return {
		update = function(partial: { [string]: any })
			if partial.title ~= nil then
				window.setTitle(partial.title)
			end
			if partial.segments ~= nil and not spinning then
				wheel = ScreensLogic.wheel(shell.props.segments)
				rotation = 0
				disc.Rotation = 0
				buildSegments()
			end
			refreshButton()
		end,
		methods = {
			spin = spin,
			isSpinning = function(): boolean
				return spinning
			end,
		},
	}
end
