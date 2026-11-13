# Contact sheet of an action: N frames from one camera, Cycles CPU.
import bpy, sys, math
from mathutils import Vector
args = sys.argv[sys.argv.index("--")+1:]
blend, action, out = args[0], args[1], args[2]
n = int(args[3]) if len(args) > 3 else 8
view = args[4] if len(args) > 4 else "side"
bpy.ops.wm.open_mainfile(filepath=blend)
sc = bpy.context.scene
arm = bpy.data.objects["hound_rig"]
act = bpy.data.actions[action]
arm.animation_data_create(); arm.animation_data.action = act
f0, f1 = act.frame_range
sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'; sc.cycles.samples = 6; sc.cycles.use_denoising = False
sc.render.resolution_x = 400; sc.render.resolution_y = 300
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.6, 0.62, 0.65, 1)
sun = bpy.data.lights.new("s", 'SUN'); sun.energy = 3.0
so = bpy.data.objects.new("s", sun); sc.collection.objects.link(so); so.rotation_euler = (math.radians(50), 0, math.radians(30))
# ground grid
bpy.ops.mesh.primitive_plane_add(size=4)
g = bpy.context.active_object
m = bpy.data.materials.new("g"); m.use_nodes = True
bsdf = m.node_tree.nodes["Principled BSDF"]
tex = m.node_tree.nodes.new("ShaderNodeTexChecker"); tex.inputs["Scale"].default_value = 20
tex.inputs["Color1"].default_value = (0.35, 0.35, 0.35, 1); tex.inputs["Color2"].default_value = (0.45, 0.45, 0.45, 1)
m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
g.data.materials.append(m)
cam = bpy.data.cameras.new("c"); cam.lens = 40
co = bpy.data.objects.new("c", cam); sc.collection.objects.link(co); sc.camera = co
c = Vector((0, 0, 0.45))
d = {"side": Vector((1, 0, 0.12)), "q34": Vector((0.75, -0.75, 0.5)), "front": Vector((0.15, -1, 0.25)), "back": Vector((-0.6, 0.8, 0.5))}[view].normalized()
co.location = c + d * 2.6
co.rotation_euler = (c - co.location).to_track_quat('-Z', 'Y').to_euler()
import os
paths = []
for i in range(n):
    f = f0 + (f1 - f0) * i / max(1, n - 1 if action.startswith(("death", "lunge", "bite", "hit")) else n)
    sc.frame_set(int(round(f)))
    p = f"{out}_{i:02d}.png"; sc.render.filepath = p
    bpy.ops.render.render(write_still=True); paths.append((p, int(round(f))))
print("FRAMES", paths)
