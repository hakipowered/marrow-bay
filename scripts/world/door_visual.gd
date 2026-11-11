class_name DoorVisual
## Door leaves. Pivot sits on the hinge edge so swing doors rotate naturally.

static func build(style: String, width: float, height: float) -> Node3D:
	var pivot := Node3D.new()
	var leaf := Node3D.new()
	pivot.add_child(leaf)
	pivot.position.x = -width / 2 if style not in ["glass", "shutter"] else 0.0
	leaf.position.x = width / 2 if style not in ["glass", "shutter"] else 0.0
	match style:
		"wood_panel":
			_slab(leaf, Vector3(width, height, 0.06), Vector3(0, height / 2, 0), Mats.surface("archive_wainscot", {"tile_size": 1.0, "grime_amount": 0.3}))
			for row in 2:
				for col in 2:
					_slab(leaf, Vector3(width * 0.36, height * 0.36, 0.08), Vector3((col - 0.5) * width * 0.44, height * (0.28 + row * 0.44), 0), Mats.trim(Color(0.18, 0.1, 0.06), 0.4))
			_handle(leaf, Vector3(width * 0.38, 1.0, 0.06), Color(0.75, 0.6, 0.3))
		"steel":
			_slab(leaf, Vector3(width, height, 0.12), Vector3(0, height / 2, 0), Mats.surface("boiler_wall", {"tile_size": 1.5, "grime_amount": 0.2}))
			_slab(leaf, Vector3(0.3, 0.3, 0.06), Vector3(0, 1.5, 0.07), Mats.trim(Color(0.2, 0.2, 0.22), 0.3, 0.9))
			_handle(leaf, Vector3(width * 0.38, 1.05, 0.1), Color(0.6, 0.6, 0.62))
		"glass":
			var g := StandardMaterial3D.new()
			g.albedo_color = Color(0.7, 0.85, 0.9, 0.25)
			g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			g.roughness = 0.05
			g.metallic_specular = 1.0
			_slab(leaf, Vector3(width, height, 0.03), Vector3(0, height / 2, 0), g)
			_slab(leaf, Vector3(width, 0.08, 0.06), Vector3(0, 0.04, 0), Mats.trim(Color(0.6, 0.6, 0.6), 0.25, 1.0))
			_slab(leaf, Vector3(width, 0.08, 0.06), Vector3(0, height - 0.04, 0), Mats.trim(Color(0.6, 0.6, 0.6), 0.25, 1.0))
		"shutter":
			_slab(leaf, Vector3(width, height, 0.06), Vector3(0, height / 2, 0), Mats.surface("shutter", {"tile_size": 1.5}))
		"iron_gate":
			for i in int(width / 0.14):
				_slab(leaf, Vector3(0.03, height, 0.03), Vector3(-width / 2 + 0.07 + i * 0.14, height / 2, 0), Mats.trim(Color(0.08, 0.08, 0.08), 0.5, 0.8))
			for y in [0.2, height * 0.5, height - 0.15]:
				_slab(leaf, Vector3(width, 0.05, 0.05), Vector3(0, y, 0), Mats.trim(Color(0.08, 0.08, 0.08), 0.5, 0.8))
	return pivot

static func _slab(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)

static func _handle(parent: Node3D, pos: Vector3, color: Color) -> void:
	for z in [-1, 1]:
		var mi := MeshInstance3D.new()
		var s := CylinderMesh.new()
		s.top_radius = 0.018
		s.bottom_radius = 0.018
		s.height = 0.14
		mi.mesh = s
		mi.rotation_degrees.z = 90
		mi.position = pos * Vector3(1, 1, z)
		mi.material_override = Mats.trim(color, 0.25, 1.0)
		parent.add_child(mi)
