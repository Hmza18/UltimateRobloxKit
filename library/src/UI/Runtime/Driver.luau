--!strict
-- One shared frame loop for every running animation (decorative effects, count-ups, shakes).
-- It connects to RenderStepped only while at least one job is active and disconnects when the
-- last job finishes, so an idle UI does no per-frame work at all.

local RunService = game:GetService("RunService")

-- A job receives the frame delta and os.clock(). Returning false ends the job.
export type Job = (dt: number, now: number) -> boolean?

local Driver = {}

local jobs: { [number]: Job } = {}
local jobCount = 0
local nextId = 0
local connection: RBXScriptConnection? = nil

local function removeJob(id: number)
	if jobs[id] ~= nil then
		jobs[id] = nil
		jobCount -= 1
	end
end

local function step(dt: number)
	local now = os.clock()
	for id, job in table.clone(jobs) do
		if jobs[id] == job then
			local ok, result = pcall(job, dt, now)
			if not ok then
				warn("[UrkUI] animation job failed: " .. tostring(result))
				removeJob(id)
			elseif result == false then
				removeJob(id)
			end
		end
	end
	if jobCount == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Adds a job and returns a function that removes it.
function Driver.add(job: Job): () -> ()
	nextId += 1
	local id = nextId
	jobs[id] = job
	jobCount += 1
	if connection == nil then
		local signal = if RunService:IsClient() then RunService.RenderStepped else RunService.Heartbeat
		connection = signal:Connect(step)
	end
	local function remove()
		removeJob(id)
	end
	return remove
end

-- Number of running jobs (0 means the frame loop is disconnected).
function Driver.count(): number
	return jobCount
end

function Driver.isRunning(): boolean
	return connection ~= nil
end

return Driver
