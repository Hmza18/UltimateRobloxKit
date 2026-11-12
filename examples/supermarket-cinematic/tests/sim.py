"""Run the cinematic's real Luau source headless, frame by frame, on the Roblox API mock.

    python3 tests/sim.py            (needs the `lupa` package: pip install lupa)

The source is loaded exactly as Rojo would lay it out (default.project.json), with Lua 5.4 standing in
for Luau. Results are measurements of the runtime logic, not of the Roblox engine (no rendering,
physics, AnimationTracks or audio): see README "Verification status".
"""
import json
import math
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

BOOT = r'''
local M = MOCK
Instance, Vector3, CFrame, Color3, UDim2, UDim, Vector2, Enum = M.Instance, M.Vector3, M.CFrame, M.Color3, M.UDim2, M.UDim, M.Vector2, M.Enum
NumberRange, NumberSequence, ColorSequence = M.NumberRange, M.NumberSequence, M.ColorSequence
NumberSequenceKeypoint, ColorSequenceKeypoint, TweenInfo = M.NumberSequenceKeypoint, M.ColorSequenceKeypoint, M.TweenInfo
math.clamp = function(x, a, b) if x < a then return a elseif x > b then return b end return x end
math.noise = function(x, y, z) return math.sin(x * 12.9898 + (y or 0) * 78.233 + (z or 0) * 37.719) * 0.5 end
LOGS = {}
warn = function(...) local t = {} for i, v in ipairs({...}) do t[i] = tostring(v) end LOGS[#LOGS + 1] = "WARN " .. table.concat(t, " ") end
print = function(...) local t = {} for i, v in ipairs({...}) do t[i] = tostring(v) end LOGS[#LOGS + 1] = table.concat(t, " ") end
typeof = function(v)
	local t = type(v)
	if t == "table" and rawget(v, "__t") then return rawget(v, "__t") end
	if t == "table" and getmetatable(v) and rawget(v, "_p") then return "Instance" end
	return t
end

SIM = { time = 0, deferred = {}, delayed = {}, render = {} }
task = {
	defer = function(fn, ...) local a = {...}; table.insert(SIM.deferred, function() fn(table.unpack(a)) end) end,
	spawn = function(fn, ...) fn(...) end,
	delay = function(t, fn, ...) local a = {...}; table.insert(SIM.delayed, { at = SIM.time + t, fn = function() fn(table.unpack(a)) end }) end,
	wait = function() return 0 end,
}

-- data model ------------------------------------------------------------------------------------------
game = Instance.new("DataModel")
local services = {}
local function service(name, class)
	local s = Instance.new(class or name)
	s.Name = name
	s.Parent = game
	services[name] = s
	return s
end
game.GetService = function(_, name) return services[name] or error("no service " .. name) end
workspace = service("Workspace")
local camera = Instance.new("Camera"); camera.Name = "Camera"; camera.Parent = workspace
camera.CameraType = Enum.CameraType.Custom
camera.FieldOfView = 70
workspace.CurrentCamera = camera
local RS = service("RunService")
RS.IsStudio = function() return true end
RS.BindToRenderStep = function(_, name, prio, fn) SIM.render[name] = { prio = prio, fn = fn } end
RS.UnbindFromRenderStep = function(_, name) SIM.render[name] = nil end
local Players = service("Players")
local player = Instance.new("Player"); player.Name = "Tester"; player.Parent = Players
Players.LocalPlayer = player
local pg = Instance.new("PlayerGui"); pg.Name = "PlayerGui"; pg.Parent = player
local ps = Instance.new("PlayerScripts"); ps.Name = "PlayerScripts"; ps.Parent = player
CONTROLS = { enabled = true, disables = 0, enables = 0 }
local pm = Instance.new("ModuleScript"); pm.Name = "PlayerModule"; pm.Parent = ps
pm._mock = { GetControls = function() return {
	Disable = function() CONTROLS.enabled = false; CONTROLS.disables = CONTROLS.disables + 1 end,
	Enable = function() CONTROLS.enabled = true; CONTROLS.enables = CONTROLS.enables + 1 end } end }
local hud = Instance.new("ScreenGui"); hud.Name = "GameHUD"; hud.Parent = pg
local char = Instance.new("Model"); char.Name = "Tester"; char.Parent = workspace
local hum = Instance.new("Humanoid"); hum.Parent = char
player.Character = char
camera.CameraSubject = hum
local SG = service("StarterGui")
CORE = {}
SG.SetCoreGuiEnabled = function(_, t, v)
	if t.Name == "All" then for _, n in ipairs({ "PlayerList", "Health", "Backpack", "Chat", "EmotesMenu" }) do CORE[n] = v end else CORE[t.Name] = v end
end
SG.GetCoreGuiEnabled = function(_, t) local v = CORE[t.Name]; if v == nil then return true end return v end
local CAS = service("ContextActionService")
CAS_BOUND = 0
CAS.BindAction = function(_, name, fn) CAS_BOUND = CAS_BOUND + 1; CAS_FN = fn end
CAS.UnbindAction = function(_, name) CAS_BOUND = CAS_BOUND - 1 end
local TS = service("TweenService")
TS.Create = function(_, obj, info, goal) local tw = Instance.new("Tween"); tw.Play = function(self) for k, v in pairs(goal) do obj[k] = v end self.Completed:Fire() end return tw end
local GS = service("GuiService"); GS.ReducedMotionEnabled = false; GS.GetGuiInset = function() return Vector2.new(0, 36) end
local L = service("Lighting")
L.ClockTime = 14; L.GeographicLatitude = 41; L.Brightness = 2; L.Ambient = Color3.new(0.3, 0.3, 0.3); L.OutdoorAmbient = Color3.new(0.5, 0.5, 0.5)
L.ExposureCompensation = 0; L.EnvironmentDiffuseScale = 1; L.EnvironmentSpecularScale = 1
service("SoundService"); service("ReplicatedStorage"); service("ServerScriptService"); service("StarterPlayer")

-- modules: Source strings attached by the Python loader; require runs them with `script` bound
local cache = {}
require = function(mod)
	if type(mod) == "table" and rawget(mod, "_p") and mod._mock then return mod._mock end
	if cache[mod] ~= nil then return cache[mod] end
	local src = mod.Source
	assert(src, "require: no source for " .. tostring(mod.Name))
	local env = setmetatable({ script = mod }, { __index = _G })
	local fn, err = load(src, "@" .. mod.Name, "t", env)
	assert(fn, err)
	local result = fn()
	cache[mod] = result
	return result
end
function RUN_SCRIPT(inst)
	local env = setmetatable({ script = inst }, { __index = _G })
	local fn, err = load(inst.Source, "@" .. inst.Name, "t", env)
	assert(fn, err)
	fn()
end

function STEP(dt)
	SIM.time = SIM.time + dt
	RS.PreSimulation:Fire(dt)
	M.solveJoints()
	local list = {}
	for name, r in pairs(SIM.render) do list[#list + 1] = r end
	table.sort(list, function(a, b) return a.prio < b.prio end)
	for _, r in ipairs(list) do r.fn(dt) end
	RS.Heartbeat:Fire(dt)
	local d = SIM.deferred; SIM.deferred = {}
	for _, fn in ipairs(d) do fn() end
	local keep = {}
	for _, t in ipairs(SIM.delayed) do if t.at <= SIM.time then t.fn() else keep[#keep + 1] = t end end
	SIM.delayed = keep
end
function COUNT_WORKSPACE() return #workspace:GetDescendants() end
'''


