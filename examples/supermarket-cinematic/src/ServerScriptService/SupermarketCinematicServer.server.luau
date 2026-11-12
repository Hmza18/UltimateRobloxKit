-- SupermarketCinematicServer: small and passive by design.
--   * builds authentic R15 cast templates once (Players:CreateHumanoidModelFromDescription) into
--     ReplicatedStorage.SupermarketCinematics.CastTemplates; clients fall back to block rigs if this fails
--   * asks each joining player's client to play the intro once per session (Configuration.AutoPlayOnJoin)
--   * never touches gameplay data: no currency, inventory, prices, DataStores or existing objects

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Root = ReplicatedStorage:WaitForChild("SupermarketCinematics")
local Configuration = require(Root:WaitForChild("Configuration"))

local remote = Root:FindFirstChild("PlayIntro")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "PlayIntro"
	remote.Parent = Root
end

-- Cast templates ------------------------------------------------------------------------------------
local LOOKS = {
	Employee = { skin = Color3.fromRGB(255, 204, 153), shirt = Color3.fromRGB(46, 184, 92), pants = Color3.fromRGB(52, 73, 112) },
	Cashier = { skin = Color3.fromRGB(196, 136, 92), shirt = Color3.fromRGB(46, 184, 92), pants = Color3.fromRGB(52, 73, 112) },
	Customer = { skin = Color3.fromRGB(234, 184, 146), shirt = Color3.fromRGB(255, 140, 50), pants = Color3.fromRGB(70, 120, 210) },
	Shopper = { skin = Color3.fromRGB(160, 112, 80), shirt = Color3.fromRGB(150, 90, 230), pants = Color3.fromRGB(60, 60, 70) },
	Shopper2 = { skin = Color3.fromRGB(255, 220, 180), shirt = Color3.fromRGB(70, 200, 220), pants = Color3.fromRGB(230, 220, 200) },
}

local function buildTemplates()
	local folder = Root:FindFirstChild("CastTemplates")
	if folder then
		return
	end
	folder = Instance.new("Folder")
	folder.Name = "CastTemplates"
	local built = 0
	for role, look in pairs(LOOKS) do
		local ok, model = pcall(function()
			local d = Instance.new("HumanoidDescription")
			-- blocky R15 proportions: the cast clips were authored on exactly these
			d.BodyTypeScale = 0
			d.ProportionScale = 0
			d.HeightScale = 1
			d.WidthScale = 1
			d.DepthScale = 1
			d.HeadScale = 1
			d.HeadColor = look.skin
			d.LeftArmColor = look.skin
			d.RightArmColor = look.skin
			d.TorsoColor = look.shirt
			d.LeftLegColor = look.pants
			d.RightLegColor = look.pants
			return Players:CreateHumanoidModelFromDescription(d, Enum.HumanoidRigType.R15)
		end)
		if ok and model then
			model.Name = role
			for _, s in ipairs(model:GetDescendants()) do
				if s:IsA("BaseScript") then
					s:Destroy() -- the Animate script must not fight the cinematic
				end
			end
			model.Parent = folder
			built = built + 1
		else
			warn("[SupermarketCinematic] template " .. role .. " not built (" .. tostring(model) .. "): clients use block rigs")
		end
	end
	folder.Parent = Root
	print(("[SupermarketCinematic] %d cast templates ready"):format(built))
end

task.spawn(buildTemplates)

-- Auto play on join, once per session ------------------------------------------------------------
local played = {}

local function onCharacter(player)
	if played[player] or not Configuration.AutoPlayOnJoin then
		return
	end
	played[player] = true
	task.wait(Configuration.AutoPlayDelay)
	if player.Parent then
		remote:FireClient(player, "play")
	end
end

local function onPlayer(player)
	if player.Character then
		task.spawn(onCharacter, player)
	end
	player.CharacterAdded:Connect(function()
		onCharacter(player)
	end)
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	onPlayer(p)
end
Players.PlayerRemoving:Connect(function(player)
	played[player] = nil
end)
