# Render a GLB (or .blend) from a few angles with Cycles on the CPU.
import bpy, sys, math
from mathutils import Vector
args = sys.argv[sys.argv.index("--")+1:]
path, out = args[0], args[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
if path.endswith('.blend'):
    bpy.ops.wm.open_mainfile(filepath=path)
else:
    bpy.ops.import_scene.gltf(filepath=path)
sc = bpy.context.scene
sc.render.engine = 'CYCLES'
sc.cycles.device = 'CPU'
sc.cycles.samples = int(args[3]) if len(args) > 3 else 12
sc.cycles.use_denoising = False
sc.render.resolution_x = 640
sc.render.resolution_y = 480
frame = int(args[2]) if len(args) > 2 and args[2] != '-' else None
if frame is not None:
    sc.frame_set(frame)
w = bpy.data.worlds.new("w"); sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.57, 0.6, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 1.0
mins = Vector((1e9,)*3); maxs = Vector((-1e9,)*3)
dg = bpy.context.evaluated_depsgraph_get()
for o in sc.objects:
    if o.type == 'MESH':
        eo = o.evaluated_get(dg)
        for v in eo.to_mesh().vertices:
            p = eo.matrix_world @ v.co
            mins = Vector(map(min, mins, p)); maxs = Vector(map(max, maxs, p))
c = (mins + maxs) / 2; r = (maxs - mins).length * 0.75
sun = bpy.data.lights.new("s", 'SUN'); sun.energy = 3.0
so = bpy.data.objects.new("s", sun); sc.collection.objects.link(so)
so.rotation_euler = (math.radians(50), 0, math.radians(30))
cam = bpy.data.cameras.new("c"); cam.lens = 50
co = bpy.data.objects.new("c", cam); sc.collection.objects.link(co); sc.camera = co
views = {"side": (1, 0, 0.15), "front": (0, -1, 0.15), "q34": (0.8, -0.8, 0.45), "top": (0.001, -0.001, 1)}
for name, d in views.items():
    dv = Vector(d).normalized()
    co.location = c + dv * r * 2.2
    co.rotation_euler = (c - co.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = f"{out}_{name}.png"
    bpy.ops.render.render(write_still=True)
print("bounds", mins, maxs)
