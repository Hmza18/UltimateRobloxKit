-- SupermarketCinematicClient: plays the intro locally when the server asks (once per session), and
-- shows a small Replay / Pause / Skip test panel in Studio (Configuration.ShowTestPanel).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Root = ReplicatedStorage:WaitForChild("SupermarketCinematics")
local Configuration = require(Root:WaitForChild("Configuration"))
local Utils = Root:WaitForChild("SharedUtilities")
local Cinematic = require(Utils:WaitForChild("Cinematic"))
local CinematicUi = require(Utils:WaitForChild("CinematicUi"))

local player = Players.LocalPlayer
local cinematic = Cinematic.new()
local lastStart = -math.huge
local plays = 0

local function start()
	if cinematic:isPlaying() then
		return false -- duplicate playback is ignored
	end
	if os.clock() - lastStart < Configuration.ReplayCooldown then
		return false
	end
	lastStart = os.clock()
	-- give the server a moment to publish authentic cast templates on the very first play
	if not Root:FindFirstChild("CastTemplates") then
		Root:WaitForChild("CastTemplates", 3)
	end
	local ok = cinematic:play()
	if ok then
		plays = plays + 1
	end
	return ok
end

local remote = Root:WaitForChild("PlayIntro", 10)
if remote then
	remote.OnClientEvent:Connect(function(action)
		if action == "play" then
			start()
		end
	end)
end

local showPanel = Configuration.ShowTestPanel
if showPanel == "studio" then
	showPanel = RunService:IsStudio()
end
if showPanel then
	local panel
	panel = CinematicUi.testPanel(player:WaitForChild("PlayerGui"), {
		replay = function()
			start()
		end,
		pause = function()
			if cinematic:isPlaying() then
				cinematic:pause(not cinematic.paused)
				panel.pause.Text = cinematic.paused and "Resume" or "Pause"
			end
		end,
		skip = function()
			cinematic:skip()
		end,
	})
	cinematic.SceneChanged.Event:Connect(function(i, name)
		panel.status.Text = ("Scene %d: %s"):format(i, name)
	end)
	cinematic.Finished.Event:Connect(function(skipped, stats)
		panel.pause.Text = "Pause"
		panel.status.Text = ("Intro cinematic: %s (play %d)"):format(skipped and "skipped" or "finished", plays)
		local missing = stats and stats.missingAudio and #stats.missingAudio or 0
		panel.info.Text = ("products %d (real %d), cue errors %d, silent audio cues %d"):format(
			stats and stats.products or 0, stats and stats.realProducts or 0, stats and stats.errors or 0, missing)
	end)
	RunService.Heartbeat:Connect(function()
		if cinematic:isPlaying() then
			panel.info.Text = ("t = %.1f s%s"):format(cinematic.time, cinematic.paused and "  (paused)" or "")
		end
	end)
end

-- If the character dies or respawns mid-cinematic, playback simply continues; restore always picks up
-- the current character's Humanoid as the camera subject.
cinematic.Finished.Event:Connect(function(skipped, stats)
	local cast = {}
	for name, kind in pairs(stats and stats.cast or {}) do
		cast[#cast + 1] = name .. "=" .. kind
	end
	table.sort(cast)
	print(("[SupermarketCinematic] %s; cast %s; products %d (real %d); cue errors %d"):format(
		skipped and "skipped" or "finished", table.concat(cast, ", "),
		stats and stats.products or 0, stats and stats.realProducts or 0, stats and stats.errors or 0))
end)
