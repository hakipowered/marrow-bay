class_name ZombieModel
extends Node3D
## Zombie body: rigged model at res://assets/characters/zombie_<variant>/... when
## available, else a hunched stand-in with torn-clothes colors per variant.

var variant := "civilian"
var _parts := {}
var _anim: AnimationPlayer
var _t := 0.0
var _dead := false

const COLORS := {
	"civilian": [Color(0.35, 0.33, 0.4), Color(0.2, 0.18, 0.16), Color(0.45, 0.47, 0.38)],
	"officer": [Color(0.12, 0.14, 0.22), Color(0.1, 0.1, 0.14), Color(0.42, 0.44, 0.36)],
	"bloated": [Color(0.5, 0.45, 0.35), Color(0.3, 0.25, 0.2), Color(0.5, 0.52, 0.38)],
	"brute": [Color(0.2, 0.1, 0.08), Color(0.12, 0.1, 0.1), Color(0.38, 0.36, 0.32)],
}

func _ready() -> void:
	var path := "res://assets/characters/zombie_%s/zombie_%s.glb" % [variant, variant]
	if ResourceLoader.exists(path):
		var m: Node3D = load(path).instantiate()
		add_child(m)
		_anim = m.find_child("AnimationPlayer", true, false)
		return
	var c: Array = COLORS.get(variant, COLORS["civilian"])
	var bulk := 1.35 if variant in ["bloated", "brute"] else 1.0
	var defs := {
		"head": [Vector3(0, 1.58, 0.1), Vector3(0.2, 0.25, 0.22), c[2], true],
		"torso": [Vector3(0, 1.2, 0.04), Vector3(0.42 * bulk, 0.6, 0.26 * bulk), c[0], false],
		"arm_l": [Vector3(-0.3 * bulk, 1.25, -0.15), Vector3(0.1, 0.6, 0.1), c[2], true],
		"arm_r": [Vector3(0.3 * bulk, 1.25, -0.15), Vector3(0.1, 0.6, 0.1), c[2], true],
		"leg_l": [Vector3(-0.12, 0.45, 0), Vector3(0.15, 0.9, 0.15), c[1], true],
		"leg_r": [Vector3(0.12, 0.45, 0), Vector3(0.15, 0.9, 0.15), c[1], true],
	}
	for k in defs:
		var mi := MeshInstance3D.new()
		var mesh: PrimitiveMesh
		if defs[k][3]:
			mesh = CapsuleMesh.new()
			mesh.radius = defs[k][1].x / 2
			mesh.height = defs[k][1].y
		else:
			mesh = BoxMesh.new()
			mesh.size = defs[k][1]
		mi.mesh = mesh
		mi.position = defs[k][0]
		var mat := Mats.trim(defs[k][2], 0.85)
		mi.material_override = mat
		add_child(mi)
		_parts[k] = mi
	_parts["arm_l"].rotation.x = -1.3
	_parts["arm_r"].rotation.x = -1.1
	_parts["torso"].rotation.x = 0.25

func attach_hitbox(zone: String, area: Area3D) -> void:
	# Hitboxes ride on the parent body; with a rig they would attach to bones
	# through BoneAttachment3D so they follow the animation exactly.
	get_parent().add_child.call_deferred(area)

func animate(state: int, speed: float, crippled: bool, head_gone: bool) -> void:
	if _dead or _parts.is_empty():
		return
	_t += get_process_delta_time() * (2.0 + speed * 3.0)
	var sway: float = sin(_t) * 0.35 * clamp(speed, 0.0, 1.0)
	_parts["leg_l"].rotation.x = sway
	_parts["leg_r"].rotation.x = -sway
	_parts["torso"].rotation.z = sin(_t * 0.5) * 0.08
	if head_gone and _parts.has("head"):
		_parts["head"].visible = false
	if crippled:
		position.y = -0.7
		rotation.x = 1.2
	if state == Zombie.S.ATTACK:
		_parts["arm_l"].rotation.x = -1.6
		_parts["arm_r"].rotation.x = -1.6

func hit_react(zone: String) -> void:
	if _parts.has(zone):
		var t := create_tween()
		t.tween_property(self, "rotation:x", -0.2, 0.06)
		t.tween_property(self, "rotation:x", 0.0, 0.2)

func die(_head_gone: bool) -> void:
	_dead = true
	if _anim and _anim.has_animation("death"):
		_anim.play("death")
		return
	var t := create_tween()
	t.tween_property(self, "rotation:x", -PI / 2, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "position:y", 0.15, 0.6)
