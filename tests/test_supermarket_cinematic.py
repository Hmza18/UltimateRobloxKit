"""examples/supermarket-cinematic: data integrity (stdlib) and, when `lupa` is installed, the real Luau
runtime played headless on tests/roblox_mock.lua (a Roblox API stand-in, not the engine)."""
import json
import re
import unittest

from _util import ROOT

EX = ROOT / "examples/supermarket-cinematic"
SRC = EX / "src/ReplicatedStorage/SupermarketCinematics"
CLIPS = SRC / "AnimationDefinitions/Clips"

try:
    import lupa  # noqa: F401
    HAVE_LUPA = True
except ImportError:
    HAVE_LUPA = False


def clip_markers(name):
    text = (CLIPS / f"{name}.luau").read_text(encoding="utf-8")
    return set(re.findall(r'name = "(\w+)" }', text))


class CinematicDataTests(unittest.TestCase):
    def test_project_paths_exist(self):
        project = json.loads((EX / "default.project.json").read_text(encoding="utf-8"))

        def walk(node):
            for key, value in node.items():
                if key == "$path":
                    self.assertTrue((EX / value).exists(), value)
                elif isinstance(value, dict):
                    walk(value)
        walk(project["tree"])

    def test_every_clip_has_source_and_keyframe_sequence(self):
        clips = sorted(p.stem for p in CLIPS.glob("SM_*.luau"))
        self.assertEqual(len(clips), 13)
        for name in clips:
            with self.subTest(clip=name):
                self.assertTrue((EX / "anim_src" / f"{name}.py").exists())
                self.assertTrue((EX / "animations" / f"{name}.rbxmx").exists())

    def test_clips_and_markers_used_by_the_timeline_exist(self):
        timeline = (SRC / "TimelineDefinitions.luau").read_text(encoding="utf-8")
        clips = {p.stem for p in CLIPS.glob("SM_*.luau")}
        for name in set(re.findall(r'"(SM_\w+)"', timeline)):
            self.assertIn(name, clips)
        needs = {"SM_BoxLift": {"Grab"}, "SM_ReachPick": {"Grab", "Drop"}, "SM_Scan": {"Grab", "Beep", "Release"},
                 "SM_Stock": {"BoxToLeft", "Take1", "Place1", "Take2", "Place2", "Take3", "Place3"},
                 "SM_Walk": {"Step"}, "SM_BasketWalk": {"Step"}, "SM_CarryWalk": {"Step"}}
        for clip, markers in needs.items():
            with self.subTest(clip=clip):
                self.assertLessEqual(markers, clip_markers(clip))

    def test_configured_animation_ids_cover_every_clip(self):
        config = (SRC / "Configuration.luau").read_text(encoding="utf-8")
        for clip in (p.stem for p in CLIPS.glob("SM_*.luau")):
            self.assertRegex(config, rf"\b{clip} = \"\"")

    def test_no_invented_asset_ids(self):
        # Only empty hooks or engine-bundled rbxasset:// files; real IDs are the owner's to add.
        for path in EX.rglob("*.luau"):
            text = path.read_text(encoding="utf-8")
            with self.subTest(file=path.name):
                self.assertNotRegex(text, r"rbxassetid://\d+")
                self.assertNotRegex(text, r"SoundId\s*=\s*\"\d")

    def test_shots_cover_the_whole_timeline(self):
        text = (SRC / "TimelineDefinitions.luau").read_text(encoding="utf-8")
        shots = [(float(a), float(b)) for a, b in re.findall(r"t0 = ([\d.]+), t1 = ([\d.]+), ease", text)]
        self.assertGreaterEqual(len(shots), 12)
        self.assertEqual(shots[0][0], 0.0)
        for (a0, a1), (b0, _) in zip(shots, shots[1:]):
            self.assertAlmostEqual(a1, b0, msg="gap or overlap between shots")
        duration = float(re.search(r"Duration = ([\d.]+)", text).group(1))
        self.assertGreaterEqual(shots[-1][1], duration)
        for fov in re.findall(r"fov = ([\d.]+)", text):
            self.assertTrue(20 <= float(fov) <= 80, fov)


