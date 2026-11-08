--!strict
-- The only script the tag-only setup needs (see TagOnly.md). StarterPlayerScripts, LocalScript.
-- It mirrors the player's attributes into Stats.* so UrkBind / UrkProgress labels have data.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UrkUI = require(ReplicatedStorage:WaitForChild("UltimateRobloxKit"):WaitForChild("UI"):WaitForChild("UrkUI"))

UrkUI.start({ store = UrkUI.Store.fromAttributes(Players.LocalPlayer, "Stats") })
