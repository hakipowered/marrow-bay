class_name ItemVisual
## World models for pickups. Uses CC0 models where one exists, else a crafted mesh.

const MODEL_FOR := {
	"ammo": "ammo_box", "weapon:p9": "service_pistol", "weapon:longshot": "bolt_action_rifle_7_62",
	"weapon:hatchet": "hatchet", "weapon:knife": "machete", "weapon:frag": "stick_grenade",
	"medkit": "medical_box", "herb_green": "fern_02", "herb_red": "fern_02", "herb_mix": "fern_02", "herb_gg": "fern_02",
}

## Key items with their own scanned models (assets/props/<id>/<id>.glb,
## see tools/props/README.md): the model and its longest side in metres.
const PROP_FOR := {
	"key:fuse": ["fuse", 0.16], "key:clock_key": ["clock_key", 0.12],
	"key:crank_handle": ["crank_handle", 0.5],
}

static func build(item: String) -> Node3D:
	var root := Node3D.new()
	if PROP_FOR.has(item) and ResourceLoader.exists("res://assets/props/%s/%s.glb" % [PROP_FOR[item][0], PROP_FOR[item][0]]):
		var m := UndercroftKit.meshy(root, PROP_FOR[item][0], Vector3.ZERO, randf() * 360.0, PROP_FOR[item][1], false)
		m.position.y = 0.005
		return root
	if item == "key:diesel_can":
		# The jerrycan from the coal yard shed: the CC0 can, full size.
		var path := "res://assets/polyhaven/models/metal_jerrycan/metal_jerrycan.gltf"
		if ResourceLoader.exists(path):
			var j: Node3D = load(path).instantiate()
			j.rotation_degrees.y = randf() * 360.0
			root.add_child(j)
			return root
	# Guns, blades and grenades use the same models the survivors hold, lying
	# on their side.
	if item.begins_with("weapon:"):
		var g := HeldWeapon.build_model(item.substr(7))
		if g:
			var box: AABB = g.get_meta("aabb")
			var holder := Node3D.new()
			holder.add_child(g)
			g.position = -box.get_center()
			holder.rotation = Vector3(0, randf() * TAU, PI / 2.0)
			holder.position.y = box.size.x * 0.5 + 0.01
			root.add_child(holder)
			return root
	var key := item if MODEL_FOR.has(item) else item.split(":")[0]
	var name: String = MODEL_FOR.get(key, "")
	if name != "":
		var path := "res://assets/polyhaven/models/%s/%s.gltf" % [name, name]
		if ResourceLoader.exists(path):
			var m: Node3D = load(path).instantiate()
			var s := {"ammo_box": 0.6, "fern_02": 0.35, "medical_box": 0.7, "bolt_action_rifle_7_62": 0.9}.get(name, 1.0)
			m.scale = Vector3.ONE * s
			m.rotation_degrees.y = randf() * 360.0
			if item.begins_with("weapon"):
				m.rotation_degrees.z = 90
				m.position.y = 0.04
			root.add_child(m)
			return root
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.18, 0.06, 0.12) if not item.begins_with("key") else Vector3(0.09, 0.015, 0.03)
	mi.mesh = b
	mi.position.y = b.size.y / 2
	var c := Color(0.55, 0.75, 0.9) if item.begins_with("key") else Color(0.6, 0.55, 0.45)
	mi.material_override = Mats.trim(c, 0.35, 0.6 if item.begins_with("key") else 0.0)
	root.add_child(mi)
	return root