def load_tree(lua, mock):
    """Mirror default.project.json into mock Instances with Source attached."""
    game = lua.globals().game
    new = mock.new

    def module_tree(path, parent):
        init = path / "init.luau"
        if path.is_dir():
            if init.exists():
                inst = new("ModuleScript")
                inst.Source = init.read_text(encoding="utf-8")
            else:
                inst = new("Folder")
            inst.Name = path.name
            inst.Parent = parent
            for child in sorted(path.iterdir()):
                if child.name != "init.luau":
                    module_tree(child, inst)
            return inst
        if path.suffix == ".luau":
            name = path.name[:-len(".luau")]
            cls = "ModuleScript"
            if name.endswith(".server"):
                name, cls = name[:-7], "Script"
            elif name.endswith(".client"):
                name, cls = name[:-7], "LocalScript"
            inst = new(cls)
            inst.Name = name
            inst.Source = path.read_text(encoding="utf-8")
            inst.Parent = parent
            return inst
        return None

    rs = game.GetService(game, "ReplicatedStorage")
    module_tree(ROOT / "src/ReplicatedStorage/SupermarketCinematics", rs)
    sss = game.GetService(game, "ServerScriptService")
    server = module_tree(ROOT / "src/ServerScriptService/SupermarketCinematicServer.server.luau", sss)
    sp = game.GetService(game, "StarterPlayer")
    client = module_tree(ROOT / "src/StarterPlayerScripts/SupermarketCinematicClient.client.luau", sp)
    return server, client


