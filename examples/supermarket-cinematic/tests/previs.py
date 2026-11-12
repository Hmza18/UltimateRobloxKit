"""Previs: render what the cinematic's camera sees, from the runtime's own geometry.

    python3 tests/previs.py <blender-python>     (needs lupa + Pillow; Blender: the bpy module or the app)

1. Runs the real Luau runtime headless (tests/sim.py) and snapshots every visible part (size, CFrame,
   colour, shape, transparency) plus the camera CFrame / vertical FOV at story beats.
2. Renders each snapshot in Blender (Workbench) with the same camera, and writes a labelled sheet.
Text (SurfaceGui), particles, UI and Roblox lighting are not reproduced: this checks staging,
framing, poses and prop placement, not final look.
"""
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
OUT = ROOT / "tests" / "previs"
BEATS = [0.5, 3.0, 5.9, 6.9, 8.5, 9.3, 10.4, 11.9, 12.6, 13.9, 15.6, 17.8, 19.65, 20.35, 23.4, 24.95, 27.15, 29.3, 31.4, 34.0]

SNAP = r'''
return function(cin, t)
	local folder = workspace:FindFirstChild("SupermarketCinematicAssets")
	local out = { t = t, parts = {} }
	local cam = workspace.CurrentCamera
	out.cam = { cam.CFrame:GetComponents() }
	out.fov = cam.FieldOfView
	out.shot = cin.director and cin.director.index > 0 and cin.director.shots[cin.director.index].name or ""
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") and (d.Transparency or 0) < 0.99 then
			local c = d.Color
			out.parts[#out.parts + 1] = { s = { d.Size.X, d.Size.Y, d.Size.Z }, cf = { d.CFrame:GetComponents() },
				c = { c.R, c.G, c.B }, a = d.Transparency or 0, sh = d.Shape and d.Shape.Name or (d.ClassName == "WedgePart" and "Wedge" or "Block"),
				n = d.Name }
		end
	end
	return out
end
'''


def capture():
    sys.path.insert(0, str(HERE))
    import sim
    lua, mock = sim.make_runtime()
    sim.load_tree(lua, mock)
    api = lua.execute(sim.SCENARIO)
    snap = lua.execute(SNAP)
    shots = []
    pending = list(BEATS)

    def sampler(c):
        if pending and c.state == "playing" and c.time >= pending[0]:
            t = pending.pop(0)
            s = snap(c, t)
            parts = [{"s": list(p.s.values()), "cf": list(p.cf.values()), "c": list(p.c.values()), "a": p.a, "sh": p.sh, "n": p.n}
                     for p in s.parts.values()]
            shots.append({"t": t, "shot": s.shot, "fov": s.fov, "cam": list(s.cam.values()), "parts": parts})

    api.playFor(35.0, sampler)
    return shots


BLENDER = r'''
import bpy, json, math, sys
from mathutils import Matrix
data = json.load(open(sys.argv[-2]))
outdir = sys.argv[-1]
P = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # Roblox (x, y, z) -> Blender (x, -z, y)

def m4(cf):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf
    return P @ Matrix(((r00, r01, r02, x), (r10, r11, r12, y), (r20, r21, r22, z), (0, 0, 0, 1)))

def mesh(kind):
    if kind in meshes:
        return meshes[kind]
    if kind == "Ball":
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.5, segments=16, ring_count=8)
    else:
        bpy.ops.mesh.primitive_cube_add(size=1)
    ob = bpy.context.active_object
    me = ob.data
    if kind == "Wedge":  # Roblox wedge: slope from top-back (+Z) down to bottom-front (-Z)
        for v in me.vertices:
            if v.co.z > 0 and v.co.y < 0:  # (after P) blender -y = roblox +z (back) ... keep top at back
                pass
    bpy.data.objects.remove(ob)
    meshes[kind] = me
    return me

for i, shot in enumerate(data):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    meshes = {}
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    scene.display.shading.show_shadows = True
    scene.display.shading.shadow_intensity = 0.35
    scene.display.shading.show_cavity = True
    scene.display.shading.show_object_outline = False
    scene.render.resolution_x, scene.render.resolution_y = 640, 360
    world = bpy.data.worlds.new("w"); scene.world = world
    world.color = (0.55, 0.75, 0.95)
    scene.display.shading.background_type = "WORLD"
    for p in shot["parts"]:
        me = mesh("Ball" if p["sh"] == "Ball" else "Block")
        ob = bpy.data.objects.new(p["n"], me)
        scene.collection.objects.link(ob)
        sx, sy, sz = p["s"]
        ob.matrix_world = m4(p["cf"]) @ Matrix.Diagonal((sx, sy, sz, 1))
        ob.color = (*p["c"], 1 - p["a"] * 0.8)
    cam = bpy.data.cameras.new("cam")
    cam.sensor_fit = "VERTICAL"
    cam.angle = math.radians(shot["fov"])
    cam.clip_end = 2000
    co = bpy.data.objects.new("cam", cam)
    scene.collection.objects.link(co)
    co.matrix_world = m4(shot["cam"])
    scene.camera = co
    scene.render.filepath = f"{outdir}/beat_{i:02d}.png"
    bpy.ops.render.render(write_still=True)
'''


def render(blender_python, shots):
    OUT.mkdir(parents=True, exist_ok=True)
    data = OUT / "snapshots.json"
    data.write_text(json.dumps(shots), encoding="utf-8")
    script = OUT / "_render.py"
    script.write_text(BLENDER, encoding="utf-8")
    cmd = [blender_python, str(script), str(data), str(OUT)]
    if Path(blender_python).name.startswith("blender"):
        cmd = [blender_python, "-b", "--python", str(script), "--", str(data), str(OUT)]
    subprocess.run(cmd, check=True, capture_output=True)
    script.unlink()


def sheet(shots):
    from PIL import Image, ImageDraw
    cols, w, h, lab = 4, 640, 360, 30
    rows = (len(shots) + cols - 1) // cols
    img = Image.new("RGB", (cols * w, rows * (h + lab)), (22, 23, 27))
    d = ImageDraw.Draw(img)
    bar = int(h * 0.085)
    for i, s in enumerate(shots):
        frame = Image.open(OUT / f"beat_{i:02d}.png").convert("RGB")
        fd = ImageDraw.Draw(frame)
        fd.rectangle([0, 0, w, bar], fill=(0, 0, 0))  # letterbox, as the UI draws it
        fd.rectangle([0, h - bar, w, h], fill=(0, 0, 0))
        r, c = divmod(i, cols)
        img.paste(frame, (c * w, r * (h + lab)))
        d.text((c * w + 8, r * (h + lab) + h + 8), f"t={s['t']:.2f}s  {s['shot']}  fov {s['fov']:.0f}  parts {len(s['parts'])}", fill=(235, 235, 235))
    path = OUT / "previs_sheet.jpg"
    img = img.resize((img.width * 3 // 4, img.height * 3 // 4))
    img.save(path, quality=82)
    for i in range(len(shots)):
        (OUT / f"beat_{i:02d}.png").unlink()
    return path


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    shots = capture()
    render(sys.argv[1], shots)
    print(sheet(shots))
    (OUT / "snapshots.json").unlink()


if __name__ == "__main__":
    main()
