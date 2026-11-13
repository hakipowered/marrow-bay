# Part of tools/hound/build.sh: exports the hound without and with its clips.
import bpy, sys
args = sys.argv[sys.argv.index("--")+1:]
blend, out_model, out_anims = args
bpy.ops.wm.open_mainfile(filepath=blend)
arm = bpy.data.objects["hound_rig"]
mesh = bpy.data.objects["hound_body"]
# Drop the IK control bones.
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
for b in list(arm.data.edit_bones):
    if b.name.startswith(("tgt", "pole_")):
        arm.data.edit_bones.remove(b)
bpy.ops.object.mode_set(mode='OBJECT')
for a in bpy.data.actions:
    for fc in list(a.fcurves) if hasattr(a, "fcurves") else []:
        pass
print("actions", [a.name for a in bpy.data.actions])
common = dict(export_format='GLB', use_selection=False, export_yup=True, export_apply=False,
    export_texcoords=True, export_normals=True, export_tangents=False, export_materials='EXPORT',
    export_image_format='AUTO', export_skins=True, export_all_influences=False, export_def_bones=False)
arm.animation_data_create(); arm.animation_data.action = None
bpy.ops.export_scene.gltf(filepath=out_model, export_animations=False, **common)
bpy.ops.export_scene.gltf(filepath=out_anims, export_animations=True, export_animation_mode='ACTIONS',
    export_force_sampling=True, export_frame_range=False, export_anim_single_armature=True,
    export_reset_pose_bones=True, export_optimize_animation_size=False, **common)
