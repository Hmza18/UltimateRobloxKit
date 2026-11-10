--!strict
-- PetSelection screen: the flagship "choose your pet" screen. It wraps Pets.selection (cards with
-- live 3D previews, hover / select / confirm motion, keyboard and gamepad focus) and adds what
-- every Screen has: open / close / update / destroy and intents.
--
-- The selection screen is created on open() and removed on close(); it plays its own entrance
-- and exit, so the shell's window animation is not used.
--
-- NOT run in Studio: see README.md.

local Motion = require("../Runtime/Motion")
local Pets = require("../Pets/Pets")
local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")

-- Longer than Pets.selection's own exit, so Closed fires after the cards have gone.
local EXIT_TIME = 0.3

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local view = ScreensLogic.petSelection(props)
	if #view.issues > 0 then
		error("PetSelection: " .. table.concat(view.issues, "; "), 0)
	end
	local selection: any = nil
	local chosen: string? = view.selected
	local cancelExit: (() -> ())? = nil

	local function finish()
		if selection ~= nil then
			selection:destroy()
			selection = nil
		end
		if shell.gui then
			shell.gui.Enabled = false
		end
		shell:fire("Closed")
	end

	local function open()
		if selection ~= nil and not selection:isDestroyed() then
			return
		end
		if shell.gui then
			shell.gui.Enabled = true
		end
		shell.root.Visible = true
		local current = shell.props
		selection = Pets.selection({
			parent = shell.root,
			title = current.title,
			subtitle = current.subtitle,
			pets = ScreensLogic.petSelection(current).pets,
			style = shell.styleName,
			palette = current.palette,
			confirmText = current.confirmText,
			selected = chosen,
			worldPosition = current.worldPosition,
			closeOnConfirm = current.closeOnConfirm,
			insets = current.insets,
			onSelect = function(id: string)
				chosen = id
				shell:fire("Selected", id)
			end,
			onConfirm = function(id: string)
				shell:fire("Confirmed", id)
				if current.closeOnConfirm ~= false then
					-- Pets.selection plays its exit and destroys itself; report Closed after it.
					cancelExit = Motion.delay(EXIT_TIME, finish)
				end
			end,
		})
	end

	local function close()
		if cancelExit then
			cancelExit()
			cancelExit = nil
		end
		if selection ~= nil then
			finish()
		end
	end

	shell.trove:Add(function()
		if cancelExit then
			cancelExit()
		end
		if selection ~= nil then
			selection:destroy()
			selection = nil
		end
	end)

	return {
		open = open,
		close = close,
		isOpen = function(): boolean
			return selection ~= nil and not selection:isDestroyed()
		end,
		-- Pets.selection is built once per open: new props apply from the next open, except the
		-- selected pet, which moves at once.
		update = function(partial: { [string]: any })
			if type(partial.selected) == "string" then
				chosen = partial.selected
				if selection ~= nil and not selection:isDestroyed() then
					selection:select(partial.selected)
				end
			end
		end,
		methods = {
			select = function(id: string): boolean
				if selection ~= nil and not selection:isDestroyed() then
					return selection:select(id)
				end
				return false
			end,
			confirm = function(): boolean
				if selection ~= nil and not selection:isDestroyed() then
					return selection:confirm()
				end
				return false
			end,
			selected = function(): string?
				if selection ~= nil and not selection:isDestroyed() then
					return selection:selected()
				end
				return chosen
			end,
		},
	}
end
