--!strict
-- Pet preview: a clone of a pet model inside a ViewportFrame with its own Camera, framed with
-- CameraLogic.fitDistance, idling on a slow turntable. Used by the selection screen, inventories
-- and shop cards.
--
-- ViewportFrame limits (Roblox): no particles, beams or trails render inside it, and lighting is
-- only Ambient, LightColor and LightDirection.
--
-- Used through Pets.preview; see README.md. NOT run in Studio.

local CameraLogic = require("../Camera/CameraLogic")
local PetAnimator = require("./PetAnimator")

export type Options = {
	turntable: number?, -- degrees per second (default 24; 0 keeps it still)
	fov: number?, -- default 35
	padding: number?, -- fit margin (default 1.2)
	angle: number?, -- camera yaw around the pet; 180 is straight on (default 160)
	elevation: number?, -- degrees above the horizon (default 10)
	clone: boolean?, -- false moves the given model in instead of cloning it (default true)
	ambient: Color3?,
	lightColor: Color3?,
	lightDirection: Vector3?,
	animator: PetAnimator.Options?,
}

export type Preview = {
	model: Model,
	camera: Camera,
	animator: PetAnimator.PetAnimator,
	react: (self: Preview, id: string, options: PetAnimator.ReactOptions?) -> (),
	setHover: (self: Preview, hovered: boolean) -> (),
	setSelected: (self: Preview, selected: boolean) -> (),
	refit: (self: Preview) -> (),
	destroy: (self: Preview) -> (),
}

local PetPreview = {}

function PetPreview.new(viewport: ViewportFrame, model: Model, options: Options?): Preview
	assert(typeof(viewport) == "Instance" and viewport:IsA("ViewportFrame"), "Pets.preview expects a ViewportFrame")
	local opts: Options = options or {}
	-- A WorldModel lets AnimationTracks play inside the viewport.
	local world = Instance.new("WorldModel")
	world.Name = "PetPreviewWorld"
	world.Parent = viewport
	local pet = if opts.clone == false then model else model:Clone()
	pet:PivotTo(CFrame.new())
	pet.Parent = world

	local boxCFrame, size = pet:GetBoundingBox()
	local centre = boxCFrame.Position
	local radius = math.max(0.1, size.Magnitude / 2)

	local camera = Instance.new("Camera")
	camera.Name = "PetPreviewCamera"
	camera.FieldOfView = opts.fov or 35
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	if opts.ambient then
		viewport.Ambient = opts.ambient
	end
	if opts.lightColor then
		viewport.LightColor = opts.lightColor
	end
	if opts.lightDirection then
		viewport.LightDirection = opts.lightDirection
	end

	local function refit()
		local absolute = viewport.AbsoluteSize
		local aspect = if absolute.X > 0 and absolute.Y > 0 then absolute.X / absolute.Y else 1
		local pose = CameraLogic.focusPose({ centre.X, centre.Y, centre.Z }, {
			distance = CameraLogic.fitDistance(radius, camera.FieldOfView, aspect, opts.padding or 1.2),
			angle = opts.angle or 160,
			elevation = opts.elevation or 10,
		})
		local from, to = pose.position, pose.lookAt
		if from and to then
			camera.CFrame = CFrame.lookAt(Vector3.new(from[1], from[2], from[3]), Vector3.new(to[1], to[2], to[3]))
		end
	end
	refit()
	local resized = viewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)

	local animatorOptions: PetAnimator.Options = table.clone(opts.animator or {}) :: any
	if animatorOptions.turntable == nil then
		animatorOptions.turntable = opts.turntable or 24
	end
	animatorOptions.everyFrame = true -- the preview is what the player is looking at
	local animator = PetAnimator.new(pet, animatorOptions)
	local destroyed = false

	return {
		model = pet,
		camera = camera,
		animator = animator,
		react = function(_self: Preview, id: string, reactOptions: PetAnimator.ReactOptions?)
			if not destroyed then
				animator:react(id, reactOptions)
			end
		end,
		setHover = function(_self: Preview, hovered: boolean)
			if not destroyed then
				animator:setHover(hovered)
			end
		end,
		setSelected = function(_self: Preview, selected: boolean)
			if not destroyed then
				animator:setSelected(selected)
			end
		end,
		refit = function(_self: Preview)
			if not destroyed then
				refit()
			end
		end,
		destroy = function(_self: Preview)
			if destroyed then
				return
			end
			destroyed = true
			resized:Disconnect()
			animator:destroy(false)
			if opts.clone == false then
				pet.Parent = nil -- the caller's model is handed back, not destroyed
			end
			world:Destroy()
			camera:Destroy()
		end,
	}
end

return PetPreview
