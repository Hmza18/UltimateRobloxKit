--!strict
-- Server entry point. Loads every ModuleScript in Services: all Init calls first, then every Start.
-- Add a service by dropping a new ModuleScript into src/server/Services.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Loader"))

Loader.run(script:WaitForChild("Services"), "Server")
