---
name: roblox-camera-input
description: Camera and input on the Roblox client - Scriptable cameras, frame-rate independent CFrame lerp, camera shake, ContextActionService and UserInputService, the Input Action System (InputContext, InputAction, InputBinding), cross-platform keyboard/mouse, touch buttons and gamepad, PreferredInput detection, shift lock and first person. Use when adding controls or keybinds, mobile buttons, gamepad support, cutscene or top-down cameras, or when input works on one device but not another.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [camera, cameratype scriptable, camera shake, contextactionservice, userinputservice, input action system, gamepad, touch controls, keybind, shift lock, first person, preferredinput]
  depends: [luau-language, roblox-architecture, roblox-ui-systems]
---

# Roblox camera and input

## When to use

- Adding an action (sprint, interact, ability) that must work on keyboard, touch and gamepad.
- Custom cameras: cutscene, top-down, over-the-shoulder, fixed rooms, shake on hit.
- Showing the right button prompts for the device the player is using.
- Shift lock or forced first person.

When not to use: camera shake, FOV punches, focus, orbit and reveal cinematics that must restore the camera afterwards (use `uvk-camera-effects` when the kit's `Visuals` module is installed); on-screen HUD layout (use `roblox-ui-systems`), server validation of what the input triggers (use `roblox-networking`).

## Inputs

- The action list: name, default keyboard key, gamepad button, whether it needs a touch button, hold vs tap.
- Camera mode per game state (exploring, cutscene, menu).

## Workflow

1. **All input and camera code runs in LocalScripts / client controllers.** The server never reads input; it receives intent through remotes.
2. **Bind actions, not keys.** Use one of:
   - **ContextActionService (CAS)**: `BindAction(name, handler, createTouchButton, ...inputs)`, with `BindActionAtPriority` for overrides. Mature, gives free touch buttons.
   - **Input Action System**: `InputContext` > `InputAction` > `InputBinding` instances, editable in Studio, with per-context priority and sinking. Check creator docs for its current release status and API before adopting; it is newer and its API has changed during rollout.
   - **UserInputService (UIS)** for raw events: `InputBegan`, `InputChanged`, `InputEnded`, mouse delta, touch gestures. Always respect `gameProcessedEvent` (true when the player is typing in chat or a TextBox).
3. **Adapt to the device** with `UserInputService.PreferredInput` (an `Enum.PreferredInput` value: keyboard and mouse, gamepad or touch) and its change signal, instead of guessing from `TouchEnabled`. Fall back to `GetLastInputType()` / `LastInputTypeChanged` if PreferredInput is not available in your engine version (verify in creator docs).
4. **Set the camera mode** with `workspace.CurrentCamera.CameraType`: `Custom` for the default follow camera, `Scriptable` when your script owns `Camera.CFrame` fully. Restore `Custom` and `CameraSubject = humanoid` afterwards.
5. **Update scripted cameras with `RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, fn)`** so they run after the default camera scripts, and unbind when done.

### Cross-platform sprint with CAS, plus a scripted camera with shake

```luau
--!strict
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- 1. Sprint: keyboard LeftShift, gamepad left stick press, and a touch button.
local WALK, RUN = 16, 26

local function onSprint(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Cosmetic/local speed only; the server should cap WalkSpeed and stamina.
		humanoid.WalkSpeed = if state == Enum.UserInputState.Begin then RUN else WALK
	end
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction("Sprint", onSprint, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
ContextActionService:SetTitle("Sprint", "Run")
ContextActionService:SetPosition("Sprint", UDim2.new(1, -170, 1, -110))

-- 2. Device-aware prompts
local function refreshPrompts()
	local ok, preferred = pcall(function()
		return (UserInputService :: any).PreferredInput
	end)
	local device = if ok and preferred then preferred.Name else UserInputService:GetLastInputType().Name
	player:SetAttribute("InputDevice", device)   -- UI controllers read this to swap icons
end
refreshPrompts()
UserInputService.LastInputTypeChanged:Connect(refreshPrompts)
pcall(function() -- only succeeds where the PreferredInput property exists
	UserInputService:GetPropertyChangedSignal("PreferredInput" :: any):Connect(refreshPrompts)
end)

-- 3. Scripted camera that follows a focus point with smoothing and trauma-based shake
local focus: BasePart? = nil
local offset = Vector3.new(0, 30, 20)   -- top-down-ish
local trauma = 0                         -- 0..1, decays over time
local SMOOTH = 8

local function shake(amount: number)
	trauma = math.clamp(trauma + amount, 0, 1)
end

local function update(dt: number)
	if not focus then
		return
	end
	local target = CFrame.lookAt(focus.Position + offset, focus.Position)
	local alpha = 1 - math.exp(-SMOOTH * dt)               -- frame-rate independent
	local cf = camera.CFrame:Lerp(target, alpha)

	if trauma > 0 then
		local t = os.clock() * 25
		local s = trauma * trauma                            -- squared feels better
		local rx = math.noise(t, 0, 0) * 0.04 * s
		local ry = math.noise(0, t, 0) * 0.04 * s
		local rz = math.noise(0, 0, t) * 0.06 * s
		cf *= CFrame.Angles(rx, ry, rz)
		trauma = math.max(0, trauma - dt * 1.5)
	end
	camera.CFrame = cf
end

local function startTopDown(part: BasePart)
	focus = part
	camera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep("TopDownCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

local function stopTopDown()
	RunService:UnbindFromRenderStep("TopDownCamera")
	focus = nil
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

return { startTopDown = startTopDown, stopTopDown = stopTopDown, shake = shake }
```

### Input Action System sketch

```luau
--!strict
-- Verify class and property names in creator docs before use; the system is newer than CAS.
local context = Instance.new("InputContext")
context.Name = "Gameplay"
local action = Instance.new("InputAction")
action.Name = "Interact"
action.Parent = context
local key = Instance.new("InputBinding")
key.KeyCode = Enum.KeyCode.E
key.Parent = action
local pad = Instance.new("InputBinding")
pad.KeyCode = Enum.KeyCode.ButtonX
pad.Parent = action
context.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts")

action.Pressed:Connect(function()
	print("interact")
end)
```

Disable whole contexts (`context.Enabled = false`) for menus instead of unbinding actions one by one.

### Platform notes

- **Touch**: CAS touch buttons appear only on touch devices. Keep them away from the thumbstick (bottom left) and jump button (bottom right). Test with Studio's Device Emulator.
- **Gamepad**: every action needs a button; menus need `GuiService.SelectedObject` navigation (see `roblox-ui-systems`). Use `UserInputService:GetStringForKeyCode` or images for prompts.
- **Mouse**: `UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter` each frame while needed (the default camera may reset it); `MouseIconEnabled = false` to hide the cursor.
- **Shift lock**: allowed via `StarterPlayer.EnableMouseLockOption`. For a forced over-the-shoulder camera, set `LockCenter`, rotate the character to the camera yaw, and offset with `Humanoid.CameraOffset`.
- **First person**: `player.CameraMode = Enum.CameraMode.LockFirstPerson`, or limit with `CameraMinZoomDistance`/`CameraMaxZoomDistance` (set on `StarterPlayer` or the player).

## Outputs

- `InputController` (action table and bindings), `CameraController` (modes, shake), device attribute for UI.

## Validation

1. Studio Device Emulator: test a phone, a tablet and a console profile. Each action works and touch buttons do not overlap default controls.
2. Connect a gamepad (or emulate one): every action reachable, menus navigable.
3. Type in chat while pressing bound keys: actions do not fire (`gameProcessedEvent` respected, CAS handles this automatically).
4. Cap FPS at 30 and 240 (Studio frame rate settings): camera smoothing and shake feel the same.
5. Exit every scripted camera mode: the default camera follows the character again.

## Pitfalls

- **Ignoring `gameProcessedEvent`** in UIS handlers: typing "e" in chat triggers interact.
- **Lerp with a constant alpha** (`Lerp(target, 0.1)`) depends on frame rate. Use `1 - math.exp(-k * dt)`.
- **Setting `Camera.CFrame` while `CameraType` is `Custom`** gets overwritten by the default camera next frame.
- **Not restoring the camera** after a cutscene leaves players stuck.
- **Binding the same key in two places** with CAS: the most recently bound wins; use priorities.
- **Detecting mobile with `TouchEnabled` alone**: touch laptops report true. Prefer PreferredInput.

## Limitations

- The Input Action System and `UserInputService.PreferredInput` are recent; their exact API and availability must be verified in creator docs for your engine version.
- Device Emulator approximates devices; final checks need real phones and a console if you ship there.
- Console certification rules (e.g. no references to keyboard on Xbox) are not covered in full.
