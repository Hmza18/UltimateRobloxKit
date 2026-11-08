---
name: game-art-presentation
description: Prepares how a Roblox experience presents itself - the game icon, thumbnails and video thumbnails, loading screens with ReplicatedFirst and ContentProvider PreloadAsync, a consistent visual identity, store page title and description copy, a capture workflow from Studio, moderation-safe art rules and a shot list template. Use when making or refreshing an icon, thumbnails, a loading screen or the experience page before launch or an update.
license: MIT
metadata:
  category: ui
  version: 1.0.0
  triggers: [game icon, thumbnail, loading screen, preloadasync, replicatedfirst, store page, experience page, shot list, key art, capture]
  depends: [roblox-ui-systems, lighting-atmosphere, roblox-publishing-liveops]
---

# Game art and presentation

## When to use

- Before launch or a major update: icon, thumbnails, description.
- Building or fixing a loading screen.
- Defining the visual identity (logo, palette, type) used across UI and marketing.

When not to use: in-game HUD and menus (use `roblox-ui-systems`), publishing settings, update logs and events (use `roblox-publishing-liveops`), scene lighting (use `lighting-atmosphere`).

## Inputs

- The game's one-sentence hook and core loop (from `game-design-core`).
- A built, lit scene that shows real gameplay.
- Brand basics: name, palette, logo or permission to design one.

## Current specs (verify current specs)

These are the commonly documented values as of 2026; Roblox changes them, so check the creator docs page for experience icons and thumbnails before producing final files.

| Asset | Spec |
|---|---|
| Icon | 512x512 PNG or JPG, square; keep the subject inside the centre ~80% because some surfaces crop or round corners |
| Thumbnails | 1920x1080 (16:9), up to 10 per experience; first one matters most |
| Video thumbnail | Uploaded video asset or supported link per creator docs; short, silent-safe, gameplay first |
| File size | Keep under the upload limit in creator docs; export PNG for UI-like art, high-quality JPG for scenes |

All uploads pass moderation; rejected images can delay a launch, so upload early.

## Workflow

1. **Visual identity first.** Fix one logo wordmark, 2 brand colours plus 1 accent, one display font (from the fonts available in Roblox so UI matches), and one character or object that represents the game. Write them to `docs/brand.md`. Use the same values in the UI `Theme` module.
2. **Icon.** One clear subject, large, high contrast, readable at 50x50 px. Optional short title only if it is still legible small. No more than 3 main colours. Avoid thin lines and small text.
3. **Thumbnails.** Follow the shot list in [references/shot-list-template.md](references/shot-list-template.md). Thumbnail 1 shows the core action in one glance; later ones show progression, variety, social play and the best location. Real gameplay only; captions must describe what is actually in the game.
4. **Capture from Studio.**
   - Use a dedicated `Capture` place copy or a capture script: hide the HUD (`StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)` in a client script), set a fixed `ClockTime` and the hero lighting preset.
   - Set the Studio window or Device Emulator to 1920x1080 (or larger, then downscale), position `workspace.CurrentCamera` by script for repeatable shots, and lower `FieldOfView` (40-55) for hero shots.
   - Pose characters with animations paused on a strong frame; use R15 rigs and in-game items.
   - Capture with the Roblox screenshot key or OS tools; record video with the in-client recorder or OS capture. Composite text and logos in an image editor, not in the 3D scene.
5. **Loading screen.** Keep it short and honest: logo, a progress bar and a tip. Code below. Preload only what the first screen needs (logo, HUD icons, spawn area sounds); everything else streams.
6. **Store page copy.** Title: the game name plus at most one short descriptor; no keyword stuffing, no emoji spam, no false claims like "#1" or fake update tags. Description: first two lines say what you do and why it is fun; then a short feature list, update notes, and community rules. Disclose paid features plainly (see `monetization-economy-design`).
7. **Refresh cadence.** Update thumbnails with major updates; keep old ones as a baseline when testing (thumbnail personalisation and A/B tools exist in the Creator Dashboard; verify current options).

### Loading screen

```lua
--!strict
-- ReplicatedFirst/Loading.client.lua, with a ScreenGui "LoadingGui" as its child.
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local gui = (script:WaitForChild("LoadingGui") :: ScreenGui):Clone()
gui.ResetOnSpawn = false
gui.ScreenInsets = Enum.ScreenInsets.None
gui.DisplayOrder = 100
gui.Parent = player:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()

local bar = gui:WaitForChild("Bar"):WaitForChild("Fill") :: Frame
local MAX_WAIT = 15 -- never trap players behind a stuck loader

-- Asset ids for the first screen; keep this list short.
local critical: { string } = {
	"rbxassetid://0", -- logo (replace)
}

local done = false
task.spawn(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	local total = #critical
	local loaded = 0
	ContentProvider:PreloadAsync(critical, function(_assetId: string, _status: Enum.AssetFetchStatus)
		loaded += 1
		bar.Size = UDim2.fromScale(if total > 0 then loaded / total else 1, 1)
	end)
	done = true
end)

local start = os.clock()
while not done and os.clock() - start < MAX_WAIT do
	task.wait(0.1)
end

local fade = TweenService:Create(gui:WaitForChild("Background") :: Frame, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
fade:Play()
fade.Completed:Wait()
gui:Destroy()
```

Add a Skip button that appears after about 5 seconds. Failed asset fetches are reported through the callback status; log them, do not block.

## Outputs

- `docs/brand.md` (identity), `docs/store-page.md` (title, description, update notes).
- `art/icon_512.png`, `art/thumb_01..10.png`, optional video file, plus the layered source files.
- `ReplicatedFirst/Loading.client.lua` with its `LoadingGui`.

## Validation

1. View the icon at 512, 150 and 50 px side by side with three popular games' icons in the same genre; it should be identifiable at 50 px.
2. Check every thumbnail at phone size (about 360 px wide): the subject still reads.
3. Truth check: every thumbnail shows something a new player can see in the first sessions, or is labelled clearly.
4. Loading screen: test with network throttling in Studio (verify the current emulation option) and on a phone; it must finish or skip within 15 s.
5. Upload early to a private test experience to surface moderation issues before launch.

## Pitfalls

- Busy thumbnails with many characters and effects read as noise on phones.
- Using other games' characters, real brands, logos, celebrities or copyrighted characters: moderation risk and IP infringement.
- Misleading art (features not in the game) harms trust and can break Roblox rules.
- Preloading the whole game: long waits, worse retention.
- Loading screen that never ends because one asset failed; always add a timeout.

## Moderation-safe art rules

- Original art only; no real logos, brands, trademarks or real people.
- No gore, sexual content, drugs, gambling imagery, extremist symbols or real-world violence; check the current Community Standards for age guidelines (content maturity labels).
- No external links, social handles or "free Robux" style text in images.
- No fake UI (fake Roblox buttons, fake notifications).
- Text in images must be readable and accurate; localised captions are allowed if they match the game.

## Limitations

- Cannot produce final image files or judge aesthetics without a human look.
- Exact sizes, counts, video options and moderation rules change; verify current specs in the creator docs and Creator Dashboard.
- Thumbnail performance is only known from live data; see `monetization-economy-design` for honest A/B reading.
