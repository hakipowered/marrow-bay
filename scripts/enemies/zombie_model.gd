class_name ZombieModel
extends Node3D
## Enemy body. Loads res://assets/characters/enemies/<variant>/<look>.glb (rigged)
## when present; otherwise builds a stand-in whose silhouette matches the type
## (hunched shambler, low crawler, four-legged hound, bloated, hulking brute,
## long-limbed ventling, swollen brood mother).

var variant := "shambler"
var look := "office"
var data: Dictionary = {}
var _parts := {}
var _anim: AnimationPlayer
var _t := 0.0
var _dead := false
var _base_y := 0.0

const LOOK_COLORS := {
	# clothes, trousers, skin
	"office": [Color(0.55, 0.57, 0.6), Color(0.15, 0.15, 0.18), Color(0.47, 0.49, 0.4)],
	"nurse": [Color(0.4, 0.55, 0.6), Color(0.4, 0.55, 0.6), Color(0.5, 0.5, 0.42)],
	"cook": [Color(0.8, 0.78, 0.72), Color(0.2, 0.2, 0.2), Color(0.46, 0.46, 0.38)],
	"jogger": [Color(0.75, 0.25, 0.2), Color(0.1, 0.1, 0.12), Color(0.48, 0.45, 0.36)],
	"cop": [Color(0.12, 0.14, 0.22), Color(0.1, 0.1, 0.14), Color(0.42, 0.44, 0.36)],
	"mechanic": [Color(0.25, 0.3, 0.4), Color(0.25, 0.3, 0.4), Color(0.44, 0.42, 0.34)],
	"student": [Color(0.3, 0.45, 0.25), Color(0.2, 0.25, 0.4), Color(0.5, 0.48, 0.4)],
	"suit": [Color(0.1, 0.1, 0.11), Color(0.1, 0.1, 0.11), Color(0.45, 0.46, 0.38)],
	"courier": [Color(0.9, 0.6, 0.1), Color(0.15, 0.15, 0.15), Color(0.48, 0.46, 0.38)],
	"riot": [Color(0.08, 0.08, 0.09), Color(0.08, 0.08, 0.09), Color(0.4, 0.42, 0.35)],
	"bloated": [Color(0.5, 0.45, 0.35), Color(0.3, 0.25, 0.2), Color(0.55, 0.56, 0.36)],
	"brute": [Color(0.2, 0.1, 0.08), Color(0.12, 0.1, 0.1), Color(0.38, 0.32, 0.3)],
	"screamer": [Color(0.6, 0.55, 0.5), Color(0.3, 0.28, 0.25), Color(0.6, 0.58, 0.55)],
	"burnt": [Color(0.08, 0.06, 0.05), Color(0.08, 0.06, 0.05), Color(0.15, 0.08, 0.05)],
	"grappler": [Color(0.3, 0.2, 0.18), Color(0.15, 0.12, 0.1), Color(0.5, 0.35, 0.3)],
	"ventling": [Color(0.42, 0.3, 0.3), Color(0.42, 0.3, 0.3), Color(0.55, 0.38, 0.36)],
	"spitter": [Color(0.4, 0.45, 0.25), Color(0.3, 0.3, 0.2), Color(0.5, 0.58, 0.3)],
	"hound": [Color(0.25, 0.18, 0.15), Color(0.25, 0.18, 0.15), Color(0.45, 0.25, 0.22)],
	"larva": [Color(0.75, 0.7, 0.55), Color(0.75, 0.7, 0.55), Color(0.75, 0.7, 0.55)],
	"brood": [Color(0.45, 0.2, 0.25), Color(0.35, 0.15, 0.2), Color(0.6, 0.35, 0.35)],
}