@unittest.skipUnless(HAVE_LUPA, "lupa not installed (pip install lupa): Luau runtime tests skipped")
class CinematicRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import sys
        sys.path.insert(0, str(EX / "tests"))
        import sim
        cls.sim = sim

    def runtime(self):
        lua, mock = self.sim.make_runtime()
        self.sim.load_tree(lua, mock)
        return lua, mock

    def test_every_module_compiles(self):
        from lupa import lua54
        lua = lua54.LuaRuntime()
        load = lua.eval("function(src, name) local f, err = load(src, name, 't') return err end")
        for path in sorted(EX.rglob("*.luau")):
            with self.subTest(file=path.name):
                self.assertIsNone(load(path.read_text(encoding="utf-8"), path.name))

    def test_pure_modules(self):
        lua, _ = self.runtime()
        rs = lua.globals().game.GetService(lua.globals().game, "ReplicatedStorage")
        utils = rs.SupermarketCinematics.SharedUtilities
        req = lua.globals().require
        easing = req(utils.Easing)
        for name in ("linear", "inOutSine", "outBack", "outBackSoft", "outCubic", "inExpo", "outBounce", "outElastic"):
            self.assertAlmostEqual(easing.apply(name, 0), 0)
            self.assertAlmostEqual(easing.apply(name, 1), 1)
        timeline_mod = req(utils.Timeline)
        cues = lua.eval("function(T) local log = {} local t = T.new({ {t = 2, name = 'b', run = function() log[#log+1] = 'b' end}, "
                        "{t = 1, name = 'a', run = function() log[#log+1] = 'a' end}, {t = 2, name = 'c', run = function() error('x') end}, "
                        "{t = 5, name = 'd', run = function() log[#log+1] = 'd' end} }) t:update(0.5) t:update(3) t:update(3) "
                        "return table.concat(log, ','), #t.fired, t:done() end")
        log, fired, done = cues(timeline_mod)
        self.assertEqual(log, "a,b")  # in time order, once each, a failing cue does not stop the rest
        self.assertEqual(fired, 3)
        self.assertFalse(done)
        clip = req(utils.ClipPlayer)
        locate = lua.eval("function(C) local i, a = C.locate({0, 0.5, 1}, 0.75) return i, a end")
        i, a = locate(clip)
        self.assertEqual(i, 2)
        self.assertAlmostEqual(a, 0.5)
        crossed = lua.eval("function(C) local m = {{t = 0.1, name = 'A'}, {t = 0.9, name = 'B'}} "
                           "return table.concat(C.crossed(m, 0.8, 0.2, 1.0, true), ',') end")
        self.assertEqual(crossed(clip), "B,A")  # loop wrap fires both, in order

    def test_full_playback_restores_everything(self):
        lua, mock = self.runtime()
        G = lua.globals()
        api = lua.execute(self.sim.SCENARIO)
        cam = G.workspace.CurrentCamera
        base_ws, base_conn = G.COUNT_WORKSPACE(), mock.liveConnections
        shelf = {}

        def sampler(c):
            if c.state == "playing" and 14.5 <= c.time < 14.52 and not shelf:
                o = c.ctx.set.origin
                for name, prop in c.ctx.props.items():
                    if name.startswith(("Stock", "Cascade")):
                        p = prop if prop.ClassName != "Model" else prop.PrimaryPart
                        local = o.ToObjectSpace(o, p.CFrame)
                        shelf[name] = (local.Position.X, local.Position.Y - p.Size.Y / 2, p.Size.X)

        self.assertTrue(api.playFor(36.5, sampler))
        cin = api.cin
        self.assertEqual(cin.state, "idle")
        self.assertEqual(len(api.finished), 1)
        stats = api.finished[1].stats
        self.assertEqual(stats.errors, 0)
        self.assertEqual(cam.CameraType.Name, "Custom")
        self.assertEqual(cam.FieldOfView, 70)
        self.assertEqual(G.COUNT_WORKSPACE() - base_ws, 0, "instances left behind")
        self.assertEqual(mock.liveConnections - base_conn, 0, "connections left behind")
        self.assertEqual(G.CAS_BOUND, 0)
        self.assertTrue(G.CONTROLS.enabled)
        self.assertTrue(G.game.GetService(G.game, "Players").LocalPlayer.PlayerGui.GameHUD.Enabled)
        # products on shelf A rest on a board and do not overlap their neighbours
        boards = (0.6, 2.0, 3.7)
        self.assertGreaterEqual(len(shelf), 10)
        for name, (x, bottom, w) in shelf.items():
            self.assertTrue(any(abs(bottom - b) < 0.02 for b in boards), f"{name} floats at {bottom:.2f}")
        items = sorted(shelf.values())
        for (x0, b0, w0), (x1, b1, w1) in zip(items, items[1:]):
            if abs(b0 - b1) < 0.02:
                self.assertGreaterEqual(x1 - x0, (w0 + w1) / 2 - 0.01, "products overlap on a board")
        # skip mid-scene, then replay: same clean state
        api.playFor(9.0)
        cin.skip(cin)
        api.steps(90)
        self.assertEqual(cin.state, "idle")
        self.assertEqual(G.COUNT_WORKSPACE() - base_ws, 0)
        self.assertEqual(mock.liveConnections - base_conn, 0)


if __name__ == "__main__":
    unittest.main()
