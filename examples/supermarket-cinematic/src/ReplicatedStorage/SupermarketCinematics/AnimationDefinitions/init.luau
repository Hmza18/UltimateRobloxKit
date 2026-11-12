-- Clip registry. Clips/<Name> are generated from make-anim exports by tools/clips_to_luau.py; the
-- matching KeyframeSequences are in animations/<Name>.rbxmx (upload them, then paste the IDs into
-- Configuration.AnimationIds to play real AnimationTracks instead of the built-in pose player).
local AnimationDefinitions = { Clips = {}, Names = {} }

for _, module in ipairs(script:WaitForChild("Clips"):GetChildren()) do
	if module:IsA("ModuleScript") then
		local ok, data = pcall(require, module)
		if ok and type(data) == "table" and data.tracks then
			AnimationDefinitions.Clips[module.Name] = data
			table.insert(AnimationDefinitions.Names, module.Name)
		else
			warn("[SupermarketCinematic] clip module failed to load: " .. module.Name)
		end
	end
end
table.sort(AnimationDefinitions.Names)

-- Constants the choreography shares with the pose scripts (anim_src/*.py), in character space
-- (studs from the HumanoidRootPart centre, X right, Y up, -Z forward).
AnimationDefinitions.Contacts = {
	BoxCentre = Vector3.new(0, -1.30, -1.45), -- SM_BoxLift: box on its crate
	StockSlots = { -- SM_Stock: wrist targets for Place1..3
		Vector3.new(0.55, -0.05, -1.55),
		Vector3.new(-0.10, -0.05, -1.60),
		Vector3.new(0.45, 1.05, -1.45),
	},
	PickWrist = Vector3.new(0.35, 0.0, -1.6), -- SM_ReachPick: Grab
	ScanWait = Vector3.new(1.15, -0.15, -1.35), -- SM_Scan: product waiting on the counter (wrist)
	CounterTop = -0.5, -- SM_Scan: counter surface height in the cashier's space
}

return AnimationDefinitions
