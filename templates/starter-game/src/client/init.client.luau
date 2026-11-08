--!strict
-- Client entry point. Loads every ModuleScript in Controllers: all Init calls first, then every Start.
-- Add a controller by dropping a new ModuleScript into src/client/Controllers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Loader"))

Loader.run(script:WaitForChild("Controllers"), "Client")
