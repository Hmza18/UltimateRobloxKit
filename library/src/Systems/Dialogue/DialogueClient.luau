--!strict
-- Client adapter for Dialogue. UI-agnostic: it calls your onNode/onEnd callbacks and fires signals,
-- and your UI calls choose(index) or advance(). The server decides what happens next.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type ChoiceView = { index: number, text: string }
export type View = { id: string, speaker: string?, text: string, choices: { ChoiceView }, canContinue: boolean }

export type Options = {
	onNode: ((view: View) -> ())?, -- draw the node; choice buttons call client:choose(choice.index)
	onEnd: (() -> ())?, -- hide the dialogue UI
	remoteFolder: string?, -- default "UrkDialogue"
}

export type Client = {
	nodeChanged: Signal.Signal, -- (view)
	ended: Signal.Signal,
	current: (self: Client) -> View?,
	choose: (self: Client, index: number) -> (),
	advance: (self: Client) -> (), -- move on from a node without visible choices
	close: (self: Client) -> (),
	destroy: (self: Client) -> (),
}

local DialogueClient = {}

function DialogueClient.new(options: Options?): Client
	local opts: Options = options or {}
	local folder = ReplicatedStorage:WaitForChild(opts.remoteFolder or "UrkDialogue")
	local nodeRemote = folder:WaitForChild("Node") :: RemoteEvent
	local inputRemote = folder:WaitForChild("Input") :: RemoteEvent
	local trove = Trove.new()
	local nodeChanged = Signal.new()
	local ended = Signal.new()
	trove:Add(function()
		nodeChanged:DisconnectAll()
		ended:DisconnectAll()
	end)
	local currentView: View? = nil

	trove:Connect(nodeRemote.OnClientEvent, function(view: any)
		if type(view) == "table" then
			currentView = view
			if opts.onNode then
				opts.onNode(view)
			end
			nodeChanged:Fire(view)
		else
			currentView = nil
			if opts.onEnd then
				opts.onEnd()
			end
			ended:Fire()
		end
	end)

	local client = {} :: Client
	client.nodeChanged = nodeChanged
	client.ended = ended

	function client.current(_self: Client): View?
		return currentView
	end

	function client.choose(_self: Client, index: number)
		if currentView then
			inputRemote:FireServer("choose", index)
		end
	end

	function client.advance(_self: Client)
		if currentView then
			inputRemote:FireServer("advance")
		end
	end

	function client.close(_self: Client)
		inputRemote:FireServer("close")
	end

	function client.destroy(_self: Client)
		trove:Clean()
	end

	return client
end

return DialogueClient