func _ready() -> void:
	var path := "res://assets/characters/enemies/%s/%s.glb" % [variant, look]
	if not ResourceLoader.exists(path):
		path = "res://assets/characters/enemies/%s/%s.glb" % [variant, variant]
	if ResourceLoader.exists(path):
		var m: Node3D = load(path).instantiate()
		add_child(m)
		_anim = m.find_child("AnimationPlayer", true, false)
		return
	var c: Array = LOOK_COLORS.get(look, LOOK_COLORS["office"])
	if data.get("quadruped"):
		_build_hound(c)
	elif data.get("crawl"):
		_build_crawler(c)
	else:
		_build_biped(c)
	if look == "burnt":
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.45, 0.1)
		l.light_energy = 1.2
		l.omni_range = 3.0
		l.position.y = 1.2
		add_child(l)
		l.set_script(preload("res://scripts/world/flicker.gd"))
	if variant == "ventling" or variant == "possum":
		visible = variant != "ventling"
		if variant == "possum":
			rotation.x = -PI / 2
			position.y = 0.15

func _mesh(kind: String, size: Vector3, pos: Vector3, color: Color, rough := 0.85) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh: PrimitiveMesh
	match kind:
		"cap":
			mesh = CapsuleMesh.new()
			mesh.radius = size.x / 2
			mesh.height = max(size.y, size.x + 0.01)
		"sphere":
			mesh = SphereMesh.new()
			mesh.radius = size.x / 2
			mesh.height = size.y
		_:
			mesh = BoxMesh.new()
			mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = Mats.trim(color, rough)
	add_child(mi)
	return mi

func _build_biped(c: Array) -> void:
	var b: float = data.get("bulk", 1.0)
	var h: float = data.get("height", 1.0)
	var long_arms := 1.6 if variant == "ventling" else 1.0
	_parts["head"] = _mesh("cap", Vector3(0.2, 0.25, 0.22) * (1.15 if variant == "screamer" else 1.0), Vector3(0, 1.58 * h, 0.1), c[2])
	_parts["torso"] = _mesh("sphere" if variant in ["bloater", "brood_mother"] else "box", Vector3(0.42 * b, 0.6 * h, 0.26 * b) if variant not in ["bloater", "brood_mother"] else Vector3(0.7 * b, 0.8, 0.7 * b), Vector3(0, 1.2 * h, 0.04), c[0])
	_parts["arm_l"] = _mesh("cap", Vector3(0.1 * b, 0.6 * h * long_arms, 0.1), Vector3(-0.3 * b, 1.25 * h - (long_arms - 1) * 0.3, -0.15), c[2])
	_parts["arm_r"] = _mesh("cap", Vector3(0.1 * b, 0.6 * h * long_arms, 0.1), Vector3(0.3 * b, 1.25 * h - (long_arms - 1) * 0.3, -0.15), c[2])
	_parts["leg_l"] = _mesh("cap", Vector3(0.15 * b, 0.9 * h, 0.15), Vector3(-0.12 * b, 0.45 * h, 0), c[1])
	_parts["leg_r"] = _mesh("cap", Vector3(0.15 * b, 0.9 * h, 0.15), Vector3(0.12 * b, 0.45 * h, 0), c[1])
	_parts["arm_l"].rotation.x = -1.3
	_parts["arm_r"].rotation.x = -1.1
	_parts["torso"].rotation.x = 0.25 if variant != "brute" else 0.1
	if data.get("shield"):
		_parts["shield"] = _mesh("box", Vector3(0.6, 1.0, 0.04), Vector3(-0.1, 1.15, -0.45), Color(0.25, 0.28, 0.3), 0.2)
		_parts["shield"].material_override.metallic = 0.6
		_parts["helmet"] = _mesh("sphere", Vector3(0.27, 0.24, 0.27), Vector3(0, 1.66, 0.08), Color(0.1, 0.1, 0.11), 0.3)
	if variant == "spitter":
		_parts["sac"] = _mesh("sphere", Vector3(0.35, 0.3, 0.3), Vector3(0, 1.38, 0.05), Color(0.55, 0.8, 0.15), 0.2)
	if variant == "brood_mother":
		for i in 6:
			_mesh("sphere", Vector3(0.35, 0.35, 0.35), Vector3(cos(i) * 0.8, 0.4 + i * 0.12, sin(i) * 0.8), Color(0.7, 0.6, 0.4), 0.3)

