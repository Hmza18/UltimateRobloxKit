--!strict
-- Loading screen: wraps the LoadingScreen component (title or logo, progress bar, rotating tips)
-- as a Screen. open() shows it, setProgress(ratio) moves the bar, and finish() (or close())
-- fills the bar, fades out and raises Closed.
--
-- NOT run in Studio: see README.md.

local ScreenKit = require("./ScreenKit")

local Game = ScreenKit.Game

return function(shell: ScreenKit.Shell, _props: { [string]: any })
	local loading: any = nil
	local progress = 0

	local function remove()
		if loading ~= nil then
			loading:destroy()
			loading = nil
		end
	end
	shell.trove:Add(remove)

	local function open()
		if loading ~= nil then
			return
		end
		local props = shell.props
		progress = math.clamp(props.progress, 0, 1)
		if shell.gui then
			shell.gui.Enabled = true
		end
		shell.root.Visible = true
		local made = Game.LoadingScreen.new({
			style = shell.styleName,
			parent = shell.root,
			name = "Loading",
			title = props.title,
			logo = props.logo,
			icon = props.icon,
			tips = props.tips,
			tipInterval = props.tipInterval,
			progress = progress,
			palette = props.palette,
			destroyOnClose = false,
		})
		loading = made
		made.Closed:Connect(function()
			if loading ~= made then
				return
			end
			remove()
			if shell.gui then
				shell.gui.Enabled = false
			end
			shell:fire("Closed")
		end)
	end

	local function finish()
		if loading ~= nil then
			loading:finish()
		end
	end

	return {
		open = open,
		close = finish,
		isOpen = function(): boolean
			return loading ~= nil
		end,
		update = function(partial: { [string]: any })
			if loading == nil then
				return
			end
			if partial.progress ~= nil then
				progress = math.clamp(partial.progress, 0, 1)
				loading:setProgress(progress)
			end
			local rest: { [string]: any } = {}
			for _, key in ipairs({ "title", "logo", "icon", "tips", "tipInterval", "palette" }) do
				rest[key] = partial[key]
			end
			if next(rest) ~= nil then
				rest.progress = progress
				loading:update(rest)
			end
		end,
		methods = {
			setProgress = function(ratio: number)
				progress = math.clamp(ratio, 0, 1)
				shell.props.progress = progress
				if loading ~= nil then
					loading:setProgress(progress)
				end
			end,
			finish = finish,
		},
	}
end
