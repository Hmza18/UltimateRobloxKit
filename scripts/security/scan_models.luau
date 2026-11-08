--!strict
-- Lune twin of scan_models.py for binary models and places (.rbxm, .rbxl) and XML (.rbxmx, .rbxlx).
--   lune run scripts/security/scan_models.luau path/to/Model.rbxm [more files...]
-- Exit code 1 when any HIGH finding exists. Same rule ids as the Python scanner (kept in sync by a test).
-- Lua patterns are simpler than regular expressions, so each rule is a list of patterns.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

type Rule = { id: string, severity: string, patterns: { string }, why: string }

local RULES: { Rule } = {
	{
		id = "require-asset-id",
		severity = "high",
		patterns = { "require%s*%(%s*%d%d%d%d%d+%s*%)" },
		why = "Loads a module from the Roblox library by id",
	},
	{
		id = "require-tonumber",
		severity = "high",
		patterns = { "require%s*%(%s*tonumber%s*%(" },
		why = "Loads a module by a computed id",
	},
	{ id = "loadstring", severity = "high", patterns = { "loadstring%s*%(" }, why = "Runs code from a string" },
	{
		id = "getfenv-setfenv",
		severity = "high",
		patterns = { "getfenv%s*%(", "setfenv%s*%(" },
		why = "Rewrites function environments",
	},
	{
		id = "get-objects",
		severity = "high",
		patterns = { ":%s*GetObjects%s*%(", ":%s*LoadAsset%s*%(", ":%s*LoadAssetVersion%s*%(" },
		why = "Inserts remote assets at runtime",
	},
	{
		id = "string-char-chain",
		severity = "high",
		patterns = { "string%.char%s*%(%s*%d+" .. string.rep("%s*,%s*%d+", 12) },
		why = "Long string.char chain hides a string",
	},
	{
		id = "escaped-bytes",
		severity = "medium",
		patterns = { string.rep("\\%d%d%d?", 12), string.rep("\\x%x%x", 12) },
		why = "Long escaped byte sequence",
	},
	{
		id = "http-request",
		severity = "medium",
		patterns = { ":%s*PostAsync%s*%(", ":%s*RequestAsync%s*%(", "HttpService.-:%s*GetAsync%s*%(" },
		why = "Sends or fetches data over HTTP",
	},
	{
		id = "webhook",
		severity = "high",
		patterns = {
			"discord%.com/api/webhooks",
			"discordapp%.com/api/webhooks",
			"hooks%.slack%.com",
			"webhook%.site",
		},
		why = "Posts to a chat webhook",
	},
	{
		id = "teleport-elsewhere",
		severity = "medium",
		patterns = { ":%s*Teleport%s*%(%s*%d%d%d%d%d%d+", ":%s*TeleportAsync%s*%(%s*%d%d%d%d%d%d+" },
		why = "Teleports players to a hard-coded place",
	},
	{
		id = "prompt-purchase",
		severity = "medium",
		patterns = { ":%s*PromptPurchase%s*%(", ":%s*PromptProductPurchase%s*%(", ":%s*PromptGamePassPurchase%s*%(" },
		why = "Prompts purchases",
	},
	{
		id = "server-kick-ban",
		severity = "low",
		patterns = { ":%s*Kick%s*%(", "BanAsync%s*%(" },
		why = "Kicks or bans",
	},
	{
		id = "long-base64",
		severity = "medium",
		patterns = { "[\"']" .. string.rep("[%w+/]", 180) },
		why = "Very long base64-like string",
	},
}

local HIDDEN_NAMES = { "vaccine", "virus", "infected", "backdoor", "fix lag", "anti lag", "spread" }

local findings = 0
local highs = 0
local scanned = 0

local function report(severity: string, id: string, place: string, why: string, line: string)
	findings += 1
	if severity == "high" then
		highs += 1
	end
	print(string.format("%-6s %-20s %s\n       %s\n       %s", string.upper(severity), id, place, why, line))
end

local function scanSource(label: string, source: string)
	scanned += 1
	local lineNumber = 0
	for line in string.gmatch(source .. "\n", "(.-)\r?\n") do
		lineNumber += 1
		for _, rule in RULES do
			for _, pattern in rule.patterns do
				if string.find(line, pattern) then
					report(rule.severity, rule.id, label .. ":" .. lineNumber, rule.why, string.sub(line, 1, 160))
					break
				end
			end
		end
	end
	local lowered = string.lower(label)
	for _, word in HIDDEN_NAMES do
		if string.find(lowered, word, 1, true) then
			report("low", "hidden-name", label, "Name used by known malicious models", "")
			break
		end
	end
end

local paths = process.args
if #paths == 0 then
	print("usage: lune run scripts/security/scan_models.luau <model.rbxm|.rbxmx|.rbxl|.rbxlx> ...")
	process.exit(2)
end

for _, path in paths do
	local contents = fs.readFile(path)
	local isPlace = string.find(path, "%.rbxlx?$") ~= nil
	local roots
	if isPlace then
		roots = roblox.deserializePlace(contents):GetChildren()
	else
		roots = roblox.deserializeModel(contents)
	end
	for _, root in roots do
		local all = root:GetDescendants()
		table.insert(all, root)
		for _, instance in all do
			if instance:IsA("LuaSourceContainer") then
				local source = (instance :: any).Source :: string
				scanSource(path .. " > " .. instance.ClassName .. " " .. instance:GetFullName(), source)
			end
		end
	end
end

print(string.format("%d scripts scanned, %d findings (%d high)", scanned, findings, highs))
if highs > 0 then
	process.exit(1)
end