func _build_crawler(c: Array) -> void:
	var s := 0.35 if data.get("tiny") else 1.0
	_parts["torso"] = _mesh("box", Vector3(0.44, 0.26, 0.7) * s, Vector3(0, 0.22, -0.2) * s, c[0])
	_parts["head"] = _mesh("cap", Vector3(0.2, 0.25, 0.22) * s, Vector3(0, 0.3, -0.68) * s, c[2])
	_parts["arm_l"] = _mesh("cap", Vector3(0.1, 0.6, 0.1) * s, Vector3(-0.28, 0.15, -0.75) * s, c[2])
	_parts["arm_r"] = _mesh("cap", Vector3(0.1, 0.6, 0.1) * s, Vector3(0.28, 0.15, -0.75) * s, c[2])
	_parts["arm_l"].rotation.x = -1.4
	_parts["arm_r"].rotation.x = -1.4

func _build_hound(c: Array) -> void:
	_parts["torso"] = _mesh("cap", Vector3(0.3, 0.85, 0.3), Vector3(0, 0.55, 0), c[0])
	_parts["torso"].rotation.x = PI / 2
	_parts["head"] = _mesh("box", Vector3(0.2, 0.2, 0.32), Vector3(0, 0.65, -0.55), c[2])
	for x in [-0.12, 0.12]:
		for z in [-0.3, 0.3]:
			_parts["leg_%s_%s" % [x, z]] = _mesh("cap", Vector3(0.08, 0.5, 0.08), Vector3(x, 0.25, z), c[1])

func attach_hitbox(_zone: String, _area: Area3D) -> void:
	pass  # hitboxes are created on the Zombie body itself

func animate(state: int, speed: float, crippled: bool, head_gone: bool) -> void:
	if _dead or _parts.is_empty():
		return
	_t += get_process_delta_time() * (2.0 + speed * 3.0)
	var sway: float = sin(_t) * 0.35 * clamp(speed, 0.0, 1.0)
	if _parts.has("leg_l"):
		_parts["leg_l"].rotation.x = sway
		_parts["leg_r"].rotation.x = -sway
	if _parts.has("torso") and not data.get("quadruped"):
		_parts["torso"].rotation.z = sin(_t * 0.5) * 0.08
	if head_gone and _parts.has("head"):
		_parts["head"].visible = false
	if crippled and not data.get("crawl") and not data.get("quadruped"):
		position.y = -0.7
		rotation.x = 1.2
	if state == Zombie.S.ATTACK and _parts.has("arm_l"):
		_parts["arm_l"].rotation.x = -1.6
		_parts["arm_r"].rotation.x = -1.6
	if variant == "bloater" and _parts.has("torso"):
		_parts["torso"].scale = Vector3.ONE * (1.0 + sin(_t * 0.7) * 0.04)

func hit_react(zone: String) -> void:
	var t := create_tween()
	t.tween_property(self, "rotation:y", rotation.y + randf_range(-0.15, 0.15), 0.06)
	t.tween_property(self, "rotation:y", rotation.y, 0.2)

func rise() -> void:
	var t := create_tween()
	t.tween_property(self, "rotation:x", 0.0, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "position:y", 0.0, 0.9)

func drop_from_ceiling() -> void:
	visible = true
	position.y = 3.0
	rotation.z = PI
	var t := create_tween()
	t.tween_property(self, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(self, "rotation:z", 0.0, 0.35)

func die(_head_gone: bool) -> void:
	_dead = true
	if _anim and _anim.has_animation("death"):
		_anim.play("death")
		return
	var t := create_tween()
	t.tween_property(self, "rotation:x", -PI / 2, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "position:y", 0.15, 0.6)
