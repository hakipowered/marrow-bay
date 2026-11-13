# Part of tools/hound/build.sh (see there). Stage 1 of the infected hound.
# Stage 1: import the scanned hound, size and place it, build a quadruped
# skeleton from measured landmarks, skin it with heat weights, save a .blend.
import bpy, sys, math, bmesh
from mathutils import Vector, Matrix
args = sys.argv[sys.argv.index("--")+1:]
src, out = args[0], args[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
import numpy as np

S = 0.72
mesh = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
mesh.name = "hound_body"
me = mesh.data
co = np.array([v.co for v in me.vertices])
M = np.array(mesh.matrix_world)
wco = (M[:3, :3] @ co.T).T + M[:3, 3]
z0 = wco[:, 2].min()
YMID = (-0.455 + 0.515) / 2
# Bake: world -> metres, feet on the floor, centred between the paws.
T = Matrix.Translation((0, -YMID * S, -z0 * S)) @ Matrix.Scale(S, 4) @ mesh.matrix_world
me.transform(T)
mesh.matrix_world = Matrix.Identity(4)
# Weld the UV-seam splits so skinning sees one surface.
bm = bmesh.new(); bm.from_mesh(me)
before = len(bm.verts)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0004)
bm.to_mesh(me); bm.free()
print("welded", before, "->", len(me.vertices))

# Bones: name, head, tail, parent, deform. Dog faces -Y, +X is its left.
B = []
def bone(n, h, t, p=None, d=True):
    B.append((n, Vector(h), Vector(t), p, d))
bone("root", (0, 0, 0), (0, -0.3, 0), None, False)
bone("body", (0, 0.02, 0.57), (0, -0.08, 0.57), "root", False)
bone("pelvis", (0, 0.06, 0.575), (0, 0.31, 0.60), "body")
bone("spine1", (0, 0.06, 0.575), (0, -0.09, 0.585), "body")
bone("spine2", (0, -0.09, 0.585), (0, -0.23, 0.595), "spine1")
bone("chest", (0, -0.23, 0.595), (0, -0.33, 0.625), "spine2")
bone("neck1", (0, -0.33, 0.625), (0, -0.40, 0.70), "chest")
bone("neck2", (0, -0.40, 0.70), (0, -0.465, 0.775), "neck1")
bone("head", (0, -0.465, 0.79), (0, -0.70, 0.79), "neck2")
bone("jaw", (0, -0.49, 0.745), (0, -0.665, 0.70), "head")
for s, sx in (("L", 1), ("R", -1)):
    bone("ear_" + s, (0.07 * sx, -0.49, 0.855), (0.085 * sx, -0.495, 0.94), "head")
    bone("scapula_" + s, (0.075 * sx, -0.26, 0.66), (0.105 * sx, -0.335, 0.50), "chest")
    bone("upperarm_" + s, (0.105 * sx, -0.335, 0.50), (0.10 * sx, -0.27, 0.355), "scapula_" + s)
    bone("forearm_" + s, (0.10 * sx, -0.27, 0.355), (0.088 * sx, -0.278, 0.095), "upperarm_" + s)
    bone("hand_" + s, (0.088 * sx, -0.278, 0.095), (0.105 * sx, -0.325, 0.035), "forearm_" + s)
    bone("fpaw_" + s, (0.105 * sx, -0.325, 0.035), (0.12 * sx, -0.39, 0.015), "hand_" + s)
    bone("thigh_" + s, (0.12 * sx, 0.30, 0.54), (0.13 * sx, 0.22, 0.37), "pelvis")
    bone("shin_" + s, (0.13 * sx, 0.22, 0.37), (0.122 * sx, 0.385, 0.175), "thigh_" + s)
    bone("foot_" + s, (0.122 * sx, 0.385, 0.175), (0.15 * sx, 0.365, 0.04), "shin_" + s)
    bone("hpaw_" + s, (0.15 * sx, 0.365, 0.04), (0.165 * sx, 0.31, 0.015), "foot_" + s)
bone("tail1", (0, 0.33, 0.62), (0, 0.42, 0.615), "pelvis")
bone("tail2", (0, 0.42, 0.615), (0, 0.51, 0.612), "tail1")
bone("tail3", (0, 0.51, 0.612), (0, 0.59, 0.622), "tail2")
bone("tail4", (0, 0.59, 0.622), (0, 0.67, 0.64), "tail3")

arm_data = bpy.data.armatures.new("hound_rig")
arm = bpy.data.objects.new("hound_rig", arm_data)
bpy.context.scene.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
for n, h, t, p, d in B:
    eb = arm_data.edit_bones.new(n)
    eb.head, eb.tail = h, t
    eb.use_deform = d
    # Roll: keep each bone's local X pointing to the dog's left (+X world),
    # so bending a leg forward/back is a rotation about local X.
    eb.align_roll(Vector((0, 0, 1)) if abs((t - h).normalized().z) < 0.7 else Vector((0, -1, 0)))
for n, h, t, p, d in B:
    if p:
        eb = arm_data.edit_bones[n]
        eb.parent = arm_data.edit_bones[p]
        eb.use_connect = (eb.head - eb.parent.tail).length < 1e-4
bpy.ops.object.mode_set(mode='OBJECT')

# Heat-weight skinning.
bpy.ops.object.select_all(action='DESELECT')
mesh.select_set(True); arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
vg = {g.index: g.name for g in mesh.vertex_groups}
unw = [v.index for v in me.vertices if not any(g.weight > 1e-4 for g in v.groups)]
print("vertex groups", len(mesh.vertex_groups), "unweighted verts", len(unw))
bpy.ops.wm.save_as_mainfile(filepath=out)
