--!strict
-- Loading screen controller. Run it from a LocalScript in ReplicatedFirst so it starts before the rest
-- of the game replicates. It removes the default loading screen, waits for game.Loaded, preloads assets
-- with ContentProvider:PreloadAsync in batches, and reports a smoothed progress value to your callbacks.
-- It only requires LoadingLogic and LoadingConfig, so those three files can be copied into
-- ReplicatedFirst on their own (ReplicatedStorage may not have replicated yet when this runs).

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")

local LoadingConfig = require("./LoadingConfig")
local LoadingLogic = require("./LoadingLogic")

export type Options = {
	assets: { any }?, -- Instances or content id strings to preload
	config: { [string]: any }?,
	onProgress: ((progress: number, status: string) -> ())?, -- every frame while visible
	onSkipAvailable: (() -> ())?, -- show your skip button
	onFinished: ((status: string) -> ())?, -- hide your screen; status is "done", "skipped" or "timeout"
	removeDefault: boolean?, -- remove Roblox's default loading screen (default true)
}

export type Handle = {
	skip: (self: Handle) -> boolean,
	progress: (self: Handle) -> number,
	finished: (self: Handle) -> boolean,
	destroy: (self: Handle) -> (),
}

local LoadingClient = {}

function LoadingClient.start(options: Options?): Handle
	local opts: Options = options or {}
	local settings: { [string]: any } = table.clone(LoadingConfig)
	for key, value in pairs(opts.config or {}) do
		settings[key] = value
	end
	local config = LoadingLogic.resolveConfig(settings)
	if opts.removeDefault ~= false then
		ReplicatedFirst:RemoveDefaultLoadingScreen()
	end

	local assets = opts.assets or {}
	local started = os.clock()
	local gameStage = LoadingLogic.newTracker(1, started)
	local assetStage = LoadingLogic.newTracker(#assets, started)
	local shown = 0
	local skipOffered = false
	local done = false
	local connection: RBXScriptConnection? = nil

	local function finish(status: string)
		if done then
			return
		end
		done = true
		if connection then
			connection:Disconnect()
			connection = nil
		end
		if opts.onFinished then
			opts.onFinished(status)
		end
	end

	task.spawn(function()
		if not game:IsLoaded() then
			game.Loaded:Wait()
		end
		LoadingLogic.markLoaded(gameStage, 1, os.clock())
		for _, batch in LoadingLogic.batches(assets, config.batchSize) do
			if done then
				return
			end
			local ok = pcall(function()
				ContentProvider:PreloadAsync(batch)
			end)
			if ok then
				LoadingLogic.markLoaded(assetStage, #batch, os.clock())
			else
				LoadingLogic.markFailed(assetStage, #batch, os.clock())
			end
		end
	end)

	-- One tracker drives the timing rules; it is finished when both stages are.
	local overall = LoadingLogic.newTracker(1, started)

	connection = RunService.RenderStepped:Connect(function(dt: number)
		local now = os.clock()
		if LoadingLogic.isLoaded(gameStage) and LoadingLogic.isLoaded(assetStage) then
			LoadingLogic.markLoaded(overall, 1, now)
		end
		local target = LoadingLogic.weighted({
			{ weight = 1, progress = LoadingLogic.progress(gameStage) },
			{ weight = 4, progress = LoadingLogic.progress(assetStage) },
		})
		shown = LoadingLogic.displayProgress(shown, target, dt, config.displaySpeed)
		local status = LoadingLogic.status(overall, now, config)
		if opts.onProgress then
			opts.onProgress(shown, status)
		end
		if not skipOffered and LoadingLogic.canSkip(overall, now, config) then
			skipOffered = true
			if opts.onSkipAvailable then
				opts.onSkipAvailable()
			end
		end
		local barFull = shown >= 0.999 or status ~= "done"
		if LoadingLogic.shouldDismiss(overall, now, config) and barFull then
			finish(status)
		end
	end)

	local handle = {} :: Handle

	function handle.skip(_self: Handle): boolean
		if done or not LoadingLogic.skip(overall, os.clock(), config) then
			return false
		end
		finish("skipped")
		return true
	end

	function handle.progress(_self: Handle): number
		return shown
	end

	function handle.finished(_self: Handle): boolean
		return done
	end

	function handle.destroy(_self: Handle)
		finish("skipped")
	end

	return handle
end

return LoadingClient
