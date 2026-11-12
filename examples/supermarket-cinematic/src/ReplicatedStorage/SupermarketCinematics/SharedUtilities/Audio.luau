-- Audio cue hooks. Every cue name in Configuration.Audio can be fired from the timeline; cues without
-- a SoundId stay silent and are reported once (so missing sounds are visible, never invented).

local SoundService = game:GetService("SoundService")

local Audio = {}
Audio.__index = Audio

function Audio.new(config, folderParent)
	local self = setmetatable({}, Audio)
	self.config = config
	self.folder = Instance.new("Folder")
	self.folder.Name = "SupermarketCinematicAudio"
	self.folder.Parent = folderParent or SoundService
	self.sounds = {}
	self.missing = {}
	self.lastStep = 0
	return self
end

function Audio:_id(cue)
	local id = self.config.Audio[cue]
	if id == nil or id == "" then
		if not self.missing[cue] then
			self.missing[cue] = true
			print(("[SupermarketCinematic] audio cue '%s' has no SoundId (Configuration.Audio.%s): silent hook"):format(cue, cue))
		end
		return nil
	end
	return id
end

-- opts: { at = Vector3 (3D) or nil (2D), volume, looped, pitch }
function Audio:play(cue, opts)
	opts = opts or {}
	local id = self:_id(cue)
	if not id then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = cue
	sound.SoundId = id
	sound.Volume = opts.volume or self.config.AudioVolume[cue] or self.config.AudioVolume.default
	sound.Looped = opts.looped or false
	sound.PlaybackSpeed = opts.pitch or 1
	local holder = self.folder
	if opts.at then
		local a = Instance.new("Part")
		a.Name = cue .. "Emitter"
		a.Size = Vector3.new(0.1, 0.1, 0.1)
		a.Transparency = 1
		a.Anchored = true
		a.CanCollide = false
		a.CanQuery = false
		a.CanTouch = false
		a.CFrame = CFrame.new(opts.at)
		a.Parent = opts.parent3d or self.folder
		sound.RollOffMaxDistance = 120
		holder = a
	end
	sound.Parent = holder
	sound:Play()
	self.sounds[#self.sounds + 1] = sound
	if not sound.Looped then
		sound.Ended:Once(function()
			if holder ~= self.folder then
				holder:Destroy()
			else
				sound:Destroy()
			end
		end)
	end
	return sound
end

-- Footsteps are throttled so overlapping walkers do not stack into noise.
function Audio:footstep(at)
	local now = os.clock()
	if now - self.lastStep < 0.12 then
		return
	end
	self.lastStep = now
	self:play("Footstep", { at = at, pitch = 0.95 + math.random() * 0.1 })
end

function Audio:setPaused(paused)
	for _, s in ipairs(self.sounds) do
		if s.Parent then
			if paused and s.IsPlaying then
				s:Pause()
			elseif not paused and s.IsPaused then
				s:Resume()
			end
		end
	end
end

function Audio:missingCues()
	local out = {}
	for cue in pairs(self.missing) do
		out[#out + 1] = cue
	end
	table.sort(out)
	return out
end

function Audio:destroy()
	for _, s in ipairs(self.sounds) do
		pcall(function()
			s:Stop()
		end)
	end
	self.sounds = {}
	self.folder:Destroy()
end

return Audio
