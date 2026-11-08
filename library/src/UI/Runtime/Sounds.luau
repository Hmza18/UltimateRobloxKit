--!strict
-- Plays UI sounds locally. One Sound instance per asset id is created on first use and reused,
-- so hover sounds on a grid of buttons do not create hundreds of instances.

local SoundService = game:GetService("SoundService")

local Sounds = {}

local cache: { [string]: Sound } = {}
local folder: Folder? = nil
local muted = false
local volume = 0.5

local function assetId(id: string | number): string?
	local text = tostring(id)
	if text == "" or text == "0" then
		return nil
	end
	if string.find(text, "^%d+$") then
		return "rbxassetid://" .. text
	end
	return text
end

local function container(): Folder
	if folder == nil or folder.Parent == nil then
		local created = Instance.new("Folder")
		created.Name = "UrkUISounds"
		created.Parent = SoundService
		folder = created
		return created
	end
	return folder :: Folder
end

function Sounds.setMuted(value: boolean)
	muted = value
end

function Sounds.setVolume(value: number)
	volume = math.clamp(value, 0, 1)
end

-- Plays an asset id ("123", 123 or "rbxassetid://123"). Does nothing for nil, "" or while muted.
function Sounds.play(id: (string | number)?, gain: number?)
	if id == nil or muted then
		return
	end
	local resolved = assetId(id)
	if resolved == nil then
		return
	end
	local sound = cache[resolved]
	if sound == nil or sound.Parent == nil then
		local created = Instance.new("Sound")
		created.SoundId = resolved
		created.Parent = container()
		cache[resolved] = created
		sound = created
	end
	sound.Volume = volume * (gain or 1)
	SoundService:PlayLocalSound(sound)
end

function Sounds.clear()
	for _, sound in cache do
		sound:Destroy()
	end
	table.clear(cache)
	if folder then
		folder:Destroy()
		folder = nil
	end
end

return Sounds