def make_runtime():
    from lupa import lua54
    lua = lua54.LuaRuntime(unpack_returned_tuples=True)
    mock = lua.execute((HERE / "roblox_mock.lua").read_text(encoding="utf-8"))
    lua.globals().MOCK = mock
    lua.execute(BOOT)
    return lua, mock


SCENARIO = r'''
local RS = game:GetService("ReplicatedStorage")
local Root = RS.SupermarketCinematics
local Cinematic = require(Root.SharedUtilities.Cinematic)
local cin = Cinematic.new()
local finished = {}
cin.Finished.Event:Connect(function(skipped, stats) finished[#finished + 1] = { skipped = skipped, stats = stats, t = SIM.time } end)
local api = { cin = cin, finished = finished }

function api.playFor(seconds, sampler)
	local ok = cin:play()
	local frames = math.floor(seconds * 60 + 0.5)
	for i = 1, frames do
		STEP(1 / 60)
		if sampler then sampler(cin) end
	end
	return ok
end
function api.steps(n, sampler) for i = 1, n do STEP(1 / 60); if sampler then sampler(cin) end end end
return api
'''


def vec(v):
    return [v.X, v.Y, v.Z]


def run_all(report):
    """Every scenario; returns a dict of measurements (also what tests assert on)."""
    results = {}
    lua, mock = make_runtime()
    G = lua.globals()
    server, client = load_tree(lua, mock)
    api = lua.execute(SCENARIO)
    cam = G.workspace.CurrentCamera
    lighting = G.game.GetService(G.game, "Lighting")
    baseline_ws = G.COUNT_WORKSPACE()
    baseline_conn = mock.liveConnections
    before_light = {k: lighting[k] for k in ("ClockTime", "Brightness", "ExposureCompensation", "GeographicLatitude")}

    # ---- full playback with per-frame sampling ----------------------------------------------------
    frames = []
    prev = {"cf": None, "shot": None}
    checks = {"camera_jumps": [], "fov_out_of_range": 0, "nonfinite": 0, "shots_seen": [], "box_hand": [], "basket_hand": [],
              "held_prop_drift": [], "scenes": []}
    cin = api.cin

    def sampler(c):
        if c.state != "playing":
            return
        t = c.time
        cf = cam.CFrame
        p = vec(cf.Position)
        if any(not math.isfinite(x) for x in p):
            checks["nonfinite"] += 1
        fov = cam.FieldOfView
        if not (20 <= fov <= 80):
            checks["fov_out_of_range"] += 1
        shot = c.director.shots[c.director.index].name if c.director and c.director.index > 0 else None
        if shot and (not checks["shots_seen"] or checks["shots_seen"][-1] != shot):
            checks["shots_seen"].append(shot)
        if prev["cf"] is not None and prev["shot"] == shot:
            d = math.dist(prev["cf"], p)
            if d > 1.2:  # > 72 studs/s inside one shot = a visible jump
                checks["camera_jumps"].append((round(t, 3), shot, round(d, 3)))
        prev["cf"], prev["shot"] = p, shot
        actors = c.actors
        ctx = c.ctx
        # box between the hands while carried (9.7 - 11.0 s)
        if 9.7 <= t <= 11.0:
            box = ctx.props.ProductBox
            e = actors.Employee
            mid = [(a + b) / 2 for a, b in zip(vec(e.part(e, "RightHand").Position), vec(e.part(e, "LeftHand").Position))]
            checks["box_hand"].append(math.dist(vec(box.Position), mid))
        # basket stays under the customer's left hand
        cu = actors.Customer
        if cu and cu.basket:
            checks["basket_hand"].append(math.dist(vec(cu.basket.Position), vec(cu.part(cu, "LeftHand").Position)))
        if int(t * 60) % 30 == 0:
            frames.append({"t": round(t, 2), "cam": p, "fov": round(fov, 2), "shot": shot})

    ok = api.playFor(36.5, sampler)
    results["play_started"] = bool(ok)
    fin = api.finished
    results["finished_events"] = len(fin)
    results["finished_skipped"] = bool(fin[1].skipped) if len(fin) else None
    stats = fin[1].stats if len(fin) else None
    results["stats"] = {
        "products": stats.products if stats else None,
        "realProducts": stats.realProducts if stats else None,
        "cue_errors": stats.errors if stats else None,
        "cast": dict(stats.cast.items()) if stats else None,
        "missingAudio": list(stats.missingAudio.values()) if stats else None,
    }
    results["checks"] = {
        "camera_jumps": checks["camera_jumps"],
        "fov_out_of_range": checks["fov_out_of_range"],
        "nonfinite": checks["nonfinite"],
        "shots_seen": checks["shots_seen"],
        "box_hand_max": round(max(checks["box_hand"]), 3) if checks["box_hand"] else None,
        "basket_hand_range": [round(min(checks["basket_hand"]), 3), round(max(checks["basket_hand"]), 3)] if checks["basket_hand"] else None,
    }
    results["restore"] = {
        "state": cin.state,
        "camera_type": cam.CameraType.Name,
        "camera_fov": cam.FieldOfView,
        "camera_subject_is_humanoid": cam.CameraSubject is not None and cam.CameraSubject.ClassName == "Humanoid",
        "lighting_restored": all(abs(lighting[k] - v) < 1e-9 for k, v in before_light.items()),
        "hud_enabled": G.game.GetService(G.game, "Players").LocalPlayer.PlayerGui.GameHUD.Enabled,
        "controls_enabled": G.CONTROLS.enabled,
        "core_gui": dict(G.CORE.items()),
        "cas_bindings": G.CAS_BOUND,
        "render_bindings": len(list(G.SIM.render.keys())),
        "workspace_delta": G.COUNT_WORKSPACE() - baseline_ws,
        "connection_delta": mock.liveConnections - baseline_conn,
        "lighting_children": [c.Name for c in lighting.GetChildren(lighting).values()],
    }
    results["sounds_played"] = sorted(set(mock.soundsPlayed.values()))
    results["particles_emitted"] = mock.emitted
    results["log_warnings"] = [l for l in G.LOGS.values() if l.startswith("WARN")]
    results["frames"] = frames

    # ---- replay x3: nothing accumulates ------------------------------------------------------------
    counts = []
    for _ in range(3):
        api.playFor(36.5)
        counts.append((G.COUNT_WORKSPACE() - baseline_ws, mock.liveConnections - baseline_conn, G.CAS_BOUND, len(list(G.SIM.render.keys()))))
    results["replay_deltas"] = counts
    results["finished_events_after_replays"] = len(api.finished)

    # ---- duplicate start is refused ----------------------------------------------------------------
    api.playFor(1.0)
    results["second_play_refused"] = not cin.play(cin)
    cin.skip(cin)
    api.steps(90)

    # ---- skip during each scene -----------------------------------------------------------------------
    skips = []
    for at in (3.0, 9.0, 15.5, 24.9, 31.5):
        api.playFor(at)
        cin.skip(cin)
        api.steps(90)  # the 0.25 s fade + restore
        skips.append({
            "at": at, "state": cin.state, "camera": cam.CameraType.Name, "fov": cam.FieldOfView,
            "workspace_delta": G.COUNT_WORKSPACE() - baseline_ws, "connections": mock.liveConnections - baseline_conn,
            "controls": G.CONTROLS.enabled, "hud": G.game.GetService(G.game, "Players").LocalPlayer.PlayerGui.GameHUD.Enabled,
            "lighting_restored": all(abs(lighting[k] - v) < 1e-9 for k, v in before_light.items()),
        })
    results["skips"] = skips

    # ---- pause freezes the clock --------------------------------------------------------------------
    api.playFor(10.0)
    t0 = cin.time
    cin.pause(cin, True)
    api.steps(120)
    t1 = cin.time
    cin.pause(cin, False)
    api.steps(60)
    t2 = cin.time
    results["pause"] = {"before": round(t0, 3), "after_2s_paused": round(t1, 3), "after_resume_1s": round(t2, 3)}
    cin.skip(cin)
    api.steps(90)

    # ---- server + client scripts boot and auto-play once ----------------------------------------------
    G.RUN_SCRIPT(server)
    G.RUN_SCRIPT(client)
    G.LOGS_BEFORE = len(G.LOGS)
    api.steps(5)
    results["templates_folder"] = G.game.GetService(G.game, "ReplicatedStorage").SupermarketCinematics.FindFirstChild(
        G.game.GetService(G.game, "ReplicatedStorage").SupermarketCinematics, "CastTemplates") is not None
    results["test_panel"] = G.game.GetService(G.game, "Players").LocalPlayer.PlayerGui.FindFirstChild(
        G.game.GetService(G.game, "Players").LocalPlayer.PlayerGui, "SupermarketCinematicTestPanel") is not None
    results["log_tail"] = list(G.LOGS.values())[-12:]
    return results


def main():
    try:
        import lupa  # noqa: F401
    except ImportError:
        sys.exit("lupa is not installed: pip install lupa")
    res = run_all(report=True)
    out = ROOT / "tests" / "sim_report.json"
    frames = res.pop("frames")
    out.write_text(json.dumps(res, indent=1, default=str), encoding="utf-8")
    print(json.dumps(res, indent=1, default=str))


if __name__ == "__main__":
    main()
