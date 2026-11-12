extends SceneTree
## Bust size per outfit at the top of the Chest slider: how far the bust
## stands out in front of the ribs just below it, in centimetres, on the
## A-pose rest with the body shader's shaping redone on the CPU. Also prints
## the size at the middle of the slider, and the chest inflate ("chest_max"
## in scripts/player/outfits.gd) that would bring each outfit to the target.
##   godot --headless --path . --script tests/chest_check.gd -- [character] [target_cm]
## Fails when an outfit's top size is more than 0.6 cm off the target.
const TARGETS := {"obcera": 11.5}
var jobs := []
var cur: CharacterModel
var frames := 0
var bad := 0
var character := "obcera"
var target := 0.0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		character = a[0]
	target = float(a[1]) if a.size() > 1 else TARGETS.get(character, 0.0)
	jobs = CharacterModel.outfits(character)

## The rest-pose body: skinned vertices near the chest, in skeleton space.
static func rest_verts(model: CharacterModel) -> PackedVector3Array:
	var mi: MeshInstance3D = model._body_mesh
	var skel: Skeleton3D = model._skel
	var skin: Skin = mi.skin
	var xf := []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = skel.find_bone(skin.get_bind_name(b))
		xf.append(skel.get_bone_global_rest(bone) * skin.get_bind_pose(b))
	var arr := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / verts.size()
	var out := PackedVector3Array()
	for i in verts.size():
		var p := Vector3.ZERO
		for k in per:
			var wt := weights[i * per + k]
			if wt > 0.0:
				p += (xf[bones[i * per + k]] * verts[i]) * wt
		if p.y > 85.0 and p.y < 150.0 and p.z > -5.0 and absf(p.x) < 25.0:
			out.append(p)
	return out

## The regions as the body shader gets them, on the rest pose.
static func regions(model: CharacterModel) -> Array:
	var out := []
	for rg in model._regions:
		var def: Dictionary = rg["def"]
		var rest := model._skel.get_bone_global_rest(rg["bone"])
		out.append({"c": rest * rg["local"], "r": def["r"], "fwd": (rest.basis * rg["fwd_local"]).normalized(),
			"mask": def["mask"], "inflate": model._region_inflate(def), "chest": def["slider"] == "chest",
			"group": def.get("group", 0)})
	return out

## character_body.gdshader's vertex() shaping, without the springs.
static func shaped(v: Vector3, regs: Array, chest: float) -> Vector3:
	var add := Vector3.ZERO
	var ws := []
	for g in regs:
		ws.append(1.0 - smoothstep(0.55, 1.0, ((v - g["c"]) / (g["r"] as Vector3).max(Vector3.ONE * 1e-3)).length()))
	for i in regs.size():
		var g: Dictionary = regs[i]
		var rel: Vector3 = v - g["c"]
		var w: float = ws[i]
		if w <= 0.0:
			continue
		var share := 1.0
		if g["group"] > 0:
			var total := 0.0
			for j in regs.size():
				if regs[j]["group"] == g["group"]:
					total += maxf(ws[j], 0.0)
			share = w / maxf(total, 1e-4)
		w *= share
		var f := (rel + Vector3.ONE * 1e-4).normalized().dot(g["fwd"])
		var m := lerpf(1.0, smoothstep(-0.25, 0.35, f), g["mask"])
		var grow: Vector3 = rel.lerp(g["fwd"] * rel.length(), 0.35 * g["mask"])
		add += grow * (chest if g["chest"] else g["inflate"]) * m * w
	return v + add

## Mean over both sides of the bust's front minus the ribs' front below it.
static func bust(verts: PackedVector3Array, regs: Array, chest: float) -> float:
	var total := 0.0
	var sides := 0
	for g in regs:
		if not g["chest"]:
			continue
		var c: Vector3 = g["c"]
		var r: Vector3 = g["r"]
		var front := -INF
		var ribs := -INF
		for v in verts:
			if absf(v.x - c.x) > r.x * 0.6:
				continue
			var dy := v.y - c.y
			if absf(dy) < r.y * 0.8:
				front = maxf(front, shaped(v, regs, chest).z)
			elif dy < -r.y and dy > -r.y * 1.25:
				ribs = maxf(ribs, shaped(v, regs, chest).z)
		total += front - ribs
		sides += 1
	return total / maxf(sides, 1)

func _process(_d: float) -> bool:
	frames += 1
	if cur == null:
		if jobs.is_empty():
			print("CHEST CHECK ", "OK" if bad == 0 else "FAILED (%d)" % bad)
			quit(1 if bad else 0)
			return false
		cur = CharacterModel.new()
		cur.character = character
		cur.customization = {"outfit": jobs[0], "chest": 1.0}
		root.add_child(cur)
		frames = 0
		return false
	if frames == 3:
		var o: String = jobs.pop_front()
		var verts := rest_verts(cur)
		var regs := regions(cur)
		var top := 0.0
		var mid := 0.0
		for g in regs:
			if g["chest"]:
				top = g["inflate"]
				mid = cur._regions[regs.find(g)]["def"]["base"]
				break
		var at_top := bust(verts, regs, top)
		var at_mid := bust(verts, regs, mid)
		# Inflate that reaches the target, by bisection (size grows with it).
		var lo := 0.0
		var hi := 3.0
		for i in 18:
			var k := (lo + hi) * 0.5
			if bust(verts, regs, k) < target:
				lo = k
			else:
				hi = k
		var ok := absf(at_top - target) <= 0.6
		if not ok:
			bad += 1
		print("%-8s %-14s middle %5.2f cm   top %5.2f cm (inflate %.2f)   target %.1f cm needs %.2f%s" % [character, o, at_mid, at_top, top, target, (lo + hi) * 0.5, "" if ok else "  <-- off"])
		cur.free()
		cur = null
	return false
