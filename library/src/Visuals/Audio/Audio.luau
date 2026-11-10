--!strict
-- Audio: sound cues by name (Visuals.Audio). The kit ships no sounds and references no asset
-- ids. Every module plays cues such as "coin" or "egg.crack"; a cue is silent until the game
-- registers an id for it:
--
--   Audio.register("coin", 1234567890)
--   Audio.register("tap", { id = "rbxassetid://1234567891", volume = 0.4, pitchVariance = 0.12 })
--   Audio.play("coin")
--
-- Sounds are pooled in a "UVKSounds" folder under SoundService and routed through a "UVK"
-- SoundGroup with one child group per volume group ("sfx", "ui", ...).

local SoundService = game:GetService("SoundService")

local AudioLogic = require("./AudioLogic")
local Host = require("../Runtime/Host")

export type Handle = { stop: () -> (), cancel: () -> (), sound: Sound, cue: string }

export type PlayOptions = {
	volume: number?, -- multiplies the cue's volume
	pitch: number?, -- multiplies the cue's pitch
	pitchVariance: number?, -- overrides the cue's variance for this play
	force: boolean?, -- ignore the cue's cooldown
	at: Instance?, -- BasePart or Attachment: play as a positional sound there
}

local POOL_MAX = 12
-- A sound that never loads or never fires Ended is cleaned up after this many seconds.
local FALLBACK_SECONDS = 12

local Audio = {}

local state = AudioLogic.new()
local master: SoundGroup? = nil
local folder: Folder? = nil
local groups: { [string]: SoundGroup } = {}
local free: { Sound } = {}
local live: { [Sound]: () -> () } = {}
local masterVolume = 1
-- Group volumes live on the SoundGroups, not in the logic state, so they are applied once.
local groupVolumes: { [string]: number } = {}
local muted = false

local function masterGroup(): SoundGroup
	local existing = master
	if existing and existing.Parent then
		return existing
	end
	local group = Instance.new("SoundGroup")
	group.Name = "UVK"
	group.Volume = if muted then 0 else masterVolume
	group.Parent = SoundService
	master = group
	groups = {}
	return group
end

local function groupFor(name: string): SoundGroup
	local parent = masterGroup()
	local existing = groups[name]
	if existing and existing.Parent then
		return existing
	end
	local group = Instance.new("SoundGroup")
	group.Name = name
	group.Volume = groupVolumes[name] or 1
	group.Parent = parent
	groups[name] = group
	return group
end

local function soundFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "UVKSounds"
	created.Parent = SoundService
	folder = created
	free = {}
	return created
end

local function acquire(): Sound
	local parent = soundFolder()
	while #free > 0 do
		local sound = table.remove(free) :: Sound
		if sound.Parent == parent then
			return sound
		end
	end
	local sound = Instance.new("Sound")
	sound.Name = "Cue"
	sound.Parent = parent
	return sound
end

-- Registers a cue: an asset id (number or "rbxassetid://...") or { id, volume, pitch,
-- pitchVariance, cooldown, maxConcurrent, group }. nil removes the cue.
function Audio.register(cue: string, idOrOptions: any)
	AudioLogic.register(state, cue, idOrOptions)
end

function Audio.registerMany(map: { [string]: any })
	for cue, idOrOptions in map do
		AudioLogic.register(state, cue, idOrOptions)
	end
end

function Audio.isRegistered(cue: string): boolean
	return AudioLogic.isRegistered(state, cue)
end

-- The cue names the kit itself plays (registered or not).
function Audio.cues(): { string }
	return table.clone(AudioLogic.CUES)
end

-- The cues that currently have a sound.
function Audio.registered(): { string }
	return AudioLogic.registered(state)
end

-- Plays a cue. Returns nil without doing anything when the cue has no sound, is cooling down,
-- already has its maximum number of copies playing, or audio is muted.
function Audio.play(cue: string, options: PlayOptions?): Handle?
	local play = AudioLogic.decide(state, cue, os.clock(), options)
	if play == nil then
		return nil
	end
	local at = if options then options.at else nil
	local positional = at ~= nil and (at:IsA("BasePart") or at:IsA("Attachment"))
	local sound: Sound
	if positional and at then
		sound = Instance.new("Sound")
		sound.Name = "Cue"
		sound.Parent = at
	else
		sound = acquire()
	end
	sound.SoundId = play.id
	sound.Volume = play.volume
	sound.PlaybackSpeed = play.pitch
	sound.Looped = false
	sound.SoundGroup = groupFor(play.group)
	sound.TimePosition = 0

	local done = false
	local connection: RBXScriptConnection? = nil
	local cancelTimer: (() -> ())? = nil
	local function release()
		if done then
			return
		end
		done = true
		live[sound] = nil
		AudioLogic.ended(state, cue)
		if connection then
			connection:Disconnect()
		end
		if cancelTimer then
			cancelTimer()
		end
		if sound.Parent == nil then
			return
		end
		sound:Stop()
		if positional or #free >= POOL_MAX then
			sound:Destroy()
		else
			table.insert(free, sound)
		end
	end
	connection = sound.Ended:Once(release)
	local length = if sound.IsLoaded and sound.TimeLength > 0
		then sound.TimeLength / math.max(0.1, play.pitch) + 0.5
		else FALLBACK_SECONDS
	cancelTimer = Host.clock:after(length, release)
	live[sound] = release
	sound:Play()
	return { stop = release, cancel = release, sound = sound, cue = cue }
end

-- Stops a sound started by play(). Safe to call twice or with nil.
function Audio.stop(handle: Handle?)
	if handle then
		handle.stop()
	end
end

-- Stops every sound the kit is playing.
function Audio.stopAll()
	local releases: { () -> () } = {}
	for _, release in live do
		table.insert(releases, release)
	end
	for _, release in releases do
		release()
	end
end

-- Sets the volume (0..1) of a group ("sfx", "ui", or a group named at registration), or the
-- master volume when group is nil. Applies to sounds that are already playing.
function Audio.setVolume(group: string?, volume: number)
	local clamped = math.clamp(volume, 0, 1)
	if group == nil then
		masterVolume = clamped
		if master and not muted then
			master.Volume = clamped
		end
		return
	end
	groupVolumes[group] = clamped
	local existing = groups[group]
	if existing then
		existing.Volume = clamped
	end
end

-- Mutes or unmutes every cue. While muted, play() returns nil.
function Audio.mute(value: boolean)
	muted = value == true
	state.muted = muted
	if master then
		master.Volume = if muted then 0 else masterVolume
	end
	if muted then
		Audio.stopAll()
	end
end

function Audio.isMuted(): boolean
	return muted
end

return Audio
